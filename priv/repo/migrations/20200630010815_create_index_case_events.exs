defmodule NYSETL.Repo.Migrations.CreateIndexCaseEvents do
  use Ecto.Migration

  def change do
    create table(:index_case_events) do
      add :index_case_id, references(:index_cases), null: false
      add :event_id, references(:events), null: false

      timestamps()
    end

    create index(:index_case_events, [:index_case_id, :event_id])
  end
end
