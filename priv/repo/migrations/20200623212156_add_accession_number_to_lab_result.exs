defmodule NYSETL.Repo.Migrations.AddAccessionNumberToLabResult do
  use Ecto.Migration

  def change do
    alter table(:lab_results) do
      add :accession_number, :string, null: false
    end
  end
end
