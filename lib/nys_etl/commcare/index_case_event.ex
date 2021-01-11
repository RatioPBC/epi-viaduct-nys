defmodule NYSETL.Commcare.IndexCaseEvent do
  use NYSETL, :schema

  alias NYSETL.Commcare

  schema "index_case_events" do
    timestamps()

    belongs_to :event, NYSETL.Event
    belongs_to :index_case, Commcare.IndexCase
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, [:index_case_id, :event_id])
    |> cast_assoc(:event, required: true)
    |> validate_required([:index_case_id])
  end
end
