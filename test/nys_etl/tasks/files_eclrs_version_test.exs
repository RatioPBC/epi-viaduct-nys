defmodule NYSETL.Tasks.FilesEclrsVersionTest do
  use NYSETL.DataCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  require Ecto.Query

  alias NYSETL.Tasks.FilesEclrsVersion
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E1
  alias NYSETL.Engines.E1.ECLRSFileExtractor

  setup :start_supervised_oban

  setup do
    E1.Cache.clear()

    on_exit(fn ->
      E1.Cache.clear()
    end)

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

      :ok = FilesEclrsVersion.backfill_all()
      %{failure: 0, success: 1} = Oban.drain_queue(queue: :tasks)

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

      :ok = FilesEclrsVersion.backfill_all()
      %{failure: 0, success: 1} = Oban.drain_queue(queue: :tasks)

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

      :ok = FilesEclrsVersion.backfill_all()
      %{failure: 0, success: 0} = Oban.drain_queue(queue: :tasks)
    end

    test "succeeds on a file with no test results (which occurs when a file has no *new* test results)" do
      filename = "fake/file/with/no/new/records.txt"
      {:ok, _file} = ECLRS.create_file(%{filename: filename, processing_started_at: DateTime.utc_now()})

      :ok = FilesEclrsVersion.backfill_all()
      %{discard: 1, failure: 0, success: 0} = Oban.drain_queue(queue: :tasks)

      {:ok, file} = ECLRS.get_file(filename: filename)
      refute file.eclrs_version
    end
  end
end
