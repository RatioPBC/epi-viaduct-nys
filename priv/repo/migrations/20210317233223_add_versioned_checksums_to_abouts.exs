defmodule NYSETL.Repo.Migrations.AddVersionedChecksumsToAbouts do
  use Ecto.Migration

  def change do
    alter table(:abouts) do
      add :checksums, :map
    end

    create index(:abouts, ["(checksums->>'v1')"], unique: true, name: :abouts_unique_checksum_v1)
    create index(:abouts, ["(checksums->>'v2')"], unique: true, name: :abouts_unique_checksum_v2)
    create index(:abouts, ["(checksums->>'v3')"], unique: true, name: :abouts_unique_checksum_v3)
  end
end
