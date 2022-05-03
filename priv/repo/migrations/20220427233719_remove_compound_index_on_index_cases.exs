defmodule NYSETL.Repo.Migrations.RemoveCompoundIndexOnIndexCases do
  use Ecto.Migration

  # Reverses AddUniqueIndexOnIndexCases migration,
  # which added a compound index on [:county_id, :case_id] which was later
  # made obsolete by AddUniqueConstraintOnIndexCaseCaseId

  def up do
    drop index(:index_cases, [:county_id, :case_id])
  end

  def down do
    create unique_index(:index_cases, [:county_id, :case_id])
  end
end
