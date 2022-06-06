defmodule NYSETLWeb.ReportsLiveTest do
  use NYSETLWeb.ConnCase, async: false
  use Oban.Testing, repo: NYSETL.Repo

  import Phoenix.LiveViewTest
  import Plug.BasicAuth, only: [encode_basic_auth: 2]

  alias NYSETL.ECLRS

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

  defp put_admin_auth(conn) do
    put_req_header(conn, "authorization", encode_basic_auth("test", "test"))
  end
end
