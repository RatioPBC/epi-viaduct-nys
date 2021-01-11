defmodule NYSETL.Commcare.IndexCase do
  use NYSETL, :schema

  alias NYSETL.Commcare
  alias NYSETL.ECLRS

  schema "index_cases" do
    field :case_id, :string, read_after_writes: true
    field :data, :map
    field :tid, :string

    belongs_to :county, ECLRS.County
    belongs_to :person, Commcare.Person
    has_many :lab_results, Commcare.LabResult
    has_many :index_case_events, Commcare.IndexCaseEvent
    has_many :events, through: [:index_case_events, :event]

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, __schema__(:fields) -- [:id])
    |> validate_required([:data])
    |> unique_constraint(:case_id)
  end
end
