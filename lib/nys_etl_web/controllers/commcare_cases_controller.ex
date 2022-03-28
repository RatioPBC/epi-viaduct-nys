defmodule NYSETLWeb.CommcareCasesController do
  use NYSETLWeb, :controller

  alias NYSETL.Commcare.CaseImporter

  @viaduct_commcare_user_ids Application.compile_env(:nys_etl, :viaduct_commcare_user_ids) |> MapSet.new()

  def create(conn, %{"commcare_case" => %{"case_id" => case_id, "domain" => domain, "user_id" => user_id}}) do
    if FunWithFlags.enabled?(:commcare_case_forwarder) do
      unless MapSet.member?(@viaduct_commcare_user_ids, user_id) do
        CaseImporter.new(%{commcare_case_id: case_id, domain: domain})
        |> Oban.insert!()
      end

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
