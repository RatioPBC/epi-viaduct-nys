defmodule NYSETL.Engines.E1.ECLRSFileExtractorTest do
  use NYSETL.DataCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  alias NYSETL.ECLRS
  alias NYSETL.Engines.E1
  alias NYSETL.Engines.E1.ECLRSFileExtractor
  alias NYSETL.Engines.E2

  setup :start_supervised_oban

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
        "new" => %{"total" => 3, "1111" => 1, "9999" => 2}
      })

      ECLRS.County |> Repo.count() |> assert_eq(2)
      ECLRS.TestResult |> Repo.count() |> assert_eq(3)
      ECLRS.About |> Repo.count() |> assert_eq(3)

      {:ok, about} = ECLRS.get_about(checksum: "RTUA3m3vajNkf9VHtXDIEkK/WZRmH5y1qizhGDx2l/4=")

      about
      |> assert_eq(
        %{
          county_id: 1111,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_000
        },
        only: :right_keys
      )

      about.checksums
      |> assert_eq(
        %{
          v1: "YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8=",
          v2: "c4AeQ4s/s7By9VwwvztlzAiqaXk5IVt8G+4H2URT32U=",
          v3: "RTUA3m3vajNkf9VHtXDIEkK/WZRmH5y1qizhGDx2l/4="
        },
        only: :right_keys
      )

      {:ok, about} = ECLRS.get_about(checksum: "RdcbYg0gWgHS56YNHxkKDIL1u737MUI2VPNMCXrXcRk=")

      about
      |> assert_eq(
        %{
          county_id: 9999,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_001
        },
        only: :right_keys
      )

      about.checksums
      |> assert_eq(
        %{
          v1: "2xyXS0QBcixEPmPI2IcHZUyr2OIuSLGhHTdzA0noM/I=",
          v2: "DEVIgFpICrIlCFq7yZprPNSqKeuIXM5slqm4VoxT7+U=",
          v3: "RdcbYg0gWgHS56YNHxkKDIL1u737MUI2VPNMCXrXcRk="
        },
        only: :right_keys
      )

      {:ok, about} = ECLRS.get_about(checksum: "Vc0JGTOi9LC5qJ+4bTuq4oW76IDd2wWqNhu+rU+s++A=")

      about
      |> assert_eq(
        %{
          county_id: 9999,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_002
        },
        only: :right_keys
      )

      about.checksums
      |> assert_eq(
        %{
          v1: "k68TeJakzpNDZupxeo0FrjJ3X5DT04ssjUfijnmM5rE=",
          v2: "cVhURpBsRsOm4hVE0c45V8jr7INuCWkqX3GxAR8ldkk=",
          v3: "Vc0JGTOi9LC5qJ+4bTuq4oW76IDd2wWqNhu+rU+s++A="
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
        "new" => %{"total" => 3, "1111" => 1, "9999" => 2}
      })

      ECLRS.County |> Repo.count() |> assert_eq(2)
      ECLRS.TestResult |> Repo.count() |> assert_eq(3)
      ECLRS.About |> Repo.count() |> assert_eq(3)

      # Same checksum as for v1 which doesn't have the employer columns
      {:ok, about} = ECLRS.get_about(checksum: "RTUA3m3vajNkf9VHtXDIEkK/WZRmH5y1qizhGDx2l/4=")

      about
      |> assert_eq(
        %{
          county_id: 1111,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_000
        },
        only: :right_keys
      )

      about.checksums
      |> assert_eq(
        %{
          v1: "YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8=",
          v2: "c4AeQ4s/s7By9VwwvztlzAiqaXk5IVt8G+4H2URT32U=",
          v3: "RTUA3m3vajNkf9VHtXDIEkK/WZRmH5y1qizhGDx2l/4="
        },
        only: :right_keys
      )

      {:ok, about} = ECLRS.get_about(checksum: "VGWpa4/LeQ+wvWzFMAhd1y15msKC/Z83P7wiuU/1pJQ=")

      about
      |> assert_eq(
        %{
          county_id: 9999,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_001
        },
        only: :right_keys
      )

      about.checksums
      |> assert_eq(
        %{
          v1: "2xyXS0QBcixEPmPI2IcHZUyr2OIuSLGhHTdzA0noM/I=",
          v2: "hk52rV6eghiXb3+9L9DC0/h9vR2Wgt5sZJu+Z4D7EVY=",
          v3: "VGWpa4/LeQ+wvWzFMAhd1y15msKC/Z83P7wiuU/1pJQ="
        },
        only: :right_keys
      )

      {:ok, about} = ECLRS.get_about(checksum: "Vc0JGTOi9LC5qJ+4bTuq4oW76IDd2wWqNhu+rU+s++A=")

      about
      |> assert_eq(
        %{
          county_id: 9999,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_002
        },
        only: :right_keys
      )

      about.checksums
      |> assert_eq(
        %{
          v1: "k68TeJakzpNDZupxeo0FrjJ3X5DT04ssjUfijnmM5rE=",
          v2: "cVhURpBsRsOm4hVE0c45V8jr7INuCWkqX3GxAR8ldkk=",
          v3: "Vc0JGTOi9LC5qJ+4bTuq4oW76IDd2wWqNhu+rU+s++A="
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

    test "reads a v3 file, creates a File record and Abouts for each row" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v3_new_records.txt")

      {:ok, _county} = ECLRS.get_county(1111)
      {:ok, _county} = ECLRS.get_county(9999)
      {:ok, file} = ECLRS.get_file(filename: "test/fixtures/eclrs/v3_new_records.txt")

      assert file.eclrs_version == 3

      file.processing_started_at |> assert_recent()
      file.processing_completed_at |> assert_recent()

      file.statistics
      |> assert_eq(%{
        "duplicate" => %{"total" => 0},
        "error" => %{"total" => 0},
        "matched" => %{"total" => 0},
        "new" => %{"total" => 3, "1111" => 1, "9999" => 2}
      })

      ECLRS.County |> Repo.count() |> assert_eq(2)
      ECLRS.TestResult |> Repo.count() |> assert_eq(3)
      ECLRS.About |> Repo.count() |> assert_eq(3)

      # Same checksum as for v1 which doesn't have the employer columns
      {:ok, about} = ECLRS.get_about(checksum: "RTUA3m3vajNkf9VHtXDIEkK/WZRmH5y1qizhGDx2l/4=")

      about
      |> assert_eq(
        %{
          county_id: 1111,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_000
        },
        only: :right_keys
      )

      about.checksums
      |> assert_eq(
        %{
          v1: "YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8=",
          v2: "c4AeQ4s/s7By9VwwvztlzAiqaXk5IVt8G+4H2URT32U=",
          v3: "RTUA3m3vajNkf9VHtXDIEkK/WZRmH5y1qizhGDx2l/4="
        },
        only: :right_keys
      )

      {:ok, about} = ECLRS.get_about(checksum: "VGWpa4/LeQ+wvWzFMAhd1y15msKC/Z83P7wiuU/1pJQ=")

      about
      |> assert_eq(
        %{
          county_id: 9999,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_001
        },
        only: :right_keys
      )

      about.checksums
      |> assert_eq(
        %{
          v1: "2xyXS0QBcixEPmPI2IcHZUyr2OIuSLGhHTdzA0noM/I=",
          v2: "hk52rV6eghiXb3+9L9DC0/h9vR2Wgt5sZJu+Z4D7EVY=",
          v3: "VGWpa4/LeQ+wvWzFMAhd1y15msKC/Z83P7wiuU/1pJQ="
        },
        only: :right_keys
      )

      {:ok, about} = ECLRS.get_about(checksum: "j4t6aZHgMawC1oJJFM9mjGH+QIlGQlWRIOy8CeN826o=")

      about
      |> assert_eq(
        %{
          county_id: 9999,
          first_seen_file_id: file.id,
          patient_key_id: 15_200_000_000_002
        },
        only: :right_keys
      )

      about.checksums
      |> assert_eq(
        %{
          v1: "k68TeJakzpNDZupxeo0FrjJ3X5DT04ssjUfijnmM5rE=",
          v2: "cVhURpBsRsOm4hVE0c45V8jr7INuCWkqX3GxAR8ldkk=",
          v3: "j4t6aZHgMawC1oJJFM9mjGH+QIlGQlWRIOy8CeN826o="
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

      ECLRS.TestResult
      |> Repo.get_by(patient_name_last: "GOODE")
      |> assert_eq(
        %{
          first_test: "A",
          aoe_date: ~U[2020-03-20 05:02:03.000000Z],
          healthcare_employee: "B",
          eclrs_symptomatic: "C",
          eclrs_symptom_onset_date: ~U[2020-03-21 08:05:06.000000Z],
          eclrs_hospitalized: "D",
          eclrs_icu: "E",
          eclrs_congregate_care_resident: "F",
          eclrs_pregnant: "G",
          patient_name_first: "JOHNNY"
        },
        only: :right_keys
      )
    end

    test "does not import employer fields for a row that was imported at a previous version" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/new_records.txt")
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v2_new_records.txt")

      ECLRS.TestResult |> Repo.count() |> assert_eq(3)
      ECLRS.About |> Repo.count() |> assert_eq(3)

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

    test "imports employer fields for a row was previously imported at the same version" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v2_new_records.txt")
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v2_new_records_added_info.txt")

      ECLRS.TestResult |> Repo.count() |> assert_eq(4)
      ECLRS.About |> Repo.count() |> assert_eq(4)

      ECLRS.TestResult
      |> first()
      |> Repo.get_by(patient_name_last: "LASTNAME")
      |> assert_eq(
        %{
          employer_name: nil,
          employer_address: nil,
          employer_phone_alt: nil,
          patient_name_first: "FIRSTNAME"
        },
        only: :right_keys
      )

      ECLRS.TestResult
      |> last()
      |> Repo.get_by(patient_name_last: "LASTNAME")
      |> assert_eq(
        %{
          employer_name: "cool employer",
          patient_name_first: "FIRSTNAME"
        },
        only: :right_keys
      )
    end

    test "does not import AOE fields for a row that was imported at a previous version" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v2_new_records.txt")
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v3_new_records.txt")

      ECLRS.TestResult |> Repo.count() |> assert_eq(3)
      ECLRS.About |> Repo.count() |> assert_eq(3)

      ECLRS.TestResult
      |> Repo.get_by(patient_name_last: "GOODE")
      |> assert_eq(
        %{
          first_test: nil,
          healthcare_employee: nil,
          eclrs_symptomatic: nil,
          patient_name_first: "JOHNNY"
        },
        only: :right_keys
      )
    end

    test "imports AOE fields for a row that was previously imported without them" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v3_new_records.txt")
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/v3_new_records_added_info.txt")

      ECLRS.TestResult |> Repo.count() |> assert_eq(4)
      ECLRS.About |> Repo.count() |> assert_eq(4)

      ECLRS.TestResult
      |> first()
      |> Repo.get_by(patient_name_last: "LASTNAME")
      |> assert_eq(
        %{
          first_test: nil,
          healthcare_employee: nil,
          eclrs_symptomatic: nil,
          patient_name_first: "FIRSTNAME"
        },
        only: :right_keys
      )

      ECLRS.TestResult
      |> last()
      |> Repo.get_by(patient_name_last: "LASTNAME")
      |> assert_eq(
        %{
          first_test: "yes",
          healthcare_employee: "no",
          eclrs_symptomatic: "maybe so",
          patient_name_first: "FIRSTNAME"
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
      ECLRS.TestResult |> Repo.count() |> assert_eq(4)
      ECLRS.About |> Repo.count() |> assert_eq(4)
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

    test "enqueues E2.TestResultProducer" do
      :ok = ECLRSFileExtractor.extract!("test/fixtures/eclrs/new_records.txt")
      {:ok, file} = ECLRS.get_file(filename: "test/fixtures/eclrs/new_records.txt")
      assert_enqueued(worker: E2.TestResultProducer, args: %{"file_id" => file.id})
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
