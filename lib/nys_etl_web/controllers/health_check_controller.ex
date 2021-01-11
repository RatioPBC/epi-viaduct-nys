defmodule NYSETLWeb.HealthCheckController do
  use NYSETLWeb, :controller

  def index(conn, _params) do
    Ecto.Adapters.SQL.query!(NYSETL.Repo, "SELECT 1", [])
    text(conn, "OK")
  end
end
