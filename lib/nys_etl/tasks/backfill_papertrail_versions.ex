defmodule NYSETL.Tasks.BackfillPapertrailVersions do
  alias NYSETL.Repo
  import Ecto.Query

  # These schemas are snapshot of the corresponding schemas at the time
  # the migration was written. This allows the actual schemas to change
  # without breaking the migration that uses this backfiller.
  # This only matters when running the migrations from scratch, e.g. in CI
  defmodule MigrationSchemas do
    defmodule Person do
      use NYSETL, :schema

      schema "people" do
        field :patient_keys, {:array, :string}
        field :data, :map
        field :name_last, :string
        field :name_first, :string
        field :dob, :date

        timestamps()
      end
    end

    defmodule IndexCase do
      use NYSETL, :schema

      schema "index_cases" do
        field :case_id, :string, read_after_writes: true
        field :data, :map
        field :tid, :string

        field :county_id, :integer
        field :person_id, :integer

        timestamps()
      end
    end

    defmodule LabResult do
      use NYSETL, :schema

      schema "lab_results" do
        field :accession_number, :string
        field :case_id, :string, read_after_writes: true
        field :data, :map
        field :tid, :string

        field :index_case_id, :integer

        timestamps()
      end
    end
  end

  def run do
    Repo.transaction(fn ->
      backfill_model(MigrationSchemas.Person, "Person", [:data, :patient_keys, :name_first, :name_last, :dob])
      backfill_model(MigrationSchemas.IndexCase, "IndexCase", [:data, :person_id, :county_id, :case_id, :tid])
      backfill_model(MigrationSchemas.LabResult, "LabResult", [:data, :index_case_id, :case_id, :accession_number, :tid])
    end)
  end

  def backfill_model(struct_type, item_type, fields) do
    from(struct_type)
    |> Repo.stream()
    |> Enum.each(fn record ->
      %PaperTrail.Version{
        event: "insert",
        item_type: item_type,
        item_id: record.id,
        item_changes: Map.take(record, fields ++ [:id, :inserted_at, :updated_at]),
        origin: "backfill"
      }
      |> Repo.insert()
    end)
  end
end
