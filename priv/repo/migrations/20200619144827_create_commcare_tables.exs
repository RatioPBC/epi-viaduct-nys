defmodule NYSETL.Repo.Migrations.CreateCommcareTables do
  use Ecto.Migration

  def change do
    drop table(:commcare_patients)

    create table(:people) do
      add :patient_keys, {:array, :string}, null: false
      add :data, :map, null: false

      timestamps()
    end

    create table(:index_cases) do
      add :person_id, references(:people), null: false
      add :case_id, :uuid, default: fragment("gen_random_uuid()")
      add :data, :map, null: false

      timestamps()
    end

    create table(:lab_results) do
      add :index_case_id, references(:index_cases), null: false

      add :case_id, :uuid, default: fragment("gen_random_uuid()")
      add :data, :map, null: false

      timestamps()
    end
  end
end
