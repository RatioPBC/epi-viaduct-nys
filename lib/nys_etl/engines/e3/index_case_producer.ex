defmodule NYSETL.Engines.E3.IndexCaseProducer do
  @moduledoc """
  Find IndexCase records to process by the CommcareCaseLoader and created or updated in CommCare.
  """

  use GenStage
  import Ecto.Query
  alias NYSETL.Commcare
  alias NYSETL.Repo
  require Logger

  defstruct ~w{
    find_with_events_matching
    reject_with_events_matching
    idle_timeout_ms
    last_seen_id
    most_recent_demand_at
    case_count
  }a

  def new(attrs \\ []), do: __struct__(attrs)

  def start_link(args) do
    GenStage.start_link(__MODULE__, args)
  end

  def init(opts) do
    find_with_events_matching = Keyword.fetch!(opts, :find_with_events_matching)
    reject_with_events_matching = Keyword.fetch!(opts, :reject_with_events_matching)
    idle_timeout_ms = Keyword.get(opts, :idle_timeout_ms, 5_000)
    :timer.send_interval(poll_interval(), self(), :poll)

    {:producer,
     new(
       find_with_events_matching: find_with_events_matching,
       reject_with_events_matching: reject_with_events_matching,
       idle_timeout_ms: idle_timeout_ms,
       case_count: 0
     )}
  end

  # Uncomment this to stop producing after max_case_count cases.
  # @max_case_count 10
  # def handle_demand(_demand, %{case_count: n} = state) when n >= @max_case_count, do: {:noreply, [], state}

  def handle_demand(demand, state) do
    {elapsed_time, test_results} =
      :timer.tc(fn ->
        unprocessed_index_cases(demand, state.find_with_events_matching, state.reject_with_events_matching)
        |> more_recent_than(state.last_seen_id)
        |> Repo.all()
      end)

    case state.last_seen_id do
      0 -> :telemetry.execute([:loader, :index_case_producer, :initial_query], %{time: elapsed_time / 1000})
      _ -> :telemetry.execute([:loader, :index_case_producer, :subsequent_query], %{time: elapsed_time / 1000})
    end

    state =
      state
      |> with_most_recent_id(test_results)
      |> with_increased_case_count(test_results)
      |> with_most_recent_demand_at()

    {:noreply, test_results, state}
  end

  def handle_info(:poll, state) do
    state.most_recent_demand_at
    |> DateTime.compare(DateTime.utc_now() |> DateTime.add(-state.idle_timeout_ms, :millisecond))
    |> case do
      :lt -> handle_demand(batch_size(), %{state | last_seen_id: 0})
      _ -> {:noreply, [], state}
    end
  end

  def batch_size() do
    Application.get_env(:nys_etl, :e3_producer_batch_size)
  end

  def poll_interval() do
    Application.get_env(:nys_etl, :e3_producer_poll_interval)
  end

  @update_id_sql """
    case
        when type = any (?) then ?
        when type = any (?) then null
    end
  """

  @enqueue_id_sql """
    case
        when type = any (?) then null
        when type = any (?) then ?
    end
  """

  def unprocessed_index_cases(demand, find_with_events_matching, reject_with_events_matching) do
    all_event_types = find_with_events_matching ++ reject_with_events_matching

    from index_case in Commcare.IndexCase,
      where:
        index_case.id in subquery(
          from latest in subquery(
                 from updates_and_enqueues in subquery(
                        from event in NYSETL.Event,
                          join: ic_event in Commcare.IndexCaseEvent,
                          on: event.id == ic_event.event_id,
                          select: %{
                            index_case_id: ic_event.index_case_id,
                            update_id: fragment(@update_id_sql, ^find_with_events_matching, event.id, ^reject_with_events_matching),
                            enqueue_id: fragment(@enqueue_id_sql, ^find_with_events_matching, ^reject_with_events_matching, event.id)
                          },
                          where: event.type in ^all_event_types
                      ),
                      select: %{
                        index_case_id: updates_and_enqueues.index_case_id,
                        latest_update_id: max(updates_and_enqueues.update_id),
                        latest_enqueue_id: max(updates_and_enqueues.enqueue_id)
                      },
                      group_by: updates_and_enqueues.index_case_id
               ),
               select: %{
                 index_case_id: latest.index_case_id
               },
               where: latest.latest_enqueue_id < latest.latest_update_id or is_nil(latest.latest_enqueue_id)
        ),
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

  defp with_increased_case_count(%{case_count: n} = state, test_results) do
    %{state | case_count: n + length(test_results)}
  end
end
