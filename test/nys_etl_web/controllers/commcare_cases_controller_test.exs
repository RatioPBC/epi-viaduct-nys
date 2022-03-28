defmodule NYSETLWeb.CommcareCasesControllerTest do
  use NYSETLWeb.ConnCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  alias NYSETL.Commcare
  alias NYSETL.Commcare.CaseImporter

  setup [:start_supervised_oban, :midsomer_county, :midsomer_patient_case]

  setup do
    {:ok, true} = FunWithFlags.enable(:commcare_case_forwarder)
    :ok
  end

  describe "create" do
    test "501 when feature flag is off", %{conn: conn, midsomer_patient_case: patient_case} do
      {:ok, false} = FunWithFlags.disable(:commcare_case_forwarder)
      conn = post(conn, Routes.commcare_cases_path(@endpoint, :create), %{"commcare_case" => patient_case})
      assert text_response(conn, 501) =~ "Not Implemented"
    end

    test "create a new index case and person", %{conn: conn, midsomer_county: midsomer, midsomer_patient_case: patient_case} do
      assert {:error, :not_found} = Commcare.get_index_case(case_id: patient_case["case_id"], county_id: midsomer.fips)
      refute_enqueued(worker: CaseImporter)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(Routes.commcare_cases_path(@endpoint, :create), %{"commcare_case" => patient_case})

      assert text_response(conn, 202) =~ "Accepted"
      assert {:error, :not_found} = Commcare.get_index_case(case_id: patient_case["case_id"], county_id: midsomer.fips)
      assert_enqueued(worker: CaseImporter, args: %{commcare_case_id: Map.fetch!(patient_case, "case_id"), domain: midsomer.domain})
    end
  end
end
