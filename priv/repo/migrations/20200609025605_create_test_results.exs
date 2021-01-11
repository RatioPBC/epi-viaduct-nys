defmodule NYSETL.Repo.Migrations.CreateTestResults do
  use Ecto.Migration

  def change do
    create table(:test_results) do
      add :raw_data, :text
      add :county_id, references(:counties), null: false
      add :eclrs_create_date, :utc_datetime
      add :file_id, references(:files), null: false
      add :lab_id, :string
      add :lab_name, :string
      add :message_master_key, :string
      add :patient_address_1, :string
      add :patient_address_2, :string
      add :patient_city, :string
      add :patient_dob, :date
      add :patient_gender, :string
      add :patient_home_phone, :string
      add :patient_id, :string
      add :patient_name_first, :string
      add :patient_name_last, :string
      add :patient_name_middle, :string
      add :patient_updated_at, :utc_datetime
      add :patient_zip, :string
      add :request_accession_number, :string
      add :request_collection_date, :string
      add :request_facility_address_1, :string
      add :request_facility_address_2, :string
      add :request_facility_city, :string
      add :request_facility_code, :string
      add :request_facility_name, :string
      add :request_facility_phone, :string
      add :request_provider_address_1, :string
      add :request_provider_city, :string
      add :request_provider_id, :string
      add :request_provider_name_first, :string
      add :request_provider_name_last, :string
      add :request_specimen_source_name, :string
      add :result, :string
      add :result_analysis_date, :utc_datetime
      add :result_local_test_code, :string
      add :result_local_test_desc, :string
      add :result_loinc_code, :string
      add :result_loinc_desc, :string
      add :result_observation_date, :utc_datetime
      add :result_observation_text, :string
      add :result_observation_text_short, :string
      add :result_producer_lab_name, :string
      add :result_snomed_code, :string
      add :result_snomed_desc, :string
      add :result_status_code, :string
      add :sending_facility_clia, :string

      timestamps()
    end
  end
end
