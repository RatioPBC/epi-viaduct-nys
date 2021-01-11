defmodule NYSETL.Repo.Migrations.AddTidsToLabResults do
  use Ecto.Migration

  def change do
    alter table(:lab_results) do
      add :tid, :string
    end
  end
end
