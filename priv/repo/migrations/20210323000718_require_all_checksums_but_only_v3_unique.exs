defmodule NYSETL.Repo.Migrations.RequireAllChecksumsButOnlyV3Unique do
  use Ecto.Migration

  def change do
    abouts_must_have_checksum(:v1)
    abouts_must_have_checksum(:v2)
    abouts_must_have_checksum(:v3)

    create index(:abouts, ["(checksums->>'v1')"], unique: false, name: :abouts_checksum_v1)
    create index(:abouts, ["(checksums->>'v2')"], unique: false, name: :abouts_checksum_v2)

    drop index(:abouts, ["(checksums->>'v1')"], name: :abouts_unique_checksum_v1)
    drop index(:abouts, ["(checksums->>'v2')"], name: :abouts_unique_checksum_v2)

    alter table(:abouts) do
      modify(:checksums, :map, null: false)
      remove :checksum
    end
  end

  defp abouts_must_have_checksum(version) do
    create constraint(:abouts, "must_have_checksum_#{version}",
             check:
               "(checksums->>'#{version}') IS NOT NULL AND TRIM((checksums->>'#{version}')) <> ''"
           )
  end
end
