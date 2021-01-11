defmodule NYSETL.Repo.Migrations.AddExtensions do
  use Ecto.Migration

  def change do
    execute """
            CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public
            """,
            "DROP EXTENSION IF EXISTS citext;"

    execute """
            CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA public
            """,
            """
            DROP EXTENSION IF EXISTS "pgcrypto";
            """

    execute """
            CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public
            """,
            """
            DROP EXTENSION IF EXISTS btree_gist
            """
  end
end
