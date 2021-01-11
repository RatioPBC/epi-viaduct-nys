defmodule NYSETL.Repo.Migrations.RenameCommcareLoader do
  use Ecto.Migration

  import Ecto.Query

  def up do
    query =
      from(o in Oban.Job,
        where: o.worker == "NYSETL.Loader.CommcareCaseLoader" and o.state != "completed",
        update: [set: [worker: "NYSETL.Engines.E4.CommcareCaseLoader"]]
      )

    NYSETL.Repo.update_all(query, [])
  end

  def down do
    query =
      from(o in Oban.Job,
        where: o.worker == "NYSETL.Engines.E4.CommcareCaseLoader" and o.state != "completed",
        update: [set: [worker: "NYSETL.Loader.CommcareCaseLoader"]]
      )

    NYSETL.Repo.update_all(query, [])
  end
end
