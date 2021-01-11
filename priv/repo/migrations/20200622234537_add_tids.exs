defmodule NYSETL.Repo.Migrations.AddTids do
  use Ecto.Migration

  def change do
    alter table(:abouts) do
      add :tid, :string
    end

    alter table(:test_results) do
      add :tid, :string
    end

    alter table(:files) do
      add :tid, :string
    end

    alter table(:counties) do
      add :tid, :string
    end
  end
end
