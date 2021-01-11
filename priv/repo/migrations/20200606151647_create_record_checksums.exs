defmodule NYSETL.Repo.Migrations.CreateRecordChecksums do
  use Ecto.Migration

  def change do
    create table(:record_checksums) do
      add :checksum, :string, null: false
      add :patient_key_id, :bigint, null: false
      add :first_seen_file_id, references(:files), null: false
      add :last_seen_at, :utc_datetime_usec
      add :county_id, references(:counties), null: false

      timestamps()
    end

    create index(:record_checksums, :checksum, unique: true)
  end
end
