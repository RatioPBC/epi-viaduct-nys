defmodule NYSETL.Repo.Migrations.AddVariousIndexesForTestResults do
  use Ecto.Migration

  def change do
    create index(:test_results, [:patient_key])
    create index(:test_results, [:patient_dob])
    create index(:test_results, [:patient_name_last, :patient_name_first, :patient_name_middle])
    create index(:test_results, [:patient_phone_home_normalized])
  end
end
