defmodule NYSETL.Engines.E2.TestResultProducer do
  @moduledoc """
  Broadway producer. Finds TestResult records that have not previously been processed.

  ## Options

  * :event_filters : List : skips TestResult records where an Event exists with :type included
    in this list.
  * :idle_timeout_ms : Integer : wakes the producer if no events have been produced after this timeout.
    Fixes for GenStage consumer hibernation.
  """

  use GenStage
  import Ecto.Query
  alias NYSETL.ECLRS
  alias NYSETL.Repo
  require Logger

  defstruct ~w{
    event_filters
    idle_timeout_ms
    last_seen_id
    most_recent_demand_at
  }a

  def new(attrs \\ []), do: __struct__(attrs)

  def init(opts) do
    event_filters = Keyword.fetch!(opts, :event_filters)
    idle_timeout_ms = Keyword.get(opts, :idle_timeout_ms, 5_000)
    :timer.send_interval(100, self(), :poll)
    {:producer, new(event_filters: event_filters, idle_timeout_ms: idle_timeout_ms)}
  end

  def handle_demand(demand, state) do
    {elapsed_time, test_results} =
      :timer.tc(fn ->
        unprocessed_test_results(demand, state)
        |> more_recent_than(state.last_seen_id)
        |> Repo.all()
      end)

    case state.last_seen_id do
      0 -> :telemetry.execute([:transformer, :test_result_producer, :initial_query], %{time: elapsed_time / 1000})
      _ -> :telemetry.execute([:transformer, :test_result_producer, :subsequent_query], %{time: elapsed_time / 1000})
    end

    {:noreply, test_results, state |> with_most_recent_id(test_results) |> with_most_recent_demand_at()}
  end

  def handle_info(:poll, state) do
    state.most_recent_demand_at
    |> DateTime.compare(DateTime.utc_now() |> DateTime.add(-state.idle_timeout_ms, :millisecond))
    |> case do
      :lt -> handle_demand(10, %{state | last_seen_id: 0})
      _ -> {:noreply, [], state}
    end
  end

  def unprocessed_test_results(demand, state) do
    event_filters = state.event_filters

    from tr in ECLRS.TestResult,
      left_join: tre in ECLRS.TestResultEvent,
      on:
        tr.id == tre.test_result_id and
          tre.event_id in fragment(
            """
            select id from events e
            where e.type = any (?)
            """,
            ^event_filters
          ),
      where: is_nil(tre.event_id),
      limit: ^demand,
      order_by: [asc: :id]
  end

  def more_recent_than(query, nil), do: query
  def more_recent_than(query, id), do: query |> where([t], t.id > ^id)

  defp with_most_recent_id(state, []), do: state

  defp with_most_recent_id(state, test_results) do
    id = test_results |> List.last() |> Map.get(:id)
    %{state | last_seen_id: id}
  end

  defp with_most_recent_demand_at(state) do
    %{state | most_recent_demand_at: DateTime.utc_now()}
  end
end
