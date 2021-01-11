defmodule NYSETL.Repo.Migrations.AddTypeIndexToEvents do
  use Ecto.Migration

  def change do
    create index(:events, [:type])
  end
end
