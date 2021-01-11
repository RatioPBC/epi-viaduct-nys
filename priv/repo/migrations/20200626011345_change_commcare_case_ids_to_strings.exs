defmodule NYSETL.Repo.Migrations.ChangeCommcareCaseIdsToStrings do
  use Ecto.Migration

  def change do
    alter table(:index_cases) do
      modify :case_id, :string, from: :uuid
    end

    alter table(:lab_results) do
      modify :case_id, :string, from: :uuid
    end
  end
end
