defmodule NYSETL.Tasks.BackfillPapertrailVersions do
  alias NYSETL.Repo
  alias NYSETL.Commcare
  import Ecto.Query

  def run do
    Repo.transaction(fn ->
      backfill_model(Commcare.Person, "Person", [:data, :patient_keys, :name_first, :name_last, :dob])
      backfill_model(Commcare.IndexCase, "IndexCase", [:data, :person_id, :county_id, :case_id, :tid])
      backfill_model(Commcare.LabResult, "LabResult", [:data, :index_case_id, :case_id, :accession_number, :tid])
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
