defmodule NYSETL.Repo.Migrations.IndexIndexCasesDataTransferSourceCaseId do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:index_cases, ["(data->>'transfer_source_case_id')"],
             concurrently: true,
             name: :index_cases_data_transfer_source_case_id_index
           )
  end
end
