defmodule NYSETL.Repo.Migrations.RenamePhoneColumns do
  use Ecto.Migration

  def change do
    rename table(:test_results), :patient_home_phone, to: :patient_phone_home

    rename table(:test_results), :patient_home_phone_normalized,
      to: :patient_phone_home_normalized

    rename table(:test_results), :request_facility_phone, to: :request_phone_facility

    rename table(:test_results), :request_facility_phone_normalized,
      to: :request_phone_facility_normalized
  end
end
