defmodule NYSETL.Monitoring.Transformer.FailureReporterTest do
  use NYSETL.DataCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  alias NYSETL.{Repo, ECLRS}
  alias NYSETL.Monitoring.Transformer.FailureReporter

  setup do
    {:ok, _oban} = start_supervised({Oban, queues: [commcare: 1], repo: NYSETL.Repo})
    :ok
  end

  test "counts the events of type `processing_failed` created the last week" do
    :ok = NYSETL.Engines.E1.ECLRSFileExtractor.extract!("test/fixtures/eclrs/new_records.txt")
    test_result = Repo.first(ECLRS.TestResult)
    {:ok, _} = ECLRS.save_event(test_result, "processing_failed")
    {:ok, _} = ECLRS.save_event(test_result, "processing_failed")
    {:ok, _} = ECLRS.save_event(test_result, "ignored")
    {:ok, old} = ECLRS.save_event(test_result, "processing_failed")

    {1, _} =
      from(e in NYSETL.Event, where: e.id == ^old.event_id)
      |> Repo.update_all(set: [inserted_at: eight_days_ago()])

    assert FailureReporter.count_processing_failed() == 2
  end

  test "behaves like a proper Oban job" do
    assert {:ok, 0} = perform_job(FailureReporter, %{anything: "goes"})
  end

  defp eight_days_ago,
    do: Date.utc_today() |> Date.add(-8) |> NaiveDateTime.new!(~T[00:00:00])
end
