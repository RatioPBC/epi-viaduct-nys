defmodule NYSETL.Engines.E4.XmlBuilderTest do
  use NYSETL.DataCase, async: true

  alias NYSETL.Commcare
  alias NYSETL.Engines.E4.{Data, XmlBuilder}
  alias NYSETL.ECLRS
  alias NYSETL.Extra
  alias NYSETL.Test

  describe "xml builder" do
    setup do
      now_as_string = "2020-06-10T01:02:03Z"
      {:ok, now_as_date_time, _offset} = DateTime.from_iso8601(now_as_string)

      {:ok, _county} = ECLRS.find_or_create_county(111)
      {:ok, person} = %{data: %{}, patient_keys: ["123", "456"]} |> Commcare.create_person()

      {:ok, index_case} =
        %{
          data: %{
            "full_name" => "index-case-full-name",
            "field1" => "value1"
          },
          person_id: person.id,
          county_id: 111,
          case_id: "index-case-id"
        }
        |> Commcare.create_index_case()

      {:ok, _lab_result} =
        %{data: %{"field1" => "value1", "field2" => "value2"}, index_case_id: index_case.id, accession_number: "lab_result_accession_number"}
        |> Commcare.create_lab_result()

      data_from_index_case = Data.from_index_case(index_case, "COUNTY_LOCATION_ID", now_as_date_time)
      xml = data_from_index_case |> XmlBuilder.build()
      doc = xml |> Floki.parse_document!()

      [doc: doc, now: now_as_string, data_from_index_case: data_from_index_case, xml: xml]
    end

    test "xml has <?xml> element", %{xml: xml} do
      assert xml |> String.starts_with?(~s|<?xml version=\"1.0\" encoding=\"UTF-8\"?>|)
    end

    test "xml contains base data", %{doc: doc, now: now, data_from_index_case: data_from_index_case} do
      assert Test.Xml.attr(doc, "data", "xmlns") == "http://geometer.io/viaduct-nys"
      assert Test.Xml.attr(doc, "case:nth-of-type(1)", "xmlns:n0") == "http://commcarehq.org/case/transaction/v2"
      assert Test.Xml.attr(doc, "case:nth-of-type(1)", "case_id") == data_from_index_case.index_case.case_id
      assert Test.Xml.attr(doc, "case:nth-of-type(1)", "user_id") == "test-user-id"
      assert Test.Xml.attr(doc, "case:nth-of-type(1)", "date_modified") == now
      assert Test.Xml.text(doc, "case:nth-of-type(1) create case_type") == "patient"
      assert Test.Xml.text(doc, "case:nth-of-type(1) create case_name") == "index-case-full-name"
    end

    test "xml contains metadata", %{doc: doc, now: now} do
      assert Test.Xml.attr(doc, "meta", "xmlns:n1") == "http://openrosa.org/jr/xforms"
      assert Test.Xml.text(doc, "meta timeStart") == now
      assert Test.Xml.text(doc, "meta timeEnd") == now
      assert Test.Xml.text(doc, "meta username") == "test-username"
      assert Test.Xml.text(doc, "meta userID") == "test-user-id"
      assert Test.Xml.text(doc, "meta instanceID") =~ Extra.Regex.uuid()
    end

    test "xml contains patient fields", %{doc: doc} do
      Floki.find(doc, "case:nth-of-type(1) update *")
      |> Enum.map(fn {element, _attrs, [value]} -> {element, value} end)
      |> Map.new()
      |> assert_eq(
        %{
          "n0:full_name" => "index-case-full-name",
          "n0:field1" => "value1"
        },
        only: :right_keys
      )
    end

    test "xml contains lab results fields", %{doc: doc, data_from_index_case: data_from_index_case} do
      assert Test.Xml.attr(doc, "case:nth-of-type(2)", "xmlns:n0") == "http://commcarehq.org/case/transaction/v2"
      assert Test.Xml.attr(doc, "case:nth-of-type(2)", "case_id") =~ Extra.Regex.uuid()

      Floki.find(doc, "case:nth-of-type(2) create *")
      |> Enum.map(fn {element, _attrs, [value]} -> {element, value} end)
      |> Map.new()
      |> assert_eq(
        %{
          "n0:case_type" => "lab_result"
        },
        except: ~w(n0:case_id n0:owner_id)
      )

      Floki.find(doc, "case:nth-of-type(2) index *")
      |> Enum.map(fn {element, _attrs, [value]} -> {element, value} end)
      |> Map.new()
      |> assert_eq(%{
        "n0:parent" => data_from_index_case.index_case.case_id
      })

      Floki.find(doc, "case:nth-of-type(2) update *")
      |> Enum.map(fn {element, _attrs, [value]} -> {element, value} end)
      |> Map.new()
      |> assert_eq(
        %{
          "n0:field1" => "value1",
          "n0:field2" => "value2",
          "n0:accession_number" => "lab_result_accession_number"
        },
        except: ~w(n0:owner_id)
      )
    end
  end
end
