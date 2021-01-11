defmodule NYSETL.Repo.Migrations.AboutsEnforceNonNull do
  use Ecto.Migration

  def change do
    alter table(:abouts) do
      modify :last_seen_at, :utc_datetime, null: false
      modify :last_seen_file_id, references(:files), from: references(:files), null: false
    end
  end
end
