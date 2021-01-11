defmodule NYSETL.Repo.Migrations.BackfillPaperTrailVersions do
  use Ecto.Migration

  def up do
    NYSETL.Tasks.BackfillPapertrailVersions.run()
  end

  def down do
    IO.puts(
      "This migration does not rollback the backfilled PaperTrail versions. If you wish to do so, you should rollback 20200805214112_add_versions."
    )
  end
end
