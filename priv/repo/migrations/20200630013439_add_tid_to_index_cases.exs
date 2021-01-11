defmodule NYSETL.Repo.Migrations.AddTidToIndexCases do
  use Ecto.Migration

  def change do
    alter table(:index_cases) do
      add :tid, :string
    end
  end
end
