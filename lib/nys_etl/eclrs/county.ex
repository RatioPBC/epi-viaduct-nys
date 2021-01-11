defmodule NYSETL.ECLRS.County do
  use NYSETL, :schema

  schema "counties" do
    field :tid, :string
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, [:id, :tid])
    |> validate_required(:id)
    |> unique_constraint([:id], name: :counties_pkey)
  end
end
