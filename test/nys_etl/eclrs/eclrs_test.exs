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
                 checksums: %{v1: "abc123", v2: "def456", v3: "ghi789"},
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

  describe "create_about (checksum validation)" do
    setup do
      {:ok, county} = ECLRS.find_or_create_county(71)
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
      {:ok, test_result} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()
      {:ok, test_result_2} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()

      {:ok, about} =
        %{
          checksum: "abc123",
          checksums: %{v1: "abc123", v2: "def456", v3: "ghi789"},
          county_id: 71,
          first_seen_file_id: file.id,
          last_seen_at: DateTime.utc_now(),
          last_seen_file_id: file.id,
          patient_key_id: "12345",
          test_result_id: test_result.id
        }
        |> ECLRS.create_about()

      about_attrs = %{
        checksum: "foo123",
        county_id: 71,
        first_seen_file_id: file.id,
        last_seen_at: DateTime.utc_now(),
        last_seen_file_id: file.id,
        patient_key_id: "54321",
        test_result_id: test_result_2.id
      }

      [about: about, about_attrs: about_attrs]
    end

    test "succeeds when there are no checksum collisions", context do
      assert {:ok, _} =
               context.about_attrs
               |> Map.put(:checksums, %{v1: "foo123", v2: "bar456", v3: "baz789"})
               |> ECLRS.create_about()
    end

    test "fails when there are any checksum collisions", context do
      assert {:error, %{errors: [checksums: {_, constraint: :unique, constraint_name: "abouts_unique_checksum_v1"}]}} =
               context.about_attrs
               |> Map.put(:checksums, %{v1: context.about.checksums.v1, v2: "bar456", v3: "baz789"})
               |> ECLRS.create_about()

      assert {:error, %{errors: [checksums: {_, constraint: :unique, constraint_name: "abouts_unique_checksum_v2"}]}} =
               context.about_attrs
               |> Map.put(:checksums, %{v1: "foo123", v2: context.about.checksums.v2, v3: "baz789"})
               |> ECLRS.create_about()

      assert {:error, %{errors: [checksums: {_, constraint: :unique, constraint_name: "abouts_unique_checksum_v3"}]}} =
               context.about_attrs
               |> Map.put(:checksums, %{v1: "foo123", v2: "bar456", v3: context.about.checksums.v3})
               |> ECLRS.create_about()
    end
  end

  describe "update_about" do
    test "requires checksum changes to be updates" do
      {:ok, county} = ECLRS.find_or_create_county(71)
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
      {:ok, test_result} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()

      {:ok, about} =
        %{
          checksum: "abc123",
          checksums: %{v1: "abc123", v2: "def456", v3: "ghi789"},
          county_id: 71,
          first_seen_file_id: file.id,
          last_seen_at: DateTime.utc_now(),
          last_seen_file_id: file.id,
          patient_key_id: "12345",
          test_result_id: test_result.id
        }
        |> ECLRS.create_about()

      assert_raise RuntimeError, ~r/you are attempting to change relation \:checksums/, fn ->
        ECLRS.update_about(about, %{checksums: %{v1: "foo", v2: "bar", v3: "baz"}})
      end

      new_checksums = about.checksums |> Map.merge(%{v1: "foo", v2: "bar", v3: "baz"}) |> Map.from_struct()
      assert {:ok, _about} = ECLRS.update_about(about, %{checksums: new_checksums})

      Repo.reload(about).checksums
      |> assert_eq(
        %{v1: "foo", v2: "bar", v3: "baz"},
        only: :right_keys
      )
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
        checksums: %{v1: "foo", v2: "bar", v3: "abc123"},
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
        checksums: %{v1: "about1_v1", v2: "about1_v2", v3: "abc123"},
        county_id: 71,
        first_seen_file_id: context.eclrs_file.id,
        last_seen_at: DateTime.utc_now() |> Timex.shift(days: -30),
        last_seen_file_id: context.eclrs_file.id,
        patient_key_id: "12345",
        test_result_id: context.test_result.id
      }

      {:ok, about1} = attrs |> ECLRS.create_about()

      {:ok, about2} =
        attrs |> Map.put(:checksum, "def456") |> Map.put(:checksums, %{v1: "about2_v1", v2: "about2_v2", v3: "def456"}) |> ECLRS.create_about()

      {:ok, _about3} =
        attrs |> Map.put(:checksum, "cba890") |> Map.put(:checksums, %{v1: "about3_v1", v2: "about3_v2", v3: "cba890"}) |> ECLRS.create_about()

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
