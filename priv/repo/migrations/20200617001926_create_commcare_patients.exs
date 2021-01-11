defmodule NYSETL.Repo.Migrations.CreateCommcarePatients do
  use Ecto.Migration

  def change do
    create table(:commcare_patients) do
      add :case_id, :uuid, default: fragment("gen_random_uuid()")
      add :patient_keys, {:array, :string}, null: false
      add :data, :map, null: false

      timestamps()
    end
  end
end
