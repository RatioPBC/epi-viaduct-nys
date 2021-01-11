defmodule NYSETL.Repo.Migrations.RenameAbouts do
  use Ecto.Migration

  def change do
    rename table("record_checksums"), to: table("abouts")

    alter table(:abouts) do
      add :last_seen_file_id, references(:files)
    end
  end
end
