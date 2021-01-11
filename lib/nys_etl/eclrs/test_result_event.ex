defmodule NYSETL.ECLRS.TestResultEvent do
  use NYSETL, :schema

  alias NYSETL.ECLRS

  schema "test_result_events" do
    timestamps()

    belongs_to :event, NYSETL.Event
    belongs_to :test_result, ECLRS.TestResult
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, [:test_result_id, :event_id])
    |> cast_assoc(:event, required: true)
    |> validate_required([:test_result_id])
  end
end
