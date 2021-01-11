defmodule NYSETL.Repo.Migrations.AddUniqueIndexOnIndexCases do
  use Ecto.Migration

  def change do
    create unique_index(:index_cases, [:county_id, :case_id])
  end
end
