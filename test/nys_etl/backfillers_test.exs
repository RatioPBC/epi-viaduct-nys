defmodule NYSETL.BackfillersTest do
  use NYSETL.DataCase, async: false

  alias NYSETL.Backfillers
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E1
  alias NYSETL.Engines.E1.ECLRSFileExtractor
  require Ecto.Query

  setup do
    E1.Cache.clear()

    on_exit(fn ->
      E1.Cache.clear()
    end)

    {:ok, _oban} = start_supervised({Oban, queues: false, repo: NYSETL.Repo})
    :ok
  end

  describe "backfill_files_eclrs_version" do
    test "determines ECLRS v1 without access to the original file" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/new_records.txt")
      {:ok, file} = ECLRS.get_file(filename: "test/fixtures/eclrs/new_records.txt")

      new_filename = "file/no/longer/exists.txt"
      {:ok, _file} = ECLRS.update_file(file, %{filename: new_filename, eclrs_version: nil})
      {:ok, file} = ECLRS.get_file(filename: new_filename)
      refute file.eclrs_version

      :ok = Backfillers.backfill_files_eclrs_version()
      %{failure: 0, success: 1} = Oban.drain_queue(queue: :backfillers)

      {:ok, file} = ECLRS.get_file(filename: new_filename)
      assert 1 == file.eclrs_version
    end

    test "determines ECLRS v2 without access to the original file" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v2_new_records.txt")
      {:ok, file} = ECLRS.get_file(filename: "test/fixtures/eclrs/v2_new_records.txt")

      new_filename = "file/no/longer/exists.txt"
      {:ok, _file} = ECLRS.update_file(file, %{filename: new_filename, eclrs_version: nil})
      {:ok, file} = ECLRS.get_file(filename: new_filename)
      refute file.eclrs_version

      :ok = Backfillers.backfill_files_eclrs_version()
      %{failure: 0, success: 1} = Oban.drain_queue(queue: :backfillers)

      {:ok, file} = ECLRS.get_file(filename: new_filename)
      assert 2 == file.eclrs_version
    end

    test "does not change it if it's already set - doesn't even try to change it" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/new_records.txt")
      {:ok, file} = ECLRS.get_file(filename: "test/fixtures/eclrs/new_records.txt")

      new_filename = "file/no/longer/exists.txt"
      {:ok, _file} = ECLRS.update_file(file, %{filename: new_filename, eclrs_version: 2})
      {:ok, file} = ECLRS.get_file(filename: new_filename)
      assert 2 == file.eclrs_version

      :ok = Backfillers.backfill_files_eclrs_version()
      %{failure: 0, success: 0} = Oban.drain_queue(queue: :backfillers)
    end

    test "succeeds on a file with no test results (which occurs when a file has no *new* test results)" do
      filename = "fake/file/with/no/new/records.txt"
      {:ok, _file} = ECLRS.create_file(%{filename: filename, processing_started_at: DateTime.utc_now()})

      :ok = Backfillers.backfill_files_eclrs_version()
      %{discard: 1, failure: 0, success: 0} = Oban.drain_queue(queue: :backfillers)

      {:ok, file} = ECLRS.get_file(filename: filename)
      refute file.eclrs_version
    end
  end
end
