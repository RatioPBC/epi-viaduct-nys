defmodule NYSETL.Repo.Migrations.IndexTestResultsEclrsCreateDate do
  use Ecto.Migration

  def change do
    create index(:test_results, :eclrs_create_date)
  end
end
