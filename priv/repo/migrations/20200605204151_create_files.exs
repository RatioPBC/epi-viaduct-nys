defmodule NYSETL.Repo.Migrations.CreateFiles do
  use Ecto.Migration

  def change do
    create table(:files) do
      add :filename, :string, null: false
      add :processed_at, :utc_datetime
      add :statistics, :map

      timestamps()
    end
  end
end
