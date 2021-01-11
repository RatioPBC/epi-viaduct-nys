defmodule NYSETL.Repo.Migrations.AddFilenameConstraintToFiles do
  use Ecto.Migration

  def change do
    create unique_index(:files, :filename)
  end
end
