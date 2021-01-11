defmodule NYSETL.Repo.Migrations.CreateTestResultEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :type, :string
      timestamps()
    end

    create table(:test_result_events) do
      add :test_result_id, references(:test_results), null: false
      add :event_id, references(:events), null: false
      timestamps()
    end
  end
end
