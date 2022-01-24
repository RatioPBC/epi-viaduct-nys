defmodule NYSETL.Engines.E4.XmlBuilder do
  import XmlBuilder

  def build(%{index_case: index_case, lab_results: lab_results}) do
    envelope_id = Ecto.UUID.generate()

    element(
      :data,
      %{
        name: "Register a New Case",
        uiVersion: "1",
        version: "3",
        xmlns: "http://geometer.io/viaduct-nys",
        "xmlns:jrm": "http://dev.commcarehq.org/jr/xforms"
      },
      [
        element(
          :"n0:case",
          %{
            case_id: index_case.case_id,
            date_modified: index_case.date_modified,
            user_id: Application.get_env(:nys_etl, :commcare_user_id),
            "xmlns:n0": "http://commcarehq.org/case/transaction/v2"
          },
          [
            element(:"n0:create", [
              element(:"n0:case_name", index_case.data["full_name"]),
              element(:"n0:case_type", "patient"),
              element(:"n0:owner_id", index_case.owner_id)
            ]),
            element(:"n0:update", build_fields(index_case.data))
          ]
        ),
        lab_results |> Enum.map(fn l -> lab_result(index_case.case_id, l) end),
        meta(index_case.date_modified, envelope_id)
      ]
      |> Enum.filter(&Euclid.Term.present?/1)
    )
    |> document()
    |> generate()
  end

  defp build_fields(map) do
    map
    |> Enum.filter(fn {_field_name, value} -> Euclid.Term.present?(value) end)
    |> Enum.map(fn {field_name, value} -> element(:"n0:#{field_name}", value) end)
    |> Enum.sort()
  end

  defp lab_result(parent_case_id, lab_result) do
    element(:"n0:case", %{case_id: lab_result.case_id, "xmlns:n0": "http://commcarehq.org/case/transaction/v2"}, [
      element(:"n0:create", [
        element(:"n0:case_type", "lab_result"),
        element(:"n0:owner_id", lab_result.owner_id)
      ]),
      element(:"n0:update", build_fields(lab_result.data)),
      element(:"n0:index", [
        element(:"n0:parent", %{case_type: "patient", relationship: "extension"}, parent_case_id)
      ])
    ])
  end

  defp meta(extracted_at, envelope_id) do
    element(:"n1:meta", %{"xmlns:n1": "http://openrosa.org/jr/xforms"}, [
      element(:"n1:deviceID", "Formplayer"),
      element(:"n1:timeStart", extracted_at),
      element(:"n1:timeEnd", extracted_at),
      element(:"n1:username", Application.get_env(:nys_etl, :commcare_username)),
      element(:"n1:userID", Application.get_env(:nys_etl, :commcare_user_id)),
      element(:"n1:instanceID", envelope_id)
    ])
  end
end
