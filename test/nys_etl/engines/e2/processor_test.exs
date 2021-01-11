defmodule NYSETL.Engines.E2.ProcessorTest do
  use NYSETL.DataCase, async: false

  import ExUnit.CaptureLog
  import NYSETL.Test.TestHelpers
  import Mox
  alias NYSETL.Commcare
  alias NYSETL.ECLRS
  alias NYSETL.Format
  alias NYSETL.Test.Fixtures
  alias NYSETL.Engines.E2

  setup :verify_on_exit!
  setup :mock_county_list

  def event(schema, name) do
    schema
    |> Repo.preload(:events)
    |> Map.get(:events)
    |> Enum.find(fn e -> e.type == name end)
  end

  describe "process" do
    setup do
      {:ok, county} = ECLRS.find_or_create_county(1111)
      {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
      now = DateTime.utc_now()
      [county: county, eclrs_file: file, now: now]
    end

    test "creates Commcare Person records, adds event to test result", context do
      {:ok, donny_test_result} =
        [
          county_id: context.county.id,
          employee_job_title: "Employee Job Title",
          employee_number: "Employee Number",
          employer_address: "Employer Address",
          employer_name: "Employer Name",
          employer_phone: "Employer Phone",
          employer_phone_alt: "Employer Phone Alt",
          file_id: context.eclrs_file.id,
          eclrs_create_date: ~U[2020-05-31 12:00:00Z],
          lab_id: "H123",
          lab_name: "Some Lab",
          message_master_key: "15200070260000",
          patient_address_1: "123 Somewhere St",
          patient_address_2: "Suite 555",
          patient_city: "SomeCity",
          patient_dob: ~D[1960-01-01],
          patient_gender: "M",
          patient_key: "12345",
          patient_name_first: "Test",
          patient_name_last: "User",
          patient_name_middle: "D",
          patient_phone_home: "(123) 123-4567",
          patient_phone_home_normalized: "1231234567",
          patient_updated_at: ~U[2020-05-31 06:00:00Z],
          patient_zip: "12301",
          request_accession_number: "ABC123",
          request_collection_date: ~U[2020-05-30 03:59:00Z],
          request_facility_address_1: "456 Somewhere Else",
          request_facility_address_2: "Suite 0",
          request_facility_city: "OtherCity",
          request_facility_code: "33D070681111",
          request_facility_name: "My Lab",
          request_phone_facility: "312-123-4567",
          request_phone_facility_normalized: "3121234567",
          request_provider_address_1: "456 Somewhere Else",
          request_provider_city: "OtterCity",
          request_provider_id: "A123",
          request_provider_name_first: "Dr",
          request_provider_name_last: "Doctor",
          request_specimen_source_name: "Nasopharyngeal swab",
          result: "POSITIVE",
          result_analysis_date: ~U[2020-05-30 05:00:00Z],
          result_local_test_code: "CULT",
          result_local_test_desc: "CULTURE",
          result_loinc_code: "41852-5",
          result_loinc_desc: "Microorganism or agent identified in Unspecified specimen",
          result_observation_date: ~U[2020-05-30 04:30:00Z],
          result_observation_text: "Yucky!!!",
          result_observation_text_short: "Yuck",
          result_producer_lab_name: "My Lab (tm)",
          result_snomed_code: "7654",
          result_snomed_desc: "Detected",
          result_status_code: "F",
          school_code: "School Code",
          school_district: "School District",
          school_job_class: "School Job Class",
          school_name: "School Name",
          school_present: "School Present",
          sending_facility_clia: "31D0696246"
        ]
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      E2.Processor.process(donny_test_result)

      Commcare.Person |> Repo.count() |> assert_eq(1)
      Commcare.IndexCase |> Repo.count() |> assert_eq(1)
      Commcare.LabResult |> Repo.count() |> assert_eq(1)

      donny = Commcare.get_person(patient_key: "12345") |> assert_ok()
      donny = donny |> Repo.preload(index_cases: [:lab_results])

      [index_case] = donny.index_cases
      assert_events(index_case, ["index_case_created", "lab_result_created"])

      index_case
      |> Map.get(:data)
      |> assert_eq(
        Fixtures.index_case_data(%{
          "address_street" => "123 Somewhere St",
          "contact_phone_number" => "1231234567",
          "dob" => "1960-01-01",
          "doh_mpi_id" => "P#{donny.id}",
          "external_id" => "P#{donny.id}",
          "fips" => to_string(context.county.id),
          "has_phone_number" => "yes",
          "initials" => "TU",
          "name_and_id" => "Test User (P#{donny.id})",
          "phone_home" => "1231234567"
        }),
        except: ~w{case_import_date}
      )
      |> Map.get("case_import_date")
      |> assert_eq(~r|\d{4}\-\d{2}\-\d{2}|)

      [lab_result] = index_case.lab_results

      lab_result
      |> assert_eq(
        %{
          accession_number: "ABC123"
        },
        only: ~w{accession_number}a
      )
      |> Map.get(:data)
      |> assert_eq(%{
        "accession_number" => "ABC123",
        "analysis_date" => "2020-05-30",
        "doh_mpi_id" => "P#{donny.id}",
        "eclrs_create_date" => "2020-05-31",
        "employee_job_title" => "Employee Job Title",
        "employee_number" => "Employee Number",
        "employer_address" => "Employer Address",
        "employer_name" => "Employer Name",
        "employer_phone_2" => "Employer Phone Alt",
        "employer_phone" => "Employer Phone",
        "external_id" => "P#{donny.id}#12345#ABC123",
        "lab_result" => "positive",
        "laboratory" => "Some Lab",
        "name_employer_school" => "School Name, Employer Name",
        "name" => "P#{donny.id} lab_result",
        "ordering_facility_name" => "My Lab",
        "ordering_facility_address" => "456 Somewhere Else\nSuite 0",
        "ordering_facility_city" => "OtherCity",
        "ordering_facility_phone" => "3121234567",
        "ordering_provider_first_name" => "Dr",
        "ordering_provider_last_name" => "Doctor",
        "ordering_provider_name" => "Dr Doctor",
        "ordering_provider_address" => "456 Somewhere Else",
        "ordering_provider_city" => "OtterCity",
        "owner_id" => "a1a1a1a1a1",
        "parent_external_id" => "P#{donny.id}",
        "parent_type" => "patient",
        "school_attended" => "School Present",
        "school_code" => "School Code",
        "school_district" => "School District",
        "school_name" => "School Name",
        "school_visitor_type" => "School Job Class",
        "specimen_collection_date" => "2020-05-29",
        "specimen_source" => "Nasopharyngeal swab",
        "test_type" => "Microorganism or agent identified in Unspecified specimen"
      })

      donny_test_result |> assert_events(["person_created", "index_case_created", "lab_result_created"])
    end

    test "skip records where eclrs_create_date is earlier than configuration data", context do
      assert ~U[2020-03-01 00:00:00Z] = Application.get_env(:nys_etl, :eclrs_ignore_before_timestamp)

      {:ok, early_test_result} =
        [
          county_id: context.county.id,
          file_id: context.eclrs_file.id,
          eclrs_create_date: ~U[2020-02-29 23:00:00Z],
          lab_name: "Some Hospital",
          patient_dob: ~D[1960-01-01],
          patient_key: "12345",
          patient_name_first: "DONNY",
          patient_name_last: "DOE",
          request_accession_number: "ABC123"
        ]
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      log =
        capture_log(fn ->
          E2.Processor.process(early_test_result)
        end)

      assert log =~ "its eclrs_create_date was older than eclrs_ignore_before_timestamp"

      Commcare.Person |> Repo.count() |> assert_eq(0)
      Commcare.IndexCase |> Repo.count() |> assert_eq(0)
      Commcare.LabResult |> Repo.count() |> assert_eq(0)

      early_test_result |> assert_events(["test_result_ignored"])

      early_test_result
      |> event("test_result_ignored")
      |> Map.get(:data)
      |> assert_eq(%{"reason" => "test_result older than 2020-03-01 00:00:00Z"})
    end

    """
    GIVEN multiple index_cases exist for the person and county
    AND some index_cases have, and some do not have, the duplicate_of_case_id property
    THEN new test results are attached to ALL index_cases for the person and county
    """
    |> test context do
      assert ~U[2020-03-01 00:00:00Z] = Application.get_env(:nys_etl, :eclrs_ignore_before_timestamp)

      {:ok, person} = Commcare.create_person(%{patient_keys: ["12345"], data: %{}})
      create_index_case = fn data -> Commcare.create_index_case(%{person_id: person.id, county_id: context.county.id, data: data}) end
      {:ok, index_case_1} = create_index_case.(%{some: "data"})
      {:ok, index_case_2} = create_index_case.(%{other: "data"})
      {:ok, index_case_3} = create_index_case.(%{more: "data", duplicate_of_case_id: "some-case-id"})

      {:ok, early_test_result} =
        [
          county_id: context.county.id,
          file_id: context.eclrs_file.id,
          eclrs_create_date: ~U[2020-03-01 23:00:00Z],
          lab_name: "Some Hospital",
          patient_dob: ~D[1960-01-01],
          patient_key: "12345",
          patient_name_first: "DONNY",
          patient_name_last: "DOE",
          request_accession_number: "ABC123"
        ]
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      E2.Processor.process(early_test_result)

      Commcare.Person |> Repo.count() |> assert_eq(1)
      Commcare.IndexCase |> Repo.count() |> assert_eq(3)
      Commcare.LabResult |> Repo.count() |> assert_eq(3)

      assert_events(early_test_result, ~w(person_matched
        index_case_updated index_case_updated index_case_updated
        lab_result_created lab_result_created lab_result_created))
      assert_events(index_case_1, ~w(index_case_updated lab_result_created))
      assert_events(index_case_2, ~w(index_case_updated lab_result_created))
      assert_events(index_case_3, ~w(index_case_updated lab_result_created))
    end

    """
    GIVEN a county_id for a non-participating county
    THEN we ignore the test result (because it will be handled by another system)
    """
    |> test context do
      {:ok, _not_participating} = ECLRS.find_or_create_county(Fixtures.nonparticipating_county_fips())

      Commcare.County.get(fips: Fixtures.nonparticipating_county_fips())
      |> assert_eq({
        :non_participating,
        %NYSETL.Commcare.County{display: "Wilkes Land", domain: "aq-wilkes-cdcms", fips: "5678", gaz: "wlk-gaz", location_id: "", name: "wilkes"}
      })

      {:ok, oscar_test_result} =
        [
          county_id: Fixtures.nonparticipating_county_fips(),
          file_id: context.eclrs_file.id,
          eclrs_create_date: ~U[2020-06-30 01:00:00Z],
          lab_name: "Some Hospital",
          patient_dob: ~D[1970-02-01],
          patient_gender: "m",
          patient_key: "67890",
          patient_name_first: "Oscar",
          patient_name_last: "Testuser",
          request_accession_number: "DEF456",
          raw_data: "Oscar"
        ]
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      E2.Processor.process(oscar_test_result)

      Commcare.Person |> Repo.count() |> assert_eq(0)
      Commcare.IndexCase |> Repo.count() |> assert_eq(0)
      Commcare.LabResult |> Repo.count() |> assert_eq(0)

      oscar_test_result |> assert_events(["test_result_ignored"])

      oscar_test_result
      |> event("test_result_ignored")
      |> Map.get(:data)
      |> assert_eq(%{"reason" => "test_result is for fips 5678 (a non-participating county)"})
    end

    """
    GIVEN a county_id not in the commcare county list
    THEN index cases and lab results are created for the statewide CommCare instance
    """
    |> test context do
      {:ok, _unknown} = ECLRS.find_or_create_county(987_654_321)
      {:ok, _statewide} = ECLRS.find_or_create_county(1234)

      Commcare.County.get(fips: 987_654_321)
      |> assert_eq({:error, "no county found with FIPS code '987654321'"})

      {:ok, oscar_test_result} =
        [
          county_id: 987_654_321,
          file_id: context.eclrs_file.id,
          eclrs_create_date: ~U[2020-06-30 12:00:00Z],
          lab_name: "Some Hospital",
          patient_dob: ~D[1970-02-01],
          patient_gender: "m",
          patient_key: "67890",
          patient_name_first: "Oscar",
          patient_name_last: "Testuser",
          request_accession_number: "DEF456",
          request_collection_date: ~U[2020-05-30 03:59:00Z],
          raw_data: "ERSCR"
        ]
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      E2.Processor.process(oscar_test_result)

      Commcare.Person |> Repo.count() |> assert_eq(1)
      Commcare.IndexCase |> Repo.count() |> assert_eq(1)
      Commcare.LabResult |> Repo.count() |> assert_eq(1)

      oscar = Commcare.get_person(patient_key: "67890") |> assert_ok()
      oscar = oscar |> Repo.preload(index_cases: [:lab_results])

      [index_case] = oscar.index_cases

      index_case
      |> assert_eq(%{county_id: 1234}, only: ~w{county_id}a)
      |> Map.get(:data)
      |> assert_eq(
        %{
          "address" => "",
          "address_city" => "",
          "address_complete" => "no",
          "address_county" => "statewide",
          "address_state" => "",
          "address_street" => "",
          "address_zip" => "",
          "analysis_date" => "",
          "case_import_date" => nil,
          "contact_phone_number" => "",
          "county_commcare_domain" => "uk-statewide-cdcms",
          "county_display" => "UK Statewide",
          "dob" => "1970-02-01",
          "dob_known" => "yes",
          "doh_mpi_id" => "P#{oscar.id}",
          "eclrs_create_date" => "2020-06-30",
          "external_id" => "P#{oscar.id}",
          "fips" => "1234",
          "first_name" => "Oscar",
          "full_name" => "Oscar Testuser",
          "gaz" => "state-gaz",
          "gender" => "male",
          "gender_other" => "",
          "has_phone_number" => "no",
          "initials" => "OT",
          "last_name" => "Testuser",
          "name" => "Oscar Testuser",
          "name_and_id" => "Oscar Testuser (P#{oscar.id})",
          "new_lab_result_received" => "yes",
          "owner_id" => "statewide-owner-id",
          "patient_type" => "confirmed",
          "phone_home" => ""
        },
        except: ~w{case_import_date}
      )
      |> Map.get("case_import_date")
      |> assert_eq(~r|\d{4}\-\d{2}\-\d{2}|)

      [lab_result] = index_case.lab_results

      lab_result
      |> assert_eq(%{accession_number: "DEF456"}, only: ~w{accession_number}a)
      |> Map.get(:data)
      |> assert_eq(
        %{
          "accession_number" => "DEF456",
          "analysis_date" => ""
        },
        only: ~w{accession_number analysis_date}
      )

      oscar_test_result |> assert_events(["person_created", "index_case_created", "lab_result_created"])
    end

    test "creates new Person records when test result does not match existing people", context do
      {:ok, donny_test_result} =
        [
          county_id: context.county.id,
          file_id: context.eclrs_file.id,
          eclrs_create_date: context.now,
          lab_name: "Some Hospital",
          patient_dob: ~D[1960-01-01],
          patient_key: "12345",
          patient_name_first: "DONNY",
          patient_name_last: "DOE",
          request_accession_number: "ABC123"
        ]
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      E2.Processor.process(donny_test_result)

      {:ok, oscar_test_result} =
        [
          county_id: context.county.id,
          file_id: context.eclrs_file.id,
          eclrs_create_date: ~U[2020-06-30 12:00:00Z],
          lab_name: "Some Hospital",
          patient_dob: ~D[1970-02-01],
          patient_gender: "f",
          patient_key: "67890",
          patient_name_first: "Oscar",
          patient_name_last: "Testuser",
          request_accession_number: "DEF456",
          raw_data: "Oscar",
          request_collection_date: ~U[2020-05-30 03:59:00Z]
        ]
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      E2.Processor.process(oscar_test_result)

      Commcare.Person |> Repo.count() |> assert_eq(2)
      Commcare.IndexCase |> Repo.count() |> assert_eq(2)
      Commcare.LabResult |> Repo.count() |> assert_eq(2)

      oscar = Commcare.get_person(patient_key: "67890") |> assert_ok()
      oscar = oscar |> Repo.preload(index_cases: [:lab_results])

      [index_case] = oscar.index_cases

      index_case
      |> Map.get(:data)
      |> assert_eq(
        %{
          "address" => "",
          "address_city" => "",
          "address_complete" => "no",
          "address_county" => "midsomer",
          "address_state" => "",
          "address_street" => "",
          "address_zip" => "",
          "analysis_date" => "",
          "case_import_date" => nil,
          "contact_phone_number" => "",
          "county_commcare_domain" => "uk-midsomer-cdcms",
          "county_display" => "Midsomer",
          "dob" => "1970-02-01",
          "dob_known" => "yes",
          "doh_mpi_id" => "P#{oscar.id}",
          "eclrs_create_date" => "2020-06-30",
          "external_id" => "P#{oscar.id}",
          "fips" => to_string(context.county.id),
          "first_name" => "Oscar",
          "full_name" => "Oscar Testuser",
          "gaz" => "ms-gaz",
          "gender" => "female",
          "gender_other" => "",
          "has_phone_number" => "no",
          "initials" => "OT",
          "last_name" => "Testuser",
          "name" => "Oscar Testuser",
          "name_and_id" => "Oscar Testuser (P#{oscar.id})",
          "new_lab_result_received" => "yes",
          "owner_id" => "a1a1a1a1a1",
          "patient_type" => "confirmed",
          "phone_home" => ""
        },
        except: ~w{case_import_date}
      )
      |> Map.get("case_import_date")
      |> assert_eq(~r|\d{4}\-\d{2}\-\d{2}|)

      [lab_result] = index_case.lab_results

      lab_result
      |> assert_eq(
        %{
          accession_number: "DEF456"
        },
        only: ~w{accession_number}a
      )
      |> Map.get(:data)
      |> assert_eq(
        %{
          "accession_number" => "DEF456",
          "analysis_date" => ""
        },
        only: ~w{accession_number analysis_date}
      )

      oscar_test_result |> assert_events(["person_created", "index_case_created", "lab_result_created"])
    end

    test "adds patient_key to existing Person when first name, last name, and dob match", context do
      {:ok, donny_test_result} =
        [
          county_id: context.county.id,
          file_id: context.eclrs_file.id,
          eclrs_create_date: context.now,
          lab_name: "Some Hospital",
          patient_dob: ~D[1960-01-01],
          patient_gender: "m",
          patient_key: "12345",
          patient_name_first: "DONNY",
          patient_name_last: "DOE",
          request_accession_number: "ABC123",
          raw_data: "checksum1"
        ]
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      E2.Processor.process(donny_test_result)

      {:ok, donny_test_result_2} =
        [
          county_id: context.county.id,
          file_id: context.eclrs_file.id,
          eclrs_create_date: context.now,
          lab_name: "Other Hospital",
          patient_dob: ~D[1960-01-01],
          patient_gender: "f",
          patient_key: "67890",
          patient_name_first: "Donny",
          patient_name_last: "Doe",
          request_accession_number: "DEF456",
          raw_data: "checksum2"
        ]
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      E2.Processor.process(donny_test_result_2)

      Commcare.Person |> Repo.count() |> assert_eq(1)
      Commcare.IndexCase |> Repo.count() |> assert_eq(1)
      Commcare.LabResult |> Repo.count() |> assert_eq(2)

      donny = Commcare.get_person(patient_key: "67890") |> assert_ok()
      donny.patient_keys |> assert_eq(["12345", "67890"], ignore_order: true)
    end

    test "lab results for the same patient_key and county are grouped into one index case", context do
      attrs = [
        county_id: context.county.id,
        file_id: context.eclrs_file.id,
        eclrs_create_date: context.now,
        lab_name: "Some Hospital",
        patient_dob: ~D[1960-01-01],
        patient_key: "12345",
        patient_name_first: "DONNY",
        patient_name_last: "DOE",
        request_accession_number: "ABC123",
        raw_data: "some raw data"
      ]

      {:ok, test_result_1} =
        attrs
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      {:ok, test_result_2} =
        attrs
        |> Keyword.merge(request_accession_number: "BCD321", raw_data: "new data")
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      E2.Processor.process(test_result_1)
      E2.Processor.process(test_result_2)

      Commcare.Person |> Repo.count() |> assert_eq(1)
      Commcare.IndexCase |> Repo.count() |> assert_eq(1)
      Commcare.LabResult |> Repo.count() |> assert_eq(2)

      test_result_1 |> assert_events(["person_created", "index_case_created", "lab_result_created"])
      test_result_2 |> assert_events(["person_matched", "index_case_untouched", "lab_result_created"])
    end

    """
    GIVEN a ECLRS test result matches a pre-existing lab result
    THEN changes to existing properties are ignored
    AND new properties are added
    AND non-empty properties write over empty values
    AND changes are logged
    """
    |> test context do
      {:ok, person} = Commcare.create_person(%{patient_keys: ["12345"], data: %{}})
      {:ok, index_case} = Commcare.create_index_case(%{data: %{}, person_id: person.id, county_id: context.county.id})

      {:ok, lr} =
        Commcare.create_lab_result(%{
          data: %{
            doh_mpi_id: "123456",
            eclrs_create_date: context.now |> Date.to_iso8601(),
            external_id: "123456",
            laboratory: "My house",
            opinion: "none",
            patient_key: "12345",
            accession_number: "ABC123"
          },
          index_case_id: index_case.id,
          accession_number: "ABC123"
        })

      test_result_attrs = [
        county_id: context.county.id,
        file_id: context.eclrs_file.id,
        eclrs_create_date: context.now,
        lab_name: "Some Hospital",
        patient_dob: ~D[1960-01-01],
        patient_key: "12345",
        patient_name_first: "DONNY",
        patient_name_last: "DOE",
        request_accession_number: "ABC123",
        raw_data: "some raw data"
      ]

      {:ok, test_result} =
        test_result_attrs
        |> Keyword.merge(raw_data: "new data")
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      assert_that(E2.Processor.process(test_result),
        changes: Repo.count(NYSETL.ChangeLog),
        from: 0,
        to: 2
      )

      Commcare.Person |> Repo.count() |> assert_eq(1)
      Commcare.IndexCase |> Repo.count() |> assert_eq(1)
      Commcare.LabResult |> Repo.count() |> assert_eq(1)

      %Commcare.LabResult{data: data, index_case: index_case} = lab_result = Commcare.LabResult |> Repo.get(lr.id) |> Repo.preload(:index_case)

      %PaperTrail.Version{meta: meta} = PaperTrail.get_version(lab_result)

      meta
      |> assert_eq(
        %{
          "source_type" => "test_result",
          "source_id" => test_result.id,
          "dropped_changes" => %{
            "doh_mpi_id" => index_case.data["external_id"],
            "external_id" => "#{index_case.data["external_id"]}#12345#ABC123",
            "laboratory" => "Some Hospital"
          }
        },
        only: ~w{source_type source_id dropped_changes}s
      )

      changelog =
        NYSETL.ChangeLog
        |> Repo.get_by(destination_type: "lab_result", destination_id: lab_result.id)
        |> assert_eq(
          %{
            source_type: "test_result",
            source_id: test_result.id,
            destination_type: "lab_result",
            destination_id: lab_result.id
          },
          only: ~w{source_type source_id destination_type destination_id}a
        )

      changelog.applied_changes
      |> assert_eq(%{
        "analysis_date" => "",
        "employee_job_title" => nil,
        "employee_number" => nil,
        "employer_address" => nil,
        "employer_name" => nil,
        "employer_phone_2" => nil,
        "employer_phone" => nil,
        "lab_result" => "other",
        "name_employer_school" => nil,
        "name" => "P#{person.id} lab_result",
        "ordering_facility_address" => nil,
        "ordering_facility_city" => nil,
        "ordering_facility_name" => nil,
        "ordering_facility_phone" => nil,
        "ordering_provider_address" => nil,
        "ordering_provider_city" => nil,
        "ordering_provider_first_name" => nil,
        "ordering_provider_last_name" => nil,
        "ordering_provider_name" => nil,
        "owner_id" => "a1a1a1a1a1",
        "parent_external_id" => index_case.data["external_id"],
        "parent_type" => "patient",
        "school_attended" => nil,
        "school_code" => nil,
        "school_district" => nil,
        "school_name" => nil,
        "school_visitor_type" => nil,
        "specimen_collection_date" => "",
        "specimen_source" => nil,
        "test_type" => nil
      })

      changelog.dropped_changes
      |> assert_eq(%{
        "doh_mpi_id" => index_case.data["external_id"],
        "external_id" => "#{index_case.data["external_id"]}#12345#ABC123",
        "laboratory" => "Some Hospital"
      })

      assert_eq(data, %{
        "accession_number" => "ABC123",
        "analysis_date" => "",
        "doh_mpi_id" => "123456",
        "eclrs_create_date" => context.now |> Date.to_iso8601(),
        "external_id" => "123456",
        "employee_job_title" => nil,
        "employee_number" => nil,
        "employer_address" => nil,
        "employer_name" => nil,
        "employer_phone_2" => nil,
        "employer_phone" => nil,
        "lab_result" => "other",
        "name_employer_school" => nil,
        "laboratory" => "My house",
        "name" => "#{index_case.data["external_id"]} lab_result",
        "opinion" => "none",
        "ordering_facility_address" => nil,
        "ordering_facility_city" => nil,
        "ordering_facility_name" => nil,
        "ordering_facility_phone" => nil,
        "ordering_provider_address" => nil,
        "ordering_provider_city" => nil,
        "ordering_provider_first_name" => nil,
        "ordering_provider_last_name" => nil,
        "ordering_provider_name" => nil,
        "owner_id" => "a1a1a1a1a1",
        "parent_external_id" => index_case.data["external_id"],
        "parent_type" => "patient",
        "patient_key" => "12345",
        "school_attended" => nil,
        "school_code" => nil,
        "school_district" => nil,
        "school_name" => nil,
        "school_visitor_type" => nil,
        "specimen_collection_date" => "",
        "specimen_source" => nil,
        "test_type" => nil
      })

      assert_events(index_case, ~w(index_case_updated lab_result_updated))
      assert_events(test_result, ~w(person_matched index_case_updated lab_result_updated))
    end

    """
    GIVEN a ECLRS test result matches multiple lab results for the same patient, having the same accession number
    THEN all lab results are updated with the same data
    """
    |> test context do
      {:ok, person} = Commcare.create_person(%{patient_keys: ["12345"], data: %{}})
      {:ok, index_case} = Commcare.create_index_case(%{data: %{}, person_id: person.id, county_id: context.county.id})

      {:ok, lr1} =
        Commcare.create_lab_result(%{
          data: %{
            accession_number: "ABC123"
          },
          index_case_id: index_case.id,
          accession_number: "ABC123"
        })

      {:ok, lr2} =
        Commcare.create_lab_result(%{
          data: %{
            accession_number: "ABC123"
          },
          index_case_id: index_case.id,
          accession_number: "ABC123"
        })

      attrs = [
        county_id: context.county.id,
        file_id: context.eclrs_file.id,
        eclrs_create_date: context.now,
        lab_name: "Some Hospital",
        patient_dob: ~D[1960-01-01],
        patient_key: "12345",
        patient_name_first: "DONNY",
        patient_name_last: "DOE",
        request_accession_number: "ABC123",
        raw_data: "some raw data"
      ]

      {:ok, test_result} =
        attrs
        |> Keyword.merge(raw_data: "new data", eclrs_create_date: DateTime.utc_now())
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      assert_that(E2.Processor.process(test_result),
        changes: Repo.count(NYSETL.ChangeLog),
        from: 0,
        to: 3
      )

      Commcare.Person |> Repo.count() |> assert_eq(1)
      Commcare.IndexCase |> Repo.count() |> assert_eq(1)
      Commcare.LabResult |> Repo.count() |> assert_eq(2)

      lab_result1 = Commcare.LabResult |> Repo.get(lr1.id) |> Repo.preload(:index_case)
      lab_result2 = Commcare.LabResult |> Repo.get(lr2.id) |> Repo.preload(:index_case)

      assert_eq(lab_result1.data["laboratory"], "Some Hospital")
      assert_eq(lab_result2.data["laboratory"], "Some Hospital")

      assert_events(index_case, ["index_case_updated", "lab_result_updated", "lab_result_updated"])
      assert_events(test_result, ["person_matched", "index_case_updated", "lab_result_updated", "lab_result_updated"])
    end

    test "lab results for the same patient_key, with different county, creates new index case and lab result", context do
      {:ok, other_county} = ECLRS.find_or_create_county(9999)

      attrs = [
        county_id: context.county.id,
        file_id: context.eclrs_file.id,
        eclrs_create_date: context.now,
        lab_name: "Some Hospital",
        patient_dob: ~D[1960-01-01],
        patient_key: "12345",
        patient_name_first: "DONNY",
        patient_name_last: "DOE",
        request_accession_number: "ABC123",
        raw_data: "some raw data"
      ]

      {:ok, test_result_1} =
        attrs
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      {:ok, test_result_2} =
        attrs
        |> Keyword.merge(county_id: other_county.id, raw_data: "other raw data")
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      E2.Processor.process(test_result_1)
      E2.Processor.process(test_result_2)

      Commcare.Person |> Repo.count() |> assert_eq(1)
      Commcare.IndexCase |> Repo.count() |> assert_eq(2)
      Commcare.LabResult |> Repo.count() |> assert_eq(2)

      test_result_1 |> assert_events(["person_created", "index_case_created", "lab_result_created"])
      test_result_2 |> assert_events(["person_matched", "index_case_created", "lab_result_created"])
    end

    test "merges new data into existing index case", context do
      lab_name = Faker.format("???????")
      dob = Faker.Date.backward(20)
      patient_key = Faker.format("########")
      first_name = Faker.Person.first_name()
      last_name = Faker.Person.last_name()
      name = first_name <> " " <> last_name
      accession_number = Faker.format("###???")
      home_phone_number = Faker.format("1##########")
      raw_data = Faker.Lorem.sentence()
      street_address = Faker.Address.street_address()

      {:ok, person} = Commcare.create_person(%{patient_keys: [patient_key], data: %{}})

      initial_case_data =
        Fixtures.index_case_data(%{
          "aaa" => "AAA",
          "a_nil_value" => nil,
          "dob" => Format.format(dob),
          "fips" => to_string(context.county.id),
          "first_name" => first_name,
          "full_name" => name,
          "last_name" => last_name,
          "name" => name,
          "name_and_id" => "#{name} (600000)"
        })

      {:ok, index_case} = Commcare.create_index_case(%{data: initial_case_data, person_id: person.id, county_id: context.county.id})

      test_result_attrs = [
        county_id: context.county.id,
        file_id: context.eclrs_file.id,
        eclrs_create_date: ~U[2020-05-31 12:00:00Z],
        lab_name: lab_name,
        patient_dob: dob,
        patient_address_1: street_address,
        patient_gender: "f",
        patient_key: patient_key,
        patient_name_first: first_name,
        patient_name_last: last_name,
        patient_phone_home_normalized: home_phone_number,
        request_accession_number: accession_number,
        request_collection_date: ~U[2020-05-30 03:59:00Z],
        raw_data: raw_data
      ]

      {:ok, test_result} =
        test_result_attrs
        |> Keyword.merge(raw_data: "new data")
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      assert_that(E2.Processor.process(test_result),
        changes: Repo.count(NYSETL.ChangeLog),
        from: 0,
        to: 1
      )

      %Commcare.IndexCase{data: data} = index_case = Repo.get!(Commcare.IndexCase, index_case.id)

      assert initial_case_data["case_import_date"] == data["case_import_date"], "Expected not to change case_import_date"
      assert initial_case_data["aaa"] == data["aaa"], "Expected not to remove/update downstream properties that we don't care about"
      assert street_address == data["address_street"], "Expected to update downstream nil values"
      assert home_phone_number == data["contact_phone_number"], "Expected to update downstream empty strings"
      assert "yes" == data["has_phone_number"], "Interpolated values can change from no to yes"
      assert initial_case_data["gender"] == data["gender"], "Expected not to change previously assigned values"

      changelog =
        NYSETL.ChangeLog
        |> Repo.first()
        |> assert_eq(
          %{
            source_type: "test_result",
            source_id: test_result.id,
            destination_type: "index_case",
            destination_id: index_case.id
          },
          only: ~w{source_type source_id destination_type destination_id}a
        )

      changelog.previous_state
      |> assert_eq(
        Fixtures.index_case_data(%{
          "a_nil_value" => nil,
          "aaa" => "AAA",
          "dob" => Format.format(dob),
          "first_name" => first_name,
          "full_name" => name,
          "last_name" => last_name,
          "name" => name,
          "name_and_id" => "#{name} (600000)"
        })
      )

      changelog.applied_changes
      |> assert_eq(%{
        "address_street" => street_address,
        "contact_phone_number" => home_phone_number,
        "has_phone_number" => "yes",
        "initials" => [first_name, last_name] |> Enum.map(&String.first/1) |> Enum.join(),
        "phone_home" => home_phone_number
      })

      today_in_commcare_tz = Format.format(context.now)

      changelog.dropped_changes
      |> assert_eq(%{
        "address" => street_address,
        "address_city" => "",
        "address_complete" => "no",
        "address_state" => "",
        "address_zip" => "",
        "analysis_date" => "",
        "case_import_date" => today_in_commcare_tz,
        "doh_mpi_id" => "P#{person.id}",
        "external_id" => "P#{person.id}",
        "gender" => "female",
        "name_and_id" => "#{name} (P#{person.id})"
      })

      assert_eq(data, Map.merge(changelog.previous_state, changelog.applied_changes))

      %PaperTrail.Version{meta: meta} = PaperTrail.get_version(index_case)

      meta
      |> assert_eq(
        %{
          "source_type" => "test_result",
          "source_id" => test_result.id,
          "dropped_changes" => %{
            "address" => street_address,
            "address_city" => "",
            "address_complete" => "no",
            "address_state" => "",
            "address_zip" => "",
            "analysis_date" => "",
            "case_import_date" => today_in_commcare_tz,
            "doh_mpi_id" => "P#{person.id}",
            "external_id" => "P#{person.id}",
            "gender" => "female",
            "name_and_id" => "#{name} (P#{person.id})"
          }
        },
        only: ~w{source_type source_id dropped_changes}s
      )

      assert_events(index_case, ~w(index_case_updated lab_result_created))
    end

    test "marks test_result as noop when no updates are made", context do
      lab_name = Faker.format("???????")
      dob = Faker.Date.backward(20)
      patient_key = Faker.format("########")
      first_name = Faker.Person.first_name()
      last_name = Faker.Person.last_name()
      name = first_name <> " " <> last_name
      accession_number = Faker.format("###???")
      home_phone_number = Faker.format("1##########")
      raw_data = Faker.Lorem.sentence()
      street_address = Faker.Address.street_address()

      initial_data =
        Fixtures.index_case_data(%{
          "address_street" => street_address,
          "contact_phone_number" => home_phone_number,
          "dob" => Format.format(dob),
          "doh_mpi_id" => "8000",
          "external_id" => "8000",
          "fips" => to_string(context.county.id),
          "first_name" => first_name,
          "full_name" => name,
          "initials" => [first_name, last_name] |> Enum.map(&String.first/1) |> Enum.join(),
          "last_name" => last_name,
          "name" => name,
          "name_and_id" => "#{name} (8000)",
          "has_phone_number" => "yes",
          "phone_home" => home_phone_number
        })

      lab_data = %{
        accession_number: accession_number,
        analysis_date: "",
        doh_mpi_id: "8000",
        eclrs_create_date: "2020-05-31",
        employee_job_title: nil,
        employee_number: nil,
        employer_address: nil,
        employer_name: nil,
        employer_phone: nil,
        employer_phone_2: nil,
        external_id: "8000##{patient_key}##{accession_number}",
        lab_result: "other",
        laboratory: lab_name,
        name: "8000 lab_result",
        name_employer_school: nil,
        ordering_facility_name: nil,
        ordering_facility_address: nil,
        ordering_facility_city: nil,
        ordering_facility_phone: nil,
        ordering_provider_first_name: nil,
        ordering_provider_last_name: nil,
        ordering_provider_name: nil,
        ordering_provider_address: nil,
        ordering_provider_city: nil,
        owner_id: "a1a1a1a1a1",
        parent_external_id: "8000",
        parent_type: "patient",
        school_attended: nil,
        school_code: nil,
        school_district: nil,
        school_name: nil,
        school_visitor_type: nil,
        specimen_collection_date: "2020-05-29",
        specimen_source: nil,
        test_type: nil
      }

      {:ok, person} = Commcare.create_person(%{patient_keys: [patient_key], data: %{}})
      {:ok, index_case} = Commcare.create_index_case(%{data: initial_data, person_id: person.id, county_id: context.county.id})
      {:ok, _lab_result} = Commcare.create_lab_result(%{data: lab_data, index_case_id: index_case.id, accession_number: accession_number})

      index_case |> Commcare.save_event("retrieved_from_commcare")

      test_result_attrs = [
        county_id: context.county.id,
        file_id: context.eclrs_file.id,
        eclrs_create_date: ~U[2020-05-31 12:00:00Z],
        lab_name: lab_name,
        patient_dob: dob,
        patient_address_1: street_address,
        patient_gender: "f",
        patient_key: patient_key,
        patient_name_first: first_name,
        patient_name_last: last_name,
        patient_phone_home_normalized: home_phone_number,
        request_accession_number: accession_number,
        request_collection_date: ~U[2020-05-30 03:59:00Z],
        raw_data: raw_data
      ]

      {:ok, test_result} =
        test_result_attrs
        |> Keyword.merge(raw_data: "new data")
        |> Factory.test_result_attrs()
        |> ECLRS.create_test_result()

      assert_that(E2.Processor.process(test_result),
        changes: Repo.count(NYSETL.ChangeLog),
        from: 0,
        to: 2
      )

      changelog =
        NYSETL.ChangeLog
        |> Repo.first()
        |> assert_eq(
          %{
            source_type: "test_result",
            source_id: test_result.id,
            destination_type: "index_case",
            destination_id: index_case.id
          },
          only: ~w{source_type source_id destination_type destination_id}a
        )

      changelog.previous_state
      |> assert_eq(
        Fixtures.index_case_data(%{
          "address_street" => street_address,
          "contact_phone_number" => home_phone_number,
          "dob" => Format.format(dob),
          "doh_mpi_id" => "8000",
          "external_id" => "8000",
          "first_name" => first_name,
          "full_name" => name,
          "has_phone_number" => "yes",
          "initials" => [first_name, last_name] |> Enum.map(&String.first/1) |> Enum.join(),
          "last_name" => last_name,
          "name" => name,
          "name_and_id" => "#{name} (8000)",
          "phone_home" => home_phone_number
        })
      )

      changelog.applied_changes
      |> assert_eq(%{})

      today_in_commcare_tz = Format.format(context.now)

      changelog.dropped_changes
      |> assert_eq(%{
        "address" => street_address,
        "address_city" => "",
        "address_complete" => "no",
        "address_state" => "",
        "address_zip" => "",
        "analysis_date" => "",
        "case_import_date" => today_in_commcare_tz,
        "doh_mpi_id" => "P#{person.id}",
        "external_id" => "P#{person.id}",
        "gender" => "female",
        "name_and_id" => "#{name} (P#{person.id})"
      })

      index_case.data
      |> assert_eq(changelog.previous_state)

      assert_events(index_case, ["retrieved_from_commcare", "index_case_untouched", "lab_result_untouched"])
      assert_events(test_result, ["person_matched", "index_case_untouched", "lab_result_untouched", "no_new_information"])
    end
  end

  describe "to_index_case_data" do
    test "sets doh_mpi_id and external_id to P<person_id>" do
      {:ok, county} = NYSETL.Commcare.County.get(fips: 9999)

      person = %Commcare.Person{id: "76543"}

      %ECLRS.TestResult{county_id: 9999}
      |> E2.Processor.to_index_case_data(person, county)
      |> assert_eq(
        %{
          doh_mpi_id: "P76543",
          external_id: "P76543"
        },
        only: ~w{doh_mpi_id external_id}a
      )
    end
  end

  describe "to_index_case_data_address_block" do
    test "looks up state abbreviation" do
      %ECLRS.TestResult{
        patient_zip: "00510"
      }
      |> E2.Processor.to_index_case_data_address_block()
      |> E2.Processor.with_index_case_data_complete_fields()
      |> assert_eq(%{
        address: "NY, 00510",
        address_city: "",
        address_complete: "no",
        address_state: "NY",
        address_street: "",
        address_zip: "00510",
        has_phone_number: "no"
      })

      %ECLRS.TestResult{
        patient_zip: "94612"
      }
      |> E2.Processor.to_index_case_data_address_block()
      |> E2.Processor.with_index_case_data_complete_fields()
      |> assert_eq(%{
        address: "CA, 94612",
        address_city: "",
        address_complete: "no",
        address_state: "CA",
        address_street: "",
        address_zip: "94612",
        has_phone_number: "no"
      })
    end

    test "handles bad zipcodes" do
      %ECLRS.TestResult{
        patient_zip: "00000"
      }
      |> E2.Processor.to_index_case_data_address_block()
      |> E2.Processor.with_index_case_data_complete_fields()
      |> assert_eq(%{
        address: "00000",
        address_city: "",
        address_complete: "no",
        address_state: "",
        address_street: "",
        address_zip: "00000",
        has_phone_number: "no"
      })

      %ECLRS.TestResult{
        patient_zip: "UNKNOWN"
      }
      |> E2.Processor.to_index_case_data_address_block()
      |> E2.Processor.with_index_case_data_complete_fields()
      |> assert_eq(%{
        address: "UNKNOWN",
        address_city: "",
        address_complete: "no",
        address_state: "",
        address_street: "",
        address_zip: "UNKNOWN",
        has_phone_number: "no"
      })
    end
  end

  describe "to_index_case_data_person_block" do
    test "handles non-binary genders" do
      %ECLRS.TestResult{
        patient_gender: "custom"
      }
      |> E2.Processor.to_index_case_data_person_block("P5555555")
      |> assert_eq(
        %{
          gender: "other",
          gender_other: "custom",
          name_and_id: " (P5555555)"
        },
        only: ~w{gender gender_other name_and_id}a
      )
    end
  end

  describe "diff/2" do
    setup do
      [
        a: %{a: 1, b: 2, z: 26},
        b: %{a: 1, b: 3, y: 25},
        c: %{"a" => 1, "b" => 2, "z" => 26},
        d: %{"a" => 1, "b" => 3, "y" => 25}
      ]
    end

    test "returns additions with atom keys", %{a: a, b: b} do
      {additions, _} = E2.Processor.diff(a, b)
      assert_eq(additions, %{"y" => 25})
    end

    test "returns updates with atom keys", %{a: a, b: b} do
      {_, updates} = E2.Processor.diff(a, b)
      assert_eq(updates, %{"b" => 3})
    end

    test "returns additions with string keys", %{c: c, d: d} do
      {additions, _} = E2.Processor.diff(c, d)
      assert_eq(additions, %{"y" => 25})
    end

    test "returns updates with string keys", %{c: c, d: d} do
      {_, updates} = E2.Processor.diff(c, d)
      assert_eq(updates, %{"b" => 3})
    end

    test "returns additions with string and atom keys", %{a: a, d: d} do
      {additions, _} = E2.Processor.diff(a, d)
      assert_eq(additions, %{"y" => 25})
    end

    test "returns updates with string and atom keys", %{b: b, c: c} do
      {_, updates} = E2.Processor.diff(b, c)
      assert_eq(updates, %{"b" => 2})
    end

    test "updates to existing blank strings are treated as additions" do
      a = %{"a" => "", "b" => nil}
      b = %{a: "b", b: "c"}

      {additions, updates} = E2.Processor.diff(a, b)
      assert_eq(additions, %{"a" => "b", "b" => "c"})
      assert_eq(updates, %{})
    end

    test "can prefer values from the right" do
      a = %{"a" => "1", "b" => "2"}
      b = %{a: "b", b: "c"}

      {additions, updates} = E2.Processor.diff(a, b, prefer_right: ["a"])
      assert_eq(additions, %{"a" => "b"})
      assert_eq(updates, %{"b" => "c"})
    end
  end

  describe "lab_result_text" do
    test "is positive when positive appears in the value" do
      E2.Processor.lab_result_text("Maybe it was POsitive???")
      |> assert_eq("positive")
    end

    test "is negative when negative appears in the value" do
      E2.Processor.lab_result_text("I suspect that NEGATIVe vibes have affected this person")
      |> assert_eq("negative")
    end

    test "is inconclusive when inconclusive appears in the value" do
      E2.Processor.lab_result_text("Inconclusive???")
      |> assert_eq("inconclusive")
    end

    test "is invalid when invalid appears in the value" do
      E2.Processor.lab_result_text("yeeee invalideeeeee")
      |> assert_eq("invalid")
    end

    test "is unknown when unknown appears in the value" do
      E2.Processor.lab_result_text("it is unknown how long this person has been sick with the virus")
      |> assert_eq("unknown")
    end

    test "is other when no other identifier matches" do
      E2.Processor.lab_result_text("this person is definitely infected")
      |> assert_eq("other")
    end
  end
end
