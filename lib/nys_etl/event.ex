defmodule NYSETL.Event do
  use NYSETL, :schema

  schema "events" do
    field :type, :string
    field :data, :map
    field :stash, :string

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, [:data, :stash, :type])
    |> validate_required([:type])
  end
end
