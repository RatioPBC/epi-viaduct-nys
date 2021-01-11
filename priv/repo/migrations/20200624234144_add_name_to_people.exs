defmodule NYSETL.Repo.Migrations.AddNameToPeople do
  use Ecto.Migration

  def change do
    alter table(:people) do
      add :name_first, :text
      add :name_last, :text
      add :dob, :date
    end

    create index(:people, [:name_last, :name_first])
    create index(:people, [:dob])
  end
end
