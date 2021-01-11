defmodule NYSETL.Repo.Migrations.AddIndexToTestResultEvents do
  use Ecto.Migration

  def change do
    create index(:test_result_events, [:test_result_id, :event_id])
  end
end
