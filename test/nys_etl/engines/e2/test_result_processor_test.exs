defmodule NYSETL.Engines.E2.TestResultProcessorTest do
  use NYSETL.DataCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  import NYSETL.Test.TestHelpers

  alias NYSETL.ECLRS
  alias NYSETL.Engines.E2.TestResultProcessor

  setup [:mock_county_list, :start_supervised_oban]

  setup do
    ECLRS.find_or_create_county(1111)
    {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()
    %{eclrs_file: file}
  end

  test "is unique" do
    # TODO: this should use Oban.insert_all, but it doesn't check uniqueness (at least not our current version)
    [1, 2, 1, 2]
    |> Enum.each(&(TestResultProcessor.new(%{"test_result_id" => &1}) |> Oban.insert!()))

    assert [
             %Oban.Job{args: %{"test_result_id" => 2}},
             %Oban.Job{args: %{"test_result_id" => 1}}
           ] = all_enqueued(worker: TestResultProcessor)
  end

  test "creates a processed event, enqueued event, and CommcareCaseLoader for a successful test result", context do
    {:ok, test_result} = test_result_attrs(county_id: 1111, file_id: context.eclrs_file.id, tid: "no-events") |> ECLRS.create_test_result()
    assert :ok = perform_job(TestResultProcessor, %{"test_result_id" => test_result.id})

    test_result
    |> assert_events(["person_created", "index_case_created", "lab_result_created", "processed"])
  end

  def test_result_attrs(overrides \\ []) do
    [
      aoe_date: ~U[2020-06-01 12:00:00Z],
      eclrs_congregate_care_resident: "A",
      eclrs_create_date: ~U[2020-05-31 12:00:00Z],
      eclrs_hospitalized: "B",
      eclrs_icu: "C",
      eclrs_pregnant: "D",
      eclrs_symptom_onset_date: ~U[2020-06-02 12:00:00Z],
      eclrs_symptomatic: "E",
      employee_job_title: "Employee Job Title",
      employee_number: "Employee Number",
      employer_address: "Employer Address",
      employer_name: "Employer Name",
      employer_phone_alt: "Employer Phone Alt",
      employer_phone: "Employer Phone",
      first_test: "F",
      healthcare_employee: "G",
      lab_id: "H123",
      lab_name: "Some Lab",
      message_master_key: "15200070260000",
      patient_address_1: "123 Somewhere St",
      patient_address_2: "Suite 555",
      patient_city: "SomeCity",
      patient_dob: ~D[1960-01-01],
      patient_gender: "M",
      patient_key: "5",
      patient_name_first: "Test",
      patient_name_last: "User",
      patient_name_middle: "D",
      patient_phone_home_normalized: "2131234567",
      patient_phone_home: "(213) 123-4567",
      patient_updated_at: ~U[2020-05-31 06:00:00Z],
      patient_zip: "12301",
      request_accession_number: "ABC123",
      request_collection_date: ~U[2020-05-30 03:59:00Z],
      request_facility_address_1: "456 Somewhere Else",
      request_facility_address_2: "Suite 0",
      request_facility_city: "OtherCity",
      request_facility_code: "33D070681111",
      request_facility_name: "My Lab",
      request_phone_facility_normalized: "3121234567",
      request_phone_facility: "312-123-4567",
      request_provider_address_1: "456 Somewhere Else",
      request_provider_city: "OtterCity",
      request_provider_id: "A123",
      request_provider_name_first: "Dr",
      request_provider_name_last: "Doctor",
      request_specimen_source_name: "Nasopharyngeal swab",
      result_analysis_date: ~U[2020-05-30 05:00:00Z],
      result_local_test_code: "CULT",
      result_local_test_desc: "CULTURE",
      result_loinc_code: "41852-5",
      result_loinc_desc: "Microorganism or agent identified in Unspecified specimen",
      result_observation_date: ~U[2020-05-30 04:30:00Z],
      result_observation_text_short: "Yuck",
      result_observation_text: "Yucky!!!",
      result_producer_lab_name: "My Lab (tm)",
      result_snomed_code: "7654",
      result_snomed_desc: "Detected",
      result_status_code: "F",
      result: "POSITIVE",
      school_code: "School Code",
      school_district: "School District",
      school_job_class: "School Job Class",
      school_name: "School Name",
      school_present: "School Present",
      sending_facility_clia: "31D0696246"
    ]
    |> Keyword.merge(overrides)
    |> Factory.test_result_attrs()
  end
end
