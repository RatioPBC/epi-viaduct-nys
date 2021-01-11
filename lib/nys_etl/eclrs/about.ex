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

    belongs_to :county, ECLRS.County
    belongs_to :test_result, ECLRS.TestResult
    belongs_to :first_seen_file, ECLRS.File, foreign_key: :first_seen_file_id
    belongs_to :last_seen_file, ECLRS.File, foreign_key: :last_seen_file_id

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, [:checksum, :patient_key_id, :first_seen_file_id, :last_seen_at, :last_seen_file_id, :county_id, :test_result_id, :tid])
    |> validate_required([:checksum, :patient_key_id, :first_seen_file_id, :last_seen_at, :last_seen_file_id, :county_id])
    |> unique_constraint([:checksum], name: :record_checksums_checksum_index)
  end

  def from_test_result(test_result, checksum, file_id) do
    %{
      checksum: checksum,
      county_id: test_result.county_id,
      first_seen_file_id: file_id,
      last_seen_at: DateTime.utc_now(),
      last_seen_file_id: file_id,
      patient_key_id: test_result.patient_key,
      test_result_id: test_result.id
    }
  end
end
