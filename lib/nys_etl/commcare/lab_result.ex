defmodule NYSETL.Commcare.LabResult do
  use NYSETL, :schema

  alias NYSETL.Commcare

  schema "lab_results" do
    field :accession_number, :string
    field :case_id, :string, read_after_writes: true
    field :data, :map
    field :tid, :string

    belongs_to :index_case, Commcare.IndexCase

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, __schema__(:fields) -- [:id])
    |> validate_required([:accession_number, :data])
  end
end
