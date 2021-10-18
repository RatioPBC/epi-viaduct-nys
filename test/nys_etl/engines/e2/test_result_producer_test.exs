defmodule NYSETL.Engines.E2.Test do
  use NYSETL.DataCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  alias NYSETL.ECLRS
  alias NYSETL.Engines.E2.{TestResultProducer, TestResultProcessor}

  setup do
    {:ok, _oban} = start_supervised({Oban, queues: false, repo: NYSETL.Repo})
    {:ok, _} = start_supervised(TestResultProducer)
    {:ok, _county} = ECLRS.find_or_create_county(42)
    :ok
  end

  test "is unique" do
    # TODO: this should use Oban.insert_all, but it doesn't check uniqueness (at least not our current version)
    [1, 2, 1, 2]
    |> Enum.each(&(TestResultProducer.new(%{"file_id" => &1}) |> Oban.insert!()))

    assert [
             %Oban.Job{args: %{"file_id" => 2}},
             %Oban.Job{args: %{"file_id" => 1}}
           ] = all_enqueued(worker: TestResultProducer)
  end

  test "with %{file_id => file.id} enqueues a TestResultProcessor for each test result in the file" do
    {:ok, file1} = Factory.file_attrs(filename: "file1") |> ECLRS.create_file()
    {:ok, tr1} = Factory.test_result_attrs(county_id: 42, file_id: file1.id, raw_data: "tr1") |> ECLRS.create_test_result()
    {:ok, tr2} = Factory.test_result_attrs(county_id: 42, file_id: file1.id, raw_data: "tr2") |> ECLRS.create_test_result()
    {:ok, file2} = Factory.file_attrs(filename: "file2") |> ECLRS.create_file()
    {:ok, tr3} = Factory.test_result_attrs(county_id: 42, file_id: file2.id, raw_data: "tr3") |> ECLRS.create_test_result()

    assert :ok = perform_job(TestResultProducer, %{"file_id" => file1.id})
    assert_enqueued(worker: TestResultProcessor, args: %{"test_result_id" => tr1.id})
    assert_enqueued(worker: TestResultProcessor, args: %{"test_result_id" => tr2.id})
    refute_enqueued(worker: TestResultProcessor, args: %{"test_result_id" => tr3.id})
  end

  test "records the last enqueued test result id" do
    {:ok, file} = Factory.file_attrs(filename: "file") |> ECLRS.create_file()
    {:ok, tr} = Factory.test_result_attrs(county_id: 42, file_id: file.id, raw_data: "tr1") |> ECLRS.create_test_result()

    assert :ok = perform_job(TestResultProducer, %{"file_id" => file.id})
    assert TestResultProducer.last_enqueued_test_result_id() == tr.id
  end

  test "with %{file_id => :all} enqueues a TestResultProcessor for each test result regardless of file" do
    {:ok, file1} = Factory.file_attrs(filename: "file1") |> ECLRS.create_file()
    {:ok, tr1} = Factory.test_result_attrs(county_id: 42, file_id: file1.id, raw_data: "tr1") |> ECLRS.create_test_result()
    {:ok, tr2} = Factory.test_result_attrs(county_id: 42, file_id: file1.id, raw_data: "tr2") |> ECLRS.create_test_result()
    {:ok, file2} = Factory.file_attrs(filename: "file2") |> ECLRS.create_file()
    {:ok, tr3} = Factory.test_result_attrs(county_id: 42, file_id: file2.id, raw_data: "tr3") |> ECLRS.create_test_result()

    assert :ok = perform_job(TestResultProducer, %{"file_id" => :all})
    assert_enqueued(worker: TestResultProcessor, args: %{"test_result_id" => tr1.id})
    assert_enqueued(worker: TestResultProcessor, args: %{"test_result_id" => tr2.id})
    assert_enqueued(worker: TestResultProcessor, args: %{"test_result_id" => tr3.id})
  end

  test "orders them by eclrs_create_date" do
    {:ok, file} = Factory.file_attrs(filename: "file1") |> ECLRS.create_file()

    {:ok, second} =
      Factory.test_result_attrs(county_id: 42, file_id: file.id, raw_data: "second", eclrs_create_date: ~U[2021-01-02 12:00:00Z])
      |> ECLRS.create_test_result()

    {:ok, third} =
      Factory.test_result_attrs(county_id: 42, file_id: file.id, raw_data: "third", eclrs_create_date: ~U[2021-01-03 12:00:00Z])
      |> ECLRS.create_test_result()

    {:ok, first} =
      Factory.test_result_attrs(county_id: 42, file_id: file.id, raw_data: "first", eclrs_create_date: ~U[2021-01-01 12:00:00Z])
      |> ECLRS.create_test_result()

    first_id = first.id
    second_id = second.id
    third_id = third.id

    assert :ok = perform_job(TestResultProducer, %{"file_id" => file.id})
    # all_enqueued sorts by id desc
    assert [
             %Oban.Job{args: %{"test_result_id" => ^first_id}},
             %Oban.Job{args: %{"test_result_id" => ^second_id}},
             %Oban.Job{args: %{"test_result_id" => ^third_id}}
           ] = all_enqueued(worker: TestResultProcessor) |> Enum.reverse()
  end

  test "excludes test results that have already been processed" do
    {:ok, file} = Factory.file_attrs(filename: "file1") |> ECLRS.create_file()
    {:ok, processed} = Factory.test_result_attrs(county_id: 42, file_id: file.id, raw_data: "tr1") |> ECLRS.create_test_result()
    {:ok, failed} = Factory.test_result_attrs(county_id: 42, file_id: file.id, raw_data: "tr2") |> ECLRS.create_test_result()
    {:ok, unprocessed} = Factory.test_result_attrs(county_id: 42, file_id: file.id, raw_data: "tr3") |> ECLRS.create_test_result()

    ECLRS.save_event(processed, "processed")
    ECLRS.save_event(failed, "processing_failed")
    ECLRS.save_event(unprocessed, "some_other_event")

    assert :ok = perform_job(TestResultProducer, %{"file_id" => file.id})
    refute_enqueued(worker: TestResultProcessor, args: %{"test_result_id" => processed.id})
    refute_enqueued(worker: TestResultProcessor, args: %{"test_result_id" => failed.id})
    assert_enqueued(worker: TestResultProcessor, args: %{"test_result_id" => unprocessed.id})
  end
end
