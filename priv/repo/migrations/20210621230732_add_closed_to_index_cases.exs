defmodule NYSETL.Repo.Migrations.AddClosedToIndexCases do
  use Ecto.Migration

  def change do
    alter table("index_cases") do
      add :closed, :boolean, null: false, default: false
    end
  end
end
