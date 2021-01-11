defmodule NYSETL.Repo.Migrations.AddTestResultsNormalizedFields do
  use Ecto.Migration

  def change do
    alter table(:test_results) do
      add :patient_home_phone_normalized, :string
      add :request_facility_phone_normalized, :string
    end
  end
end
