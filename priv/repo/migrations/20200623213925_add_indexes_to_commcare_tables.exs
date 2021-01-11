defmodule NYSETL.Repo.Migrations.AddIndexesToCommcareTables do
  use Ecto.Migration

  def change do
    create index(:people, [:patient_keys])
    create index(:lab_results, [:index_case_id])
  end
end
