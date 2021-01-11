defmodule NYSETL.Repo.Migrations.CreateIndexForRawDataOnTestResult do
  use Ecto.Migration

  def change do
    create(index(:test_results, [:raw_data], using: :hash))

    create(
      constraint(:test_results, "unique_raw_data_by_hash", exclude: "hash (raw_data with =)")
    )
  end
end
