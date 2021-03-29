defmodule NYSETL.Repo.Migrations.AddEclrsV3ColumnsToTestResults do
  use Ecto.Migration

  def change do
    alter table(:test_results) do
      add :first_test, :text
      add :aoe_date, :utc_datetime_usec
      add :healthcare_employee, :text
      add :eclrs_symptomatic, :text
      add :eclrs_symptom_onset_date, :utc_datetime_usec
      add :eclrs_hospitalized, :text
      add :eclrs_icu, :text
      add :eclrs_congregate_care_resident, :text
      add :eclrs_pregnant, :text
    end
  end
end
