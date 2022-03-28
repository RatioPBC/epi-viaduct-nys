defmodule NYSETL.Engines.E5Test do
  use NYSETL.DataCase, async: false

  alias NYSETL.Commcare

  setup [:midsomer_county, :midsomer_patient_case]

  test "create person and index case", %{midsomer_county: midsomer, midsomer_patient_case: patient_case} do
    assert {:error, :not_found} = Commcare.get_index_case(case_id: patient_case["case_id"], county_id: midsomer.fips)

    start_supervised!(NYSETL.Engines.E5.Supervisor)
    ref = Broadway.test_message(:"broadway.engines.e5", case: patient_case, county: midsomer)
    assert_receive {:ack, ^ref, [%{data: [case: ^patient_case, county: ^midsomer]}], []}

    assert {:ok, _} = Commcare.get_index_case(case_id: patient_case["case_id"], county_id: midsomer.fips)
  end
end
