defmodule NYSETL.Engines.E2.TestResultProcessor do
  use Oban.Worker, queue: :eclrs, unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias NYSETL.ECLRS
  alias NYSETL.Repo
  alias NYSETL.Engines.E2.Processor

  @impl Oban.Worker
  def perform(%{args: %{"test_result_id" => test_result_id}}) do
    with test_result <- ECLRS.TestResult |> Repo.get(test_result_id),
         :ok <- Processor.process(test_result) do
      ECLRS.save_event(test_result, "processed")
      :ok
    else
      err -> err
    end
  end
end
