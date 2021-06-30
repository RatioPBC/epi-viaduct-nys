defmodule NYSETL.Commcare.Person do
  use NYSETL, :schema

  alias NYSETL.Commcare

  schema "people" do
    field :patient_keys, {:array, :string}
    field :data, :map
    field :name_last, :string
    field :name_first, :string
    field :dob, :date

    has_many :index_cases, Commcare.IndexCase

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, __schema__(:fields) -- [:id])
    |> validate_required([:data, :patient_keys])
    |> validate_identifiers()
  end

  defp validate_identifiers(changeset) do
    if get_field(changeset, :patient_keys) == [] do
      changeset
      |> validate_required([:name_first, :name_last, :dob])
    else
      changeset
    end
  end
end
