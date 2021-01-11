defmodule NYSETL.Repo.Migrations.CreateCounties do
  use Ecto.Migration

  def change do
    create table(:counties, primary_key: false) do
      add :id, :bigint, primary_key: true, null: false
    end
  end
end
