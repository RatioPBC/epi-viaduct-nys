defmodule NYSETL.ChangeLog do
  use NYSETL, :schema

  schema "change_logs" do
    field :source_type, :string
    field :source_id, :integer
    field :destination_type, :string
    field :destination_id, :integer
    field :previous_state, :map
    field :applied_changes, :map
    field :dropped_changes, :map

    timestamps()
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, __schema__(:fields) -- [:id])
    |> validate_required([:source_type, :source_id, :destination_type, :destination_id, :previous_state, :applied_changes])
  end
end
