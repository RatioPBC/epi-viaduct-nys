defmodule NYSETLWeb.CommcareCasesController do
  use NYSETLWeb, :controller

  alias NYSETL.Commcare.CaseImporter

  @viaduct_commcare_user_ids Application.compile_env(:nys_etl, :viaduct_commcare_user_ids) |> MapSet.new()

  def create(conn, params) do
    {status, message} = require_case_forwarder_enabled() || require_params(params) || require_patient_case_type(params) || accept_case(params)

    conn
    |> put_status(status)
    |> text(message)
  end

  defp require_case_forwarder_enabled() do
    unless FunWithFlags.enabled?(:commcare_case_forwarder) do
      {501, "Not Implemented"}
    end
  end

  defp require_params(%{"case_id" => _, "domain" => _, "user_id" => _, "properties" => %{"case_type" => _}}), do: nil

  defp require_params(_) do
    {400, "Bad Request"}
  end

  defp require_patient_case_type(%{"case_id" => case_id, "properties" => %{"case_type" => case_type}}) do
    unless case_type == "patient" do
      {422, "Unprocessable Entity. Can only import `patient` cases. #{case_id} is a `#{case_type}`."}
    end
  end

  defp accept_case(%{"case_id" => case_id, "domain" => domain, "user_id" => user_id}) do
    unless MapSet.member?(@viaduct_commcare_user_ids, user_id) do
      CaseImporter.new(%{commcare_case_id: case_id, domain: domain})
      |> Oban.insert!()
    end

    {202, "Accepted"}
  end
end
