defmodule NYSETLWeb.ReportsLiveTest do
  use NYSETLWeb.ConnCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  import Phoenix.LiveViewTest
  import Plug.BasicAuth, only: [encode_basic_auth: 2]

  alias NYSETL.Commcare
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E4.CommcareCaseLoader
  alias NYSETL.Repo

  setup :start_supervised_oban

  setup context do
    conn = put_admin_auth(context.conn)
    %{context | conn: conn}
  end

  test "unprocessed test results", %{conn: conn} do
    {:ok, page, _html} = live(conn, "/admin/reports")

    {:ok, county} = ECLRS.find_or_create_county(71)
    {:ok, file} = Factory.file_attrs() |> ECLRS.create_file()

    {:ok, processed_tr_1} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()
    ECLRS.save_event(processed_tr_1, "processed")

    {:ok, processed_tr_2} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()
    ECLRS.save_event(processed_tr_2, "processed")

    {:ok, failed_tr_1} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()
    ECLRS.save_event(failed_tr_1, "processing_failed")

    {:ok, failed_tr_2} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()
    ECLRS.save_event(failed_tr_2, "processing_failed")

    {:ok, _unprocessed_tr_1} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()
    {:ok, _unprocessed_tr_2} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()
    {:ok, _unprocessed_tr_3} = Factory.test_result_attrs(county_id: county.id, file_id: file.id) |> ECLRS.create_test_result()

    page
    |> element("#test_results button", "Count")
    |> render_click()

    assert page
           |> element("#test_results span")
           |> render()
           |> Floki.text() == "3"
  end

  test "unprocessed index cases", %{conn: conn} do
    {:ok, page, _html} = live(conn, "/admin/reports")

    {:ok, _county} = ECLRS.find_or_create_county(1111)
    {:ok, _county} = ECLRS.find_or_create_county(9999)
    {:ok, _county} = ECLRS.find_or_create_county(1234)

    person = %{data: %{}, patient_keys: ["123"]} |> Commcare.Person.changeset() |> Repo.insert!()

    {:ok, %{case_id: processed_id} = processed_index_case} = %{data: %{}, person_id: person.id, county_id: 1111} |> Commcare.create_index_case()
    Commcare.save_event(processed_index_case, "send_to_commcare_succeeded")

    {:ok, %{case_id: enqueued_id} = enqueued_index_case} = %{data: %{}, person_id: person.id, county_id: 9999} |> Commcare.create_index_case()
    Commcare.save_event(enqueued_index_case, "send_to_commcare_succeeded")
    Commcare.save_event(enqueued_index_case, "send_to_commcare_enqueued")

    {:ok, %{case_id: unprocessed_id}} = %{data: %{}, person_id: person.id, county_id: 1234} |> Commcare.create_index_case()

    page
    |> element("#index_cases button", "Count")
    |> render_click()

    assert page
           |> element("#index_cases span")
           |> render()
           |> Floki.text() == "2"

    page
    |> element("#index_cases button", "Process")
    |> render_click()

    assert_enqueued(worker: CommcareCaseLoader, args: %{"case_id" => enqueued_id, "county_id" => "9999"})
    assert_enqueued(worker: CommcareCaseLoader, args: %{"case_id" => unprocessed_id, "county_id" => "1234"})
    refute_enqueued(worker: CommcareCaseLoader, args: %{"case_id" => processed_id, "county_id" => "1111"})

    assert page |> render() |> Floki.find("#index_cases button") == []

    assert page
           |> element("#index_cases span")
           |> render()
           |> Floki.text() == "2 index cases enqueued"
  end

  defp put_admin_auth(conn) do
    put_req_header(conn, "authorization", encode_basic_auth("test", "test"))
  end
end
