defmodule NYSETL.Repo.Migrations.AddUniqueConstraintOnIndexCaseCaseId do
  use Ecto.Migration

  def change do
    create unique_index(:index_cases, [:case_id])
  end
end
