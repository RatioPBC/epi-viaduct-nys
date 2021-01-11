defmodule NYSETL.Repo.Migrations.RenamePatientIdToPatientKey do
  use Ecto.Migration

  def change do
    rename table(:test_results), :patient_id, to: :patient_key
  end
end
