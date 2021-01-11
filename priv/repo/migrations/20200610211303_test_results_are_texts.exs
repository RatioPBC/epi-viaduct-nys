defmodule NYSETL.Repo.Migrations.TestResultsAreTexts do
  use Ecto.Migration

  def change do
    alter table(:test_results) do
      modify :lab_id, :text, from: :string
      modify :lab_name, :text, from: :string
      modify :message_master_key, :text, from: :string
      modify :patient_address_1, :text, from: :string
      modify :patient_address_2, :text, from: :string
      modify :patient_city, :text, from: :string
      modify :patient_gender, :text, from: :string
      modify :patient_home_phone, :text, from: :string
      modify :patient_id, :text, from: :string
      modify :patient_name_first, :text, from: :string
      modify :patient_name_last, :text, from: :string
      modify :patient_name_middle, :text, from: :string
      modify :patient_zip, :text, from: :string
      modify :request_accession_number, :text, from: :string
      modify :request_collection_date, :text, from: :string
      modify :request_facility_address_1, :text, from: :string
      modify :request_facility_address_2, :text, from: :string
      modify :request_facility_city, :text, from: :string
      modify :request_facility_code, :text, from: :string
      modify :request_facility_name, :text, from: :string
      modify :request_facility_phone, :text, from: :string
      modify :request_provider_address_1, :text, from: :string
      modify :request_provider_city, :text, from: :string
      modify :request_provider_id, :text, from: :string
      modify :request_provider_name_first, :text, from: :string
      modify :request_provider_name_last, :text, from: :string
      modify :request_specimen_source_name, :text, from: :string
      modify :result, :text, from: :string
      modify :result_local_test_code, :text, from: :string
      modify :result_local_test_desc, :text, from: :string
      modify :result_loinc_code, :text, from: :string
      modify :result_loinc_desc, :text, from: :string
      modify :result_observation_text, :text, from: :string
      modify :result_observation_text_short, :text, from: :string
      modify :result_producer_lab_name, :text, from: :string
      modify :result_snomed_code, :text, from: :string
      modify :result_snomed_desc, :text, from: :string
      modify :result_status_code, :text, from: :string
      modify :sending_facility_clia, :text, from: :string
    end
  end
end
