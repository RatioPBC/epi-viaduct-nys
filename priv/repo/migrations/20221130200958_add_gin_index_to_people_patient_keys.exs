defmodule NYSETL.Repo.Migrations.AddGinIndexToPeoplePatientKeys do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  # Note: You probably don't want to run this in real time.
  # Although postgres doesn't lock the table, the query blocks until it returns.
  # This means that running the migration will be slow (a couple minutes),
  # and the webhook URL will be down until the migration completes.
  def change do
    create_if_not_exists index(:people, [:patient_keys],
                           concurrently: true,
                           using: :gin,
                           name: "people_patient_keys_gin_index"
                         )

    drop_if_exists index(:people, [:patient_keys])
  end
end
