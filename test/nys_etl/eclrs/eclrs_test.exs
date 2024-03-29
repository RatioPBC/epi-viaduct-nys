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

    test "succeeds when there are v1 checksum duplicates", context do
      assert {:ok, _} =
               context.about_attrs
               |> Map.put(:checksums, %{v1: context.about.checksums.v1, v2: "bar456", v3: "baz789"})
               |> ECLRS.create_about()
    end

    test "succeeds when there are v2 checksum duplicates", context do
      assert {:ok, _} =
               context.about_attrs
               |> Map.put(:checksums, %{v1: "foo123", v2: context.about.checksums.v2, v3: "baz789"})
               |> ECLRS.create_about()
    end

    test "fails when there is a v3 collision", context do
      assert {:error, %{errors: [checksums: {_, constraint: :unique, constraint_name: "abouts_unique_checksum_v3"}]}} =
               context.about_attrs
               |> Map.put(:checksums, %{v1: "foo123", v2: "bar456", v3: context.about.checksums.v3})
               |> ECLRS.create_about()
    end

    test "fails when any checksum is missing", context do
      assert {:error, %{errors: [checksums: {_, [validation: :required]}]}} =
               context.about_attrs
               |> Map.put(:checksums, nil)
               |> ECLRS.create_about()

      assert {:error,
              %{
                changes: %{
                  checksums: %{
                    errors: [
                      v1: {"can't be blank", [validation: :required]},
                      v2: {"can't be blank", [validation: :required]},
                      v3: {"can't be blank", [validation: :required]}
                    ]
                  }
                }
              }} =
               context.about_attrs
               |> Map.put(:checksums, %{v2: nil, v3: "   "})
               |> ECLRS.create_about()
    end

    test "fails when any checksum is missing (bypassing validations and using DB constraints)", context do
      assert_constraint_failure = fn checksums, constraint_name ->
        checksum_changeset = %ECLRS.About.Checksums{} |> Ecto.Changeset.change(checksums)

        about_attrs =
          context.about_attrs
          |> Map.put(:patient_key_id, String.to_integer(context.about_attrs.patient_key_id))
          |> Map.put(:checksums, checksum_changeset)

        assert_raise Ecto.ConstraintError, ~r/#{constraint_name}/, fn ->
          %ECLRS.About{}
          |> Ecto.Changeset.change(about_attrs)
          |> Repo.insert()
        end
      end

      assert_constraint_failure.(%{v2: "foo", v3: "bar"}, :must_have_checksum_v1)
      assert_constraint_failure.(%{v1: "foo", v2: nil, v3: "bar"}, :must_have_checksum_v2)
      assert_constraint_failure.(%{v1: "foo", v2: "bar", v3: "  "}, :must_have_checksum_v3)
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

    test "is {:ok, about} when a record can be found by v3 checksum", context do
      %{
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

    test "does not match v1 or v2 checksums", context do
      {:ok, _about} =
        %{
          checksums: %{v1: "abc123", v2: "abc123", v3: "no_match"},
          county_id: 71,
          first_seen_file_id: context.eclrs_file.id,
          last_seen_at: DateTime.utc_now(),
          last_seen_file_id: context.eclrs_file.id,
          patient_key_id: "12345",
          test_result_id: context.test_result.id
        }
        |> ECLRS.create_about()

      assert {:error, :not_found} = ECLRS.get_about(checksum: "abc123")
    end
  end

  describe "get_about_by_version" do
    setup do
      {:ok, county} = ECLRS.find_or_create_county(71)
      {:ok, v1_file} = Factory.file_attrs(eclrs_version: 1, filename: "v1_record.txt") |> ECLRS.create_file()
      {:ok, v2_file} = Factory.file_attrs(eclrs_version: 2, filename: "v2_record.txt") |> ECLRS.create_file()
      {:ok, v3_file} = Factory.file_attrs(eclrs_version: 3, filename: "v3_record.txt") |> ECLRS.create_file()
      test_result_attrs = Factory.test_result_attrs(county_id: county.id)

      [county: county, test_result_attrs: test_result_attrs, v1_file: v1_file, v2_file: v2_file, v3_file: v3_file]
    end

    test "finds a v1 about from a v1 file", context do
      v1_file = context.v1_file
      {:ok, test_result} = context.test_result_attrs |> Map.merge(%{file_id: v1_file.id}) |> ECLRS.create_test_result()

      {:ok, about} =
        %{
          checksums: %{v1: "v1_checksum", v2: "v2_checksum", v3: "v3_checksum"},
          county_id: context.county.id,
          first_seen_file_id: v1_file.id,
          last_seen_at: DateTime.utc_now(),
          last_seen_file_id: v1_file.id,
          patient_key_id: "123",
          test_result_id: test_result.id
        }
        |> ECLRS.create_about()

      about_id = about.id
      assert {:ok, %ECLRS.About{id: ^about_id}} = ECLRS.get_about_by_version(%{v1: "v1_checksum", v2: "foo", v3: "bar"})
    end

    test "finds a v2 about from a v2 file", context do
      v2_file = context.v2_file
      {:ok, test_result} = context.test_result_attrs |> Map.merge(%{file_id: v2_file.id}) |> ECLRS.create_test_result()

      {:ok, about} =
        %{
          checksums: %{v1: "v1_checksum", v2: "v2_checksum", v3: "v3_checksum"},
          county_id: context.county.id,
          first_seen_file_id: v2_file.id,
          last_seen_at: DateTime.utc_now(),
          last_seen_file_id: v2_file.id,
          patient_key_id: "123",
          test_result_id: test_result.id
        }
        |> ECLRS.create_about()

      about_id = about.id
      assert {:ok, %ECLRS.About{id: ^about_id}} = ECLRS.get_about_by_version(%{v1: "foo", v2: "v2_checksum", v3: "bar"})
    end

    test "finds a v3 about from a v3 file", context do
      v3_file = context.v3_file
      {:ok, test_result} = context.test_result_attrs |> Map.merge(%{file_id: v3_file.id}) |> ECLRS.create_test_result()

      {:ok, about} =
        %{
          checksums: %{v1: "v1_checksum", v2: "v2_checksum", v3: "v3_checksum"},
          county_id: context.county.id,
          first_seen_file_id: v3_file.id,
          last_seen_at: DateTime.utc_now(),
          last_seen_file_id: v3_file.id,
          patient_key_id: "123",
          test_result_id: test_result.id
        }
        |> ECLRS.create_about()

      about_id = about.id
      assert {:ok, %ECLRS.About{id: ^about_id}} = ECLRS.get_about_by_version(%{v1: "foo", v2: "bar", v3: "v3_checksum"})
    end

    test "does not find an about from a different version", context do
      v1_file = context.v1_file
      {:ok, test_result} = context.test_result_attrs |> Map.merge(%{file_id: v1_file.id}) |> ECLRS.create_test_result()

      {:ok, _about} =
        %{
          checksums: %{v1: "v1_checksum", v2: "v2_checksum", v3: "v3_checksum"},
          county_id: context.county.id,
          first_seen_file_id: v1_file.id,
          last_seen_at: DateTime.utc_now(),
          last_seen_file_id: v1_file.id,
          patient_key_id: "123",
          test_result_id: test_result.id
        }
        |> ECLRS.create_about()

      assert {:error, :not_found} = ECLRS.get_about_by_version(%{v1: "foo", v2: "v2_checksum", v3: "v3_checksum"})
    end

    test "works if multiple records exist with the same early version checksums", context do
      v1_file = context.v1_file

      {:ok, test_result1} = context.test_result_attrs |> Map.merge(%{file_id: v1_file.id}) |> ECLRS.create_test_result()

      {:ok, about} =
        %{
          checksums: %{v1: "v1_checksum", v2: "v2_checksum", v3: "v3_checksum"},
          county_id: context.county.id,
          first_seen_file_id: v1_file.id,
          last_seen_at: DateTime.utc_now(),
          last_seen_file_id: v1_file.id,
          patient_key_id: "123",
          test_result_id: test_result1.id
        }
        |> ECLRS.create_about()

      {:ok, test_result2} = context.test_result_attrs |> Map.merge(%{file_id: v1_file.id}) |> ECLRS.create_test_result()

      {:ok, _about} =
        %{
          checksums: %{v1: "v1_checksum", v2: "v2_checksum", v3: "v3_checksum_brand_new"},
          county_id: context.county.id,
          first_seen_file_id: v1_file.id,
          last_seen_at: DateTime.utc_now(),
          last_seen_file_id: v1_file.id,
          patient_key_id: "456",
          test_result_id: test_result2.id
        }
        |> ECLRS.create_about()

      about_id = about.id
      assert {:ok, %NYSETL.ECLRS.About{id: ^about_id}} = ECLRS.get_about_by_version(%{v1: "v1_checksum", v2: "v2_checksum", v3: "bar"})
    end
  end

  test "get_unprocessed_test_results" do
    {:ok, _county} = ECLRS.find_or_create_county(42)
    {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()

    {:ok, processed_tr_1} = Factory.test_result_attrs(county_id: 42, file_id: file.id) |> ECLRS.create_test_result()
    ECLRS.save_event(processed_tr_1, "processed")

    {:ok, processed_tr_2} = Factory.test_result_attrs(county_id: 42, file_id: file.id) |> ECLRS.create_test_result()
    ECLRS.save_event(processed_tr_2, "processed")

    {:ok, failed_tr_1} = Factory.test_result_attrs(county_id: 42, file_id: file.id) |> ECLRS.create_test_result()
    ECLRS.save_event(failed_tr_1, "processing_failed")

    {:ok, failed_tr_2} = Factory.test_result_attrs(county_id: 42, file_id: file.id) |> ECLRS.create_test_result()
    ECLRS.save_event(failed_tr_2, "processing_failed")

    {:ok, unprocessed_tr_1} = Factory.test_result_attrs(county_id: 42, file_id: file.id) |> ECLRS.create_test_result()
    {:ok, unprocessed_tr_2} = Factory.test_result_attrs(county_id: 42, file_id: file.id) |> ECLRS.create_test_result()
    {:ok, unprocessed_tr_3} = Factory.test_result_attrs(county_id: 42, file_id: file.id) |> ECLRS.create_test_result()

    test_results =
      ECLRS.get_unprocessed_test_results()
      |> order_by(:id)
      |> Repo.all()

    assert test_results == [unprocessed_tr_1, unprocessed_tr_2, unprocessed_tr_3]
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
      |> Euclid.Enum.pluck(:type)
      |> assert_eq(["processed"])
    end

    test "saves an event with metadata", context do
      {:ok, test_result_event} = context.test_result |> ECLRS.save_event(type: "ignored", data: %{reason: "ugly"})
      test_result_event.event.type |> assert_eq("ignored")
      test_result_event.event.data |> assert_eq(%{reason: "ugly"})

      context.test_result
      |> Repo.preload(:events)
      |> Map.get(:events)
      |> Euclid.Enum.pluck(:data)
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
        checksums: %{v1: "about1_v1", v2: "about1_v2", v3: "abc123"},
        county_id: 71,
        first_seen_file_id: context.eclrs_file.id,
        last_seen_at: DateTime.utc_now() |> Timex.shift(days: -30),
        last_seen_file_id: context.eclrs_file.id,
        patient_key_id: "12345",
        test_result_id: context.test_result.id
      }

      {:ok, about1} = attrs |> ECLRS.create_about()
      {:ok, about2} = attrs |> Map.put(:checksums, %{v1: "about2_v1", v2: "about2_v2", v3: "def456"}) |> ECLRS.create_about()
      {:ok, _about3} = attrs |> Map.put(:checksums, %{v1: "about3_v1", v2: "about3_v2", v3: "cba890"}) |> ECLRS.create_about()

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
