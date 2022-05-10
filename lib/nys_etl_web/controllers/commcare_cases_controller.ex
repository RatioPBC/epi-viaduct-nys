defmodule NYSETLWeb.CommcareCasesController do
  use NYSETLWeb, :controller

  alias NYSETL.Commcare.CaseImporter

  @viaduct_commcare_user_ids Application.compile_env(:nys_etl, :viaduct_commcare_user_ids) |> MapSet.new()

  def check(conn, _params), do: respond_with({200, "OK"}, conn)

  def create_or_update(conn, params) do
    %{commcare_case: params}
    |> process_case_forward(conn, params)
  end

  defp process_case_forward(job_params, conn, params) do
    with :ok <- require_params(params),
         :ok <- require_patient_case_type(params),
         :ok <- require_non_viaduct_user_id(params) do
      job_params
      |> CaseImporter.new()
      |> Oban.insert!()

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

  defp require_params(%{"case_id" => _, "domain" => _, "user_id" => _, "properties" => %{"case_type" => _}}), do: :ok

  defp require_params(_), do: {400, "Bad Request"}

  defp require_patient_case_type(%{"properties" => %{"case_type" => "patient"}}), do: :ok

  defp require_patient_case_type(%{"case_id" => case_id, "properties" => %{"case_type" => case_type}}) do
    {422, "Unprocessable Entity. Can only import `patient` cases. #{case_id} is a `#{case_type}`."}
  end

  defp require_non_viaduct_user_id(params) do
    if MapSet.member?(@viaduct_commcare_user_ids, params["user_id"]) do
      {202, "Accepted"}
    else
      :ok
    end
  end
end
