defmodule NYSETL.Repo.Migrations.UniqueIndexOnPeople do
  use Ecto.Migration

  def change do
    create unique_index(:people, [:dob, :name_last, :name_first],
             where: "dob is not null and name_last is not null and name_first is not null"
           )
  end
end
