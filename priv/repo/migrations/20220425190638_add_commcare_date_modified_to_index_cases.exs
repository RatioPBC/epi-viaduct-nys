defmodule NYSETL.Repo.Migrations.AddCommcareDateModifiedToIndexCases do
  use Ecto.Migration

  def change do
    alter table(:index_cases) do
      add :commcare_date_modified, :utc_datetime_usec
    end
  end
end
