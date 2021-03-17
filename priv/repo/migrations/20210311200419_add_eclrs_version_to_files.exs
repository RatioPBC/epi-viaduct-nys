defmodule NYSETL.Repo.Migrations.AddEclrsVersionToFiles do
  use Ecto.Migration

  def change do
    alter table("files") do
      add :eclrs_version, :integer
    end
  end
end
