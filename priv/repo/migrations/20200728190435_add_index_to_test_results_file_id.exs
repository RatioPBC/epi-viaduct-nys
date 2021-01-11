defmodule NYSETL.Repo.Migrations.AddIndexToTestResultsFileId do
  use Ecto.Migration

  def change do
    create index(:test_results, [:file_id])
  end
end
