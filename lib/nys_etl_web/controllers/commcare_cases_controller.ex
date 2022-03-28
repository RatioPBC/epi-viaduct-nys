defmodule NYSETLWeb.CommcareCasesController do
  use NYSETLWeb, :controller

  alias NYSETL.Commcare.CaseImporter

  def create(conn, %{"commcare_case" => %{"case_id" => case_id, "domain" => domain}}) do
    if FunWithFlags.enabled?(:commcare_case_forwarder) do
      CaseImporter.new(%{commcare_case_id: case_id, domain: domain})
      |> Oban.insert!()

      conn
      |> put_status(202)
      |> text("Accepted")
    else
      conn
      |> put_status(501)
      |> text("Not Implemented")
    end
  end
end
