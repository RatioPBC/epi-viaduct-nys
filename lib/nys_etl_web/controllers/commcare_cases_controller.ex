defmodule NYSETLWeb.CommcareCasesController do
  use NYSETLWeb, :controller

  alias NYSETL.Commcare.CaseImporter

  @viaduct_commcare_user_ids Application.compile_env(:nys_etl, :viaduct_commcare_user_ids) |> MapSet.new()

  def index(conn, _params) do
    case require_case_forwarder_enabled() do
      :ok -> {200, "OK"}
      response -> response
    end
    |> respond_with(conn)
  end

  def create(conn, params) do
    with :ok <- require_case_forwarder_enabled(),
         :ok <- require_params(params),
         :ok <- require_patient_case_type(params) do
      unless MapSet.member?(@viaduct_commcare_user_ids, params["user_id"]) do
        CaseImporter.new(%{commcare_case_id: params["case_id"], domain: params["domain"]})
        |> Oban.insert!()
      end

      {202, "Accepted"}
    else
      response -> response
    end
    |> respond_with(conn)
  end

  defp respond_with({status, message}, conn) do
    conn
    |> put_status(status)
    |> text(message)
  end

  defp require_case_forwarder_enabled() do
    if FunWithFlags.enabled?(:commcare_case_forwarder) do
      :ok
    else
      {501, "Not Implemented"}
    end
  end

  defp require_params(%{"case_id" => _, "domain" => _, "user_id" => _, "properties" => %{"case_type" => _}}), do: :ok

  defp require_params(_), do: {400, "Bad Request"}

  defp require_patient_case_type(%{"properties" => %{"case_type" => "patient"}}), do: :ok

  defp require_patient_case_type(%{"case_id" => case_id, "properties" => %{"case_type" => case_type}}) do
    {422, "Unprocessable Entity. Can only import `patient` cases. #{case_id} is a `#{case_type}`."}
  end
end
