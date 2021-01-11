defmodule NYSETL.Engines.E4.CaseIdentifierTest do
  use NYSETL.SimpleCase, async: true

  alias NYSETL.Engines.E4.CaseIdentifier

  describe "describe" do
    test "produces a nice string for logs, debugging, etc." do
      %CaseIdentifier{case_id: "case-id-123", county_domain: "ny-domain"}
      |> CaseIdentifier.describe()
      |> assert_eq("<case_id:case-id-123 county_domain:ny-domain>")
    end
  end

  describe "new" do
    test "creates a new CaseIdentifier with all fields" do
      CaseIdentifier.new(
        case_id: "case-id-123",
        county_domain: "ny-domain",
        county_id: "county-fips",
        external_id: "external-id"
      )
      |> assert_eq(%CaseIdentifier{
        case_id: "case-id-123",
        county_domain: "ny-domain",
        county_id: "county-fips",
        external_id: "external-id"
      })
    end

    test "creates a new CaseIdentifier with empty fields set to nil" do
      CaseIdentifier.new(
        case_id: "case-id-123",
        county_domain: "",
        county_id: nil,
        external_id: "   "
      )
      |> assert_eq(%CaseIdentifier{
        case_id: "case-id-123",
        county_domain: nil,
        county_id: nil,
        external_id: nil
      })
    end
  end
end
