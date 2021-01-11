defmodule NYSETL.Repo.Migrations.AddDataAndStashToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add(:data, :map)
      add(:stash, :text)
    end
  end
end
