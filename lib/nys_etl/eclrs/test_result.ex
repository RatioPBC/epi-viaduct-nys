defmodule NYSETL.ECLRS.TestResult do
  @moduledoc """
  Represents a unique row from an ECLRS file.

  The raw text of the row is persisted as `:raw_data`. A checksum of the raw data is persisted in the associated
  `About` record, as `test_result.about.checksum`.
  """

  use NYSETL, :schema

  alias NYSETL.ECLRS

  schema "test_results" do
    field :eclrs_create_date, :utc_datetime_usec
    field :employee_job_title, :string
    field :employee_number, :string
    field :employer_address, :string
    field :employer_name, :string
    field :employer_phone, :string
    field :employer_phone_alt, :string
    field :lab_id, :string
    field :lab_name, :string
    field :message_master_key, :string
    field :patient_address_1, :string
    field :patient_address_2, :string
    field :patient_city, :string
    field :patient_dob, :date
    field :patient_gender, :string
    field :patient_key, :string
    field :patient_name_first, :string
    field :patient_name_last, :string
    field :patient_name_middle, :string
    field :patient_phone_home, :string
    field :patient_phone_home_normalized, :string
    field :patient_updated_at, :utc_datetime_usec
    field :patient_zip, :string
    field :raw_data, :string
    field :request_accession_number, :string
    field :request_collection_date, :utc_datetime_usec
    field :request_facility_address_1, :string
    field :request_facility_address_2, :string
    field :request_facility_city, :string
    field :request_facility_code, :string
    field :request_facility_name, :string
    field :request_phone_facility, :string
    field :request_phone_facility_normalized, :string
    field :request_provider_address_1, :string
    field :request_provider_city, :string
    field :request_provider_id, :string
    field :request_provider_name_first, :string
    field :request_provider_name_last, :string
    field :request_specimen_source_name, :string
    field :result, :string
    field :result_analysis_date, :utc_datetime_usec
    field :result_local_test_code, :string
    field :result_local_test_desc, :string
    field :result_loinc_code, :string
    field :result_loinc_desc, :string
    field :result_observation_date, :utc_datetime_usec
    field :result_observation_text, :string
    field :result_observation_text_short, :string
    field :result_producer_lab_name, :string
    field :result_snomed_code, :string
    field :result_snomed_desc, :string
    field :result_status_code, :string
    field :school_code, :string
    field :school_district, :string
    field :school_job_class, :string
    field :school_name, :string
    field :school_present, :string
    field :sending_facility_clia, :string

    belongs_to :county, ECLRS.County
    belongs_to :file, ECLRS.File
    has_many :test_result_events, ECLRS.TestResultEvent
    has_many :events, through: [:test_result_events, :event]
    has_one :about, ECLRS.About

    field :tid, :string
    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, __schema__(:fields) -- [:id])
    |> exclusion_constraint(:raw_data, name: "unique_raw_data_by_hash")
  end
end
