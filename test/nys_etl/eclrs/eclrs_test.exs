defmodule NYSETL.ECLRSTest do
  use NYSETL.DataCase, async: true

  alias NYSETL.ECLRS

  describe "find_or_create_county" do
    test "creates {:ok, county} when attrs are valid" do
      ECLRS.County |> Repo.count() |> assert_eq(0)
      assert {:ok, _county} = ECLRS.find_or_create_county(55)
      assert {:ok, _created_county} = ECLRS.get_county(55)
      ECLRS.County |> Repo.count() |> assert_eq(1)
    end

    test "is {:ok, county} when county already exists" do
      assert {:ok, _county} = ECLRS.find_or_create_county(55)

      ECLRS.County |> Repo.count() |> assert_eq(1)
      assert {:ok, _county} = ECLRS.find_or_create_county(55)
      ECLRS.County |> Repo.count() |> assert_eq(1)
    end
  end

  describe "create_file" do
    test "is {:ok, file} when attrs are valid" do
      %{filename: "test/file.txt", statistics: %{"something" => "happened"}} |> ECLRS.create_file()
      {:ok, file} = ECLRS.get_file(filename: "test/file.txt")
      file.statistics |> assert_eq(%{"something" => "happened"})
      file.processing_completed_at |> assert_eq(nil)
    end
  end

  describe "create_about" do
    setup do
      {:ok, county} = ECLRS.find_or_create_county(71)
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
      {:ok, test_result} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()
      [county: county, eclrs_file: file, test_result: test_result]
    end

    test "creates an about", context do
      assert {:ok, _} =
               %{
                 checksum: "abc123",
                 county_id: 71,
                 first_seen_file_id: context.eclrs_file.id,
                 last_seen_at: DateTime.utc_now(),
                 last_seen_file_id: context.eclrs_file.id,
                 patient_key_id: "12345",
                 test_result_id: context.test_result.id
               }
               |> ECLRS.create_about()
    end
  end

  describe "fingerprint" do
    alias NYSETL.Crypto

    def build_test_result(attrs) do
      %ECLRS.TestResult{}
      |> Map.merge(attrs)
    end

    test "provides a hash of dob, last name, first name" do
      "1990-01-01SmithAgent"
      |> Crypto.sha256()
      |> assert_eq("xSHtOJKF68AIohydbWMGIYJi+/oK+KuSzNjWLvA8d5w=")

      Factory.test_result_attrs(
        county_id: 600,
        file_id: 12,
        patient_dob: ~D[1990-01-01],
        patient_name_last: "Smith",
        patient_name_first: "Agent"
      )
      |> build_test_result()
      |> ECLRS.fingerprint()
      |> assert_eq("xSHtOJKF68AIohydbWMGIYJi+/oK+KuSzNjWLvA8d5w=")

      "1962-03-11AndersonThomas"
      |> Crypto.sha256()
      |> assert_eq("ExP+cvXPxjwHNlKbQz9CrXNxYqaWtmThUWATtY+TwR4=")

      Factory.test_result_attrs(
        county_id: 600,
        file_id: 12,
        patient_dob: ~D[1962-03-11],
        patient_name_last: "Anderson",
        patient_name_first: "Thomas"
      )
      |> build_test_result()
      |> ECLRS.fingerprint()
      |> assert_eq("ExP+cvXPxjwHNlKbQz9CrXNxYqaWtmThUWATtY+TwR4=")
    end
  end

  describe "finish_processing_file" do
    test "is {:ok, file}" do
      {:ok, file} = %{filename: "test/file.txt"} |> ECLRS.create_file()
      {:ok, file} = file |> ECLRS.finish_processing_file(statistics: %{"with" => "stats"})
      file.statistics |> assert_eq(%{"with" => "stats"})
      file.processing_completed_at |> assert_recent()
    end
  end

  describe "get_county" do
    test "is {:ok, county} when a county exists" do
      %{id: 12} |> ECLRS.County.changeset() |> Repo.insert!()
      {:ok, county} = ECLRS.get_county(12)
      county.id |> assert_eq(12)
    end

    test "is {:error, :not_found} when a county does not exists" do
      ECLRS.get_county(12) |> assert_eq({:error, :not_found})
    end
  end

  describe "get_file" do
    test "is {:ok, file} when a file can be found by filename" do
      %{filename: "test/file.txt", statistics: %{"something" => "happened"}} |> ECLRS.File.changeset() |> Repo.insert!()
      {:ok, file} = ECLRS.get_file(filename: "test/file.txt")
      file.statistics |> assert_eq(%{"something" => "happened"})
    end

    test "is {:error, :not_found} when a file does not exist" do
      assert {:error, :not_found} = ECLRS.get_file(filename: "test/file.txt")
    end
  end

  describe "get_about" do
    setup do
      {:ok, county} = ECLRS.find_or_create_county(71)
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
      {:ok, test_result} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()
      [county: county, eclrs_file: file, test_result: test_result]
    end

    test "is {:ok, about} when a record can be found by checksum", context do
      %{
        checksum: "abc123",
        county_id: 71,
        first_seen_file_id: context.eclrs_file.id,
        last_seen_at: DateTime.utc_now(),
        last_seen_file_id: context.eclrs_file.id,
        patient_key_id: "12345",
        test_result_id: context.test_result.id
      }
      |> ECLRS.create_about()

      {:ok, checksum} = ECLRS.get_about(checksum: "abc123")
      checksum.patient_key_id |> assert_eq(12_345)
    end

    test "is {:error, :not_found} when a file does not exist" do
      assert {:error, :not_found} = ECLRS.get_about(checksum: "abc123")
    end
  end

  describe "save_event" do
    setup do
      {:ok, county} = ECLRS.find_or_create_county(71)
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
      {:ok, test_result} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()
      [county: county, eclrs_file: file, test_result: test_result]
    end

    test "associates an Event with a TestResult", context do
      {:ok, test_result_event} = context.test_result |> ECLRS.save_event("processed")
      test_result_event.event.type |> assert_eq("processed")

      context.test_result
      |> Repo.preload(:events)
      |> Map.get(:events)
      |> Extra.Enum.pluck(:type)
      |> assert_eq(["processed"])
    end

    test "saves an event with metadata", context do
      {:ok, test_result_event} = context.test_result |> ECLRS.save_event(type: "ignored", data: %{reason: "ugly"})
      test_result_event.event.type |> assert_eq("ignored")
      test_result_event.event.data |> assert_eq(%{reason: "ugly"})

      context.test_result
      |> Repo.preload(:events)
      |> Map.get(:events)
      |> Extra.Enum.pluck(:data)
      |> assert_eq([%{"reason" => "ugly"}])
    end
  end

  describe "update_last_seen_file" do
    setup do
      {:ok, county} = ECLRS.find_or_create_county(71)
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
      {:ok, test_result} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()
      [county: county, eclrs_file: file, test_result: test_result]
    end

    test "updates last_seen_file_id and last_seen_file_at on the relevant abouts", context do
      {:ok, newer_file} = Factory.file_attrs(filename: "/tmp/other") |> ECLRS.create_file()

      attrs = %{
        checksum: "abc123",
        county_id: 71,
        first_seen_file_id: context.eclrs_file.id,
        last_seen_at: DateTime.utc_now() |> Timex.shift(days: -30),
        last_seen_file_id: context.eclrs_file.id,
        patient_key_id: "12345",
        test_result_id: context.test_result.id
      }

      {:ok, about1} = attrs |> ECLRS.create_about()
      {:ok, about2} = attrs |> Map.put(:checksum, "def456") |> ECLRS.create_about()
      {:ok, _about3} = attrs |> Map.put(:checksum, "cba890") |> ECLRS.create_about()

      :ok = [about1, about2] |> ECLRS.update_last_seen_file(newer_file)

      about = ECLRS.get_about(checksum: "abc123") |> assert_ok()
      about.last_seen_at |> assert_recent()
      about.last_seen_file_id |> assert_eq(newer_file.id)

      about = ECLRS.get_about(checksum: "def456") |> assert_ok()
      about.last_seen_at |> assert_recent()
      about.last_seen_file_id |> assert_eq(newer_file.id)

      about = ECLRS.get_about(checksum: "cba890") |> assert_ok()
      about.last_seen_file_id |> assert_eq(context.eclrs_file.id)
    end
  end
end
