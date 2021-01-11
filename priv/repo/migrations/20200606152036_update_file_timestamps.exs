defmodule NYSETL.Repo.Migrations.UpdateFileTimestamps do
  use Ecto.Migration

  def change do
    alter table(:files) do
      remove :processed_at, :utc_datetime
      add :processing_started_at, :utc_datetime_usec
      add :processing_completed_at, :utc_datetime_usec
    end
  end
end
