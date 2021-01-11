defmodule NYSETL.ECLRS.File do
  use NYSETL, :schema

  schema "files" do
    field :filename, :string
    field :processing_started_at, :utc_datetime_usec
    field :processing_completed_at, :utc_datetime_usec
    field :statistics, :map
    field :tid, :string
    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, [:filename, :processing_started_at, :processing_completed_at, :statistics, :tid])
    |> validate_required(:filename)
  end
end
