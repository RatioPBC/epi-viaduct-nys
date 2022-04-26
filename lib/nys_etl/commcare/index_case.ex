defmodule NYSETL.Commcare.IndexCase do
  use NYSETL, :schema

  alias NYSETL.Commcare
  alias NYSETL.ECLRS

  schema "index_cases" do
    field :case_id, :string, read_after_writes: true
    field :closed, :boolean, default: false
    field :data, :map
    field :tid, :string
    field :commcare_date_modified, :utc_datetime_usec

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
    |> cast_closed()
    |> validate_required([:data])
    |> unique_constraint(:case_id)
  end

  defp cast_closed(changeset) do
    if changeset |> get_field(:closed) |> is_nil() do
      put_change(changeset, :closed, false)
    else
      changeset
    end
  end
end
