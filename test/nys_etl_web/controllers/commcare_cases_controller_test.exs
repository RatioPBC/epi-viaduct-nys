defmodule NYSETLWeb.CommcareCasesControllerTest do
  use NYSETLWeb.ConnCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  alias NYSETL.Commcare
  alias NYSETL.Commcare.CaseImporter

  setup [:start_supervised_oban, :midsomer_county, :midsomer_patient_case, :fwf_case_forwarder]

  describe "create" do
    test "501 when feature flag is off", %{conn: conn, midsomer_patient_case: patient_case} do
      {:ok, false} = FunWithFlags.disable(:commcare_case_forwarder)
      conn = post(conn, Routes.commcare_cases_path(@endpoint, :create), %{"commcare_case" => patient_case})

      assert text_response(conn, 501) =~ "Not Implemented"
      refute_enqueued(worker: CaseImporter)
    end

    test "create an oban job and nothing else", %{conn: conn, midsomer_county: midsomer, midsomer_patient_case: patient_case} do
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

    test "don't create an oban job when user_id belongs to viaduct", %{conn: conn, midsomer_patient_case: patient_case} do
      patient_case = Map.put(patient_case, "user_id", "viaduct-test-commcare-user-id")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(Routes.commcare_cases_path(@endpoint, :create), %{"commcare_case" => patient_case})

      assert text_response(conn, 202) =~ "Accepted"
      refute_enqueued(worker: CaseImporter)
    end

    test "422 when payload is the wrong type", %{conn: conn, midsomer_patient_case: patient_case} do
      patient_case = put_in(patient_case, ["properties", "case_type"], "lab_result")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(Routes.commcare_cases_path(@endpoint, :create), %{"commcare_case" => patient_case})

      assert text_response(conn, 422) =~ "Unprocessable Entity. Can only import `patient` cases. #{patient_case["case_id"]} is a `lab_result`"
      refute_enqueued(worker: CaseImporter)
    end
  end
end
