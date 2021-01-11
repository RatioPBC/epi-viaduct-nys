defmodule NYSETL.Repo.Migrations.TestResultsKeepUsec do
  use Ecto.Migration

  def change do
    alter table(:test_results) do
      modify :eclrs_create_date, :utc_datetime_usec, from: :utc_datetime
      modify :patient_updated_at, :utc_datetime_usec, from: :utc_datetime
      modify :request_collection_date, :utc_datetime_usec, from: :utc_datetime
      modify :result_analysis_date, :utc_datetime_usec, from: :utc_datetime
      modify :result_observation_date, :utc_datetime_usec, from: :utc_datetime
    end
  end
end
