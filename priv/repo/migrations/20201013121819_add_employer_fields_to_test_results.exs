defmodule NYSETL.Repo.Migrations.AddEmployerFieldsToTestResults do
  use Ecto.Migration

  def change do
    alter table(:test_results) do
      # Source fields are between 30 and 250 chars, so :string is fine.
      add :employer_name, :string
      add :employer_address, :string
      add :employer_phone, :string
      add :employer_phone_alt, :string
      add :employee_number, :string
      add :employee_job_title, :string
    end
  end
end
