defmodule NYSETL.Engines.E2.TestResultProducer do
  use Oban.Worker, queue: :eclrs, unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]
  use Agent

  import Ecto.Query

  alias NYSETL.Repo
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E2.TestResultProcessor

  @impl Oban.Worker
  def perform(%Job{args: %{"file_id" => file_id}}) do
    {:ok, _} =
      Repo.transaction(
        fn ->
          ECLRS.get_unprocessed_test_results()
          |> select([tr], tr.id)
          |> order_by([tr], asc: tr.eclrs_create_date)
          |> filter_by_file_id(file_id)
          |> Repo.stream()
          |> Stream.chunk_every(500)
          |> Stream.each(&enqueue_test_result_ids/1)
          |> Stream.run()
        end,
        timeout: :infinity
      )

    :ok
  end

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> :none end, name: __MODULE__)
  end

  def last_enqueued_test_result_id(), do: Agent.get(__MODULE__, & &1)
  defp update_last_enqueued_test_result_id(id), do: Agent.update(__MODULE__, fn _ -> id end)

  defp enqueue_test_result_ids(ids) do
    update_last_enqueued_test_result_id(List.last(ids))

    ids
    |> Enum.map(&TestResultProcessor.new(%{"test_result_id" => &1}))
    |> Oban.insert_all()
  end

  defp filter_by_file_id(query, "all"), do: query
  defp filter_by_file_id(query, file_id), do: query |> where(file_id: ^file_id)
end
