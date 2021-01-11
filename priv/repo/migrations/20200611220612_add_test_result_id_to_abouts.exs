defmodule NYSETL.Repo.Migrations.AddTestResultIdToAbouts do
  use Ecto.Migration

  def change do
    alter table(:abouts) do
      add :test_result_id, references(:test_results), null: false
    end
  end
end
