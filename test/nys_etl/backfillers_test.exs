defmodule NYSETL.BackfillersTest do
  use NYSETL.DataCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

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

  describe "backfill_abouts_checksums" do
    setup do
      {:ok, county} = ECLRS.find_or_create_county(71)
      {:ok, file} = Factory.file_attrs(eclrs_version: 1) |> ECLRS.create_file()

      raw_data =
        "LASTNAME||FIRSTNAME|01MAR1947:00:00:00.000000|M|123 MAIN St||||1111|(555) 123-4567|3130|31D0652945|ACME LABORATORIES INC|15200000000000|321 Main Street||New Rochelle||NEW YORK STATE||321 Main Street|New Rochelle||Sally|Testuser|18MAR2020:00:00:00.000000|20MAR2020:06:03:36.589000|TH68-0|COVID-19 Nasopharynx|94309-2|2019-nCoV RNA XXX NAA+probe-Imp|19MAR2020:19:20:00.000000|Positive for 2019-nCoV|Positive for 2019-nCoV|F||10828004|Positive for 2019-nCoV|102695116|19MAR2020:19:20:00.000000|NASOPHARYNX|15200070260000|14MAY2020:13:43:16.000000|POSITIVE"

      {:ok, test_result} = Factory.test_result_attrs(raw_data: raw_data, county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()

      about_attrs = %{
        checksum: "YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8=",
        county_id: 71,
        first_seen_file_id: file.id,
        last_seen_at: DateTime.utc_now(),
        last_seen_file_id: file.id,
        patient_key_id: "54321",
        test_result_id: test_result.id
      }

      [about_attrs: about_attrs]
    end

    test "creates a job for abouts without checksums", context do
      {:ok, about} = context.about_attrs |> ECLRS.create_about()

      Backfillers.backfill_abouts_checksums()
      %{failure: 0, success: 1} = Oban.drain_queue(queue: :backfillers)

      assert_enqueued(worker: Backfillers.AboutsChecksums, args: %{"action" => "calculate_about_checksums", "about_id" => about.id})
    end

    test "does not create a job for abouts with checksums", context do
      {:ok, _about} =
        context.about_attrs
        |> Map.put(:checksums, %{v1: "foo123", v2: "bar456", v3: "baz789"})
        |> ECLRS.create_about()

      Backfillers.backfill_abouts_checksums()
      %{failure: 0, success: 1} = Oban.drain_queue(queue: :backfillers)

      assert [] = all_enqueued(worker: Backfillers.AboutsChecksums)
    end

    test "queues the next backfiller if it processed any abouts", context do
      {:ok, about} = context.about_attrs |> ECLRS.create_about()

      assert :ok = perform_job(Backfillers.AboutsChecksums, %{"action" => "backfill", "batch_size" => 1, "last_processed_id" => 0})

      assert_enqueued(worker: Backfillers.AboutsChecksums, args: %{"action" => "backfill", "batch_size" => 1, "last_processed_id" => about.id})
    end

    test "does not queue the next backfiller when there are no more abouts", context do
      {:ok, about} = context.about_attrs |> ECLRS.create_about()

      assert :ok = perform_job(Backfillers.AboutsChecksums, %{"action" => "backfill", "batch_size" => 1, "last_processed_id" => about.id})

      assert [] = all_enqueued(worker: Backfillers.AboutsChecksums)
    end

    test "sets the about's checksums", context do
      {:ok, about} = context.about_attrs |> ECLRS.create_about()

      assert {:ok, _about} = perform_job(Backfillers.AboutsChecksums, %{"action" => "calculate_about_checksums", "about_id" => about.id})

      {:ok, about} = ECLRS.get_about(id: about.id)

      about.checksums
      |> assert_eq(
        %{
          v1: "YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8=",
          v2: "c4AeQ4s/s7By9VwwvztlzAiqaXk5IVt8G+4H2URT32U=",
          v3: "RTUA3m3vajNkf9VHtXDIEkK/WZRmH5y1qizhGDx2l/4="
        },
        only: :right_keys
      )
    end

    test "prefixes checksums with 'duplicate' if they match a known about's checksums", context do
      {:ok, about} =
        context.about_attrs
        |> Map.put(:checksum, "foobar")
        |> ECLRS.create_about()

      {:ok, _about} =
        context.about_attrs
        |> Map.merge(%{checksum: "YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8=", patient_key_id: 12345})
        |> Map.put(:checksums, %{v1: "YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8=", v3: "RTUA3m3vajNkf9VHtXDIEkK/WZRmH5y1qizhGDx2l/4="})
        |> ECLRS.create_about()

      assert {:ok, _about} = perform_job(Backfillers.AboutsChecksums, %{"action" => "calculate_about_checksums", "about_id" => about.id})

      {:ok, about} = ECLRS.get_about(id: about.id)

      about.checksums
      |> assert_eq(
        %{
          v1: "duplicate-YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8=",
          v2: "c4AeQ4s/s7By9VwwvztlzAiqaXk5IVt8G+4H2URT32U=",
          v3: "duplicate-RTUA3m3vajNkf9VHtXDIEkK/WZRmH5y1qizhGDx2l/4="
        },
        only: :right_keys
      )
    end

    test "fails if the v1 checksum doesn't match the current checksum (or any known about checksum)", context do
      {:ok, about} =
        context.about_attrs
        |> Map.put(:checksum, "foobar")
        |> ECLRS.create_about()

      assert {:error, reason} = perform_job(Backfillers.AboutsChecksums, %{"action" => "calculate_about_checksums", "about_id" => about.id})
      assert String.match?(reason, ~r/Checksums don't match./)

      {:ok, about} = ECLRS.get_about(id: about.id)
      refute about.checksums
    end
  end
end
