defmodule NYSETL.Engines.E1.ECLRSFileExtractorTest do
  use NYSETL.DataCase, async: false

  alias NYSETL.ECLRS
  alias NYSETL.Engines.E1
  alias NYSETL.Engines.E1.ECLRSFileExtractor

  setup do
    E1.Cache.clear()

    on_exit(fn ->
      E1.Cache.clear()
    end)
  end

  describe "extract!" do
    test "reads a v1 file, creates a File record and Abouts for each row" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/new_records.txt")

      {:ok, _county} = ECLRS.get_county(1111)
      {:ok, _county} = ECLRS.get_county(9999)
      {:ok, file} = ECLRS.get_file(filename: "test/fixtures/eclrs/new_records.txt")

      assert file.eclrs_version == 1

      file.processing_started_at |> assert_recent()
      file.processing_completed_at |> assert_recent()

      file.statistics
      |> assert_eq(%{
        "duplicate" => %{"total" => 0},
        "error" => %{"total" => 0},
        "matched" => %{"total" => 0},
        "new" => %{"total" => 2, "1111" => 1, "9999" => 1}
      })

      ECLRS.County |> Repo.count() |> assert_eq(2)
      ECLRS.TestResult |> Repo.count() |> assert_eq(2)
      ECLRS.About |> Repo.count() |> assert_eq(2)

      ECLRS.About
      |> Repo.get_by(checksum: "YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8=")
      |> assert_eq(
        %{
          county_id: 1111,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_000
        },
        only: :right_keys
      )

      ECLRS.About
      |> Repo.get_by(checksum: "2xyXS0QBcixEPmPI2IcHZUyr2OIuSLGhHTdzA0noM/I=")
      |> assert_eq(
        %{
          county_id: 9999,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_001
        },
        only: :right_keys
      )

      ECLRS.TestResult
      |> Repo.get_by(patient_name_last: "LASTNAME")
      |> assert_eq(
        %{
          patient_name_first: "FIRSTNAME",
          patient_phone_home: "(555) 123-4567",
          patient_phone_home_normalized: "5551234567"
        },
        only: :right_keys
      )
    end

    test "reads a v2 file, creates a File record and Abouts for each row" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v2_new_records.txt")

      {:ok, _county} = ECLRS.get_county(1111)
      {:ok, _county} = ECLRS.get_county(9999)
      {:ok, file} = ECLRS.get_file(filename: "test/fixtures/eclrs/v2_new_records.txt")

      assert file.eclrs_version == 2

      file.processing_started_at |> assert_recent()
      file.processing_completed_at |> assert_recent()

      file.statistics
      |> assert_eq(%{
        "duplicate" => %{"total" => 0},
        "error" => %{"total" => 0},
        "matched" => %{"total" => 0},
        "new" => %{"total" => 2, "1111" => 1, "9999" => 1}
      })

      ECLRS.County |> Repo.count() |> assert_eq(2)
      ECLRS.TestResult |> Repo.count() |> assert_eq(2)
      ECLRS.About |> Repo.count() |> assert_eq(2)

      ECLRS.About
      # Same checksum as for v1 which doesn't have the employer columns
      |> Repo.get_by(checksum: "YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8=")
      |> assert_eq(
        %{
          county_id: 1111,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_000
        },
        only: :right_keys
      )

      ECLRS.About
      |> Repo.get_by(checksum: "2xyXS0QBcixEPmPI2IcHZUyr2OIuSLGhHTdzA0noM/I=")
      |> assert_eq(
        %{
          county_id: 9999,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_001
        },
        only: :right_keys
      )

      ECLRS.TestResult
      |> Repo.get_by(patient_name_last: "LASTNAME")
      |> assert_eq(
        %{
          patient_name_first: "FIRSTNAME",
          patient_phone_home: "(555) 123-4567",
          patient_phone_home_normalized: "5551234567"
        },
        only: :right_keys
      )

      ECLRS.TestResult
      |> Repo.get_by(patient_name_last: "SMITH")
      |> assert_eq(
        %{
          employer_name: "Employer Name",
          employer_address: "Employer Address",
          employer_phone_alt: "Employer Phone Alt",
          school_name: "School Name",
          school_present: "School Present",
          patient_name_first: "AGENT"
        },
        only: :right_keys
      )
    end

    test "does not import employer fields for a row that has already been imported without them" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/new_records.txt")
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v2_new_records.txt")

      ECLRS.TestResult |> Repo.count() |> assert_eq(2)
      ECLRS.About |> Repo.count() |> assert_eq(2)

      ECLRS.TestResult
      |> Repo.get_by(patient_name_last: "SMITH")
      |> assert_eq(
        %{
          employer_name: nil,
          employer_address: nil,
          employer_phone_alt: nil,
          patient_name_first: "AGENT"
        },
        only: :right_keys
      )
    end

    test "reads a v1 file, creates a File record and updates last_seen_at for matched Abouts" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/new_records.txt")
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/partial_match_records.txt")

      {:ok, _county} = ECLRS.get_county(1111)
      {:ok, _county} = ECLRS.get_county(9999)
      {:ok, file} = ECLRS.get_file(filename: "test/fixtures/eclrs/partial_match_records.txt")

      file.processing_started_at |> assert_recent()
      file.processing_completed_at |> assert_recent()

      file.statistics
      |> assert_eq(%{
        "duplicate" => %{"total" => 0},
        "error" => %{"total" => 0},
        "matched" => %{"total" => 1, "9999" => 1},
        "new" => %{"total" => 1, "1111" => 1}
      })

      ECLRS.County |> Repo.count() |> assert_eq(2)
      ECLRS.TestResult |> Repo.count() |> assert_eq(3)
      ECLRS.About |> Repo.count() |> assert_eq(3)
    end

    test "detects duplicates in a file" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/duplicate_rows.txt")

      {:ok, _county} = ECLRS.get_county(1111)
      {:ok, _county} = ECLRS.get_county(9999)
      {:ok, file} = ECLRS.get_file(filename: "test/fixtures/eclrs/duplicate_rows.txt")

      file.processing_started_at |> assert_recent()
      file.processing_completed_at |> assert_recent()

      file.statistics
      |> assert_eq(%{
        "duplicate" => %{"total" => 1, "9999" => 1},
        "error" => %{"total" => 0},
        "matched" => %{"total" => 0},
        "new" => %{"total" => 2, "1111" => 1, "9999" => 1}
      })

      ECLRS.County |> Repo.count() |> assert_eq(2)
      ECLRS.TestResult |> Repo.count() |> assert_eq(2)
      ECLRS.About |> Repo.count() |> assert_eq(2)
    end

    test "reads a v2 file with pipes in the data" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v2_records_with_pipes.txt")

      ECLRS.TestResult
      |> Repo.get_by(patient_name_last: "LASTNAME")
      |> assert_eq(
        %{
          patient_name_first: "FIRSTNAME",
          lab_name: "ACME LABORATORIES | INC",
          request_facility_name: "NEW YORK STATE | GREAT LAB"
        },
        only: :right_keys
      )
    end

    test "parses quotes according to CSV" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v2_records_with_quotes.txt")

      ECLRS.TestResult
      |> Repo.get_by(patient_name_last: "LASTNAME")
      |> assert_eq(
        %{
          patient_name_first: "FIRSTNAME",
          patient_address_2: "\"\""
        },
        only: :right_keys
      )
    end

    # This test has issues.
    # * It's possibly in the wrong file (but it's here because it's here that we want to test this functionality, and
    #   we don't know how to test it through the supervision tree).
    test "crashes if the header is bad" do
      {:ok, file} = ECLRS.create_file(%{filename: "test/fixtures/eclrs/bad_header.txt"})
      assert_raise ECLRS.File.HeaderError, fn -> E1.FileReader.init(file) end
    end
  end
end
