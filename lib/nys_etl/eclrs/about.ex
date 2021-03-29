defmodule NYSETL.ECLRS.About do
  @moduledoc """
  Persists metadata about an ECRLS.TestResult.
  """

  use NYSETL, :schema

  alias NYSETL.ECLRS

  schema "abouts" do
    field :checksum, :string
    field :last_seen_at, :utc_datetime_usec
    field :patient_key_id, :integer
    field :tid, :string

    embeds_one :checksums, Checksums do
      field :v1, :string
      field :v2, :string
      field :v3, :string
    end

    belongs_to :county, ECLRS.County
    belongs_to :test_result, ECLRS.TestResult
    belongs_to :first_seen_file, ECLRS.File, foreign_key: :first_seen_file_id
    belongs_to :last_seen_file, ECLRS.File, foreign_key: :last_seen_file_id

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, [:checksum, :patient_key_id, :first_seen_file_id, :last_seen_at, :last_seen_file_id, :county_id, :test_result_id, :tid])
    |> cast_embed(:checksums, with: &checksums_changeset/2)
    |> validate_required([:checksum, :patient_key_id, :first_seen_file_id, :last_seen_at, :last_seen_file_id, :county_id])
    |> unique_constraint([:checksum], name: :record_checksums_checksum_index)
    |> unique_constraint(:checksums, name: :abouts_unique_checksum_v, match: :prefix)
  end

  def from_test_result(test_result, checksums, file) do
    %{
      checksum: checksums.v1,
      checksums: checksums,
      county_id: test_result.county_id,
      first_seen_file_id: file.id,
      last_seen_at: DateTime.utc_now(),
      last_seen_file_id: file.id,
      patient_key_id: test_result.patient_key,
      test_result_id: test_result.id
    }
  end

  defp checksums_changeset(schema, params) do
    schema
    |> cast(params, [:v1, :v2, :v3])
  end
end
