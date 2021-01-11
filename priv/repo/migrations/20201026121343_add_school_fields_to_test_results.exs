defmodule NYSETL.Repo.Migrations.AddSchoolFieldsToTestResults do
  use Ecto.Migration

  def change do
    alter table(:test_results) do
      # Source fields are between 30 and 250 chars, so :string is fine.
      add :school_name, :string
      add :school_district, :string
      add :school_code, :string
      add :school_job_class, :string
      add :school_present, :string
    end
  end
end
