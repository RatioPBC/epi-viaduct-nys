defmodule NYSETL.Repo.Migrations.CreateChangeLog do
  use Ecto.Migration

  def change do
    create table(:change_logs) do
      add :source_type, :string
      add :source_id, :integer
      add :destination_type, :string
      add :destination_id, :integer
      add :previous_state, :map
      add :applied_changes, :map
      add :dropped_changes, :map

      timestamps()
    end
  end
end
