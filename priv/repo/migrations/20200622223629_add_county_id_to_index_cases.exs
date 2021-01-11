defmodule NYSETL.Repo.Migrations.AddCountyIdToIndexCases do
  use Ecto.Migration

  def change do
    alter table(:index_cases) do
      add :county_id, references(:counties), null: false
    end

    create index(:index_cases, [:person_id, :county_id])
  end
end
