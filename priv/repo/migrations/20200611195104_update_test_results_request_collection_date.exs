defmodule NYSETL.Repo.Migrations.UpdateTestResultsRequestCollectionDate do
  use Ecto.Migration

  def change do
    alter table(:test_results) do
      remove :request_collection_date, :text
      add :request_collection_date, :utc_datetime
    end
  end
end
