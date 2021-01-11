defmodule NYSETL.Engines.E4.PatientCaseDataTest do
  use NYSETL.SimpleCase, async: true

  alias NYSETL.Engines.E4.PatientCaseData

  describe "new" do
    test "creates a new PatientCaseData" do
      properties = %{"external_id" => "external-id-123", "owner_id" => "owner-id-123", "transfer_destination_county_id" => "xfer-county-123"}
      data = %{"case_id" => "case-id-123", "properties" => properties}

      assert PatientCaseData.new(data) == %PatientCaseData{
               case_id: "case-id-123",
               data: data,
               external_id: "external-id-123",
               owner_id: "owner-id-123",
               properties: properties,
               transfer_destination_county_id: "xfer-county-123"
             }
    end

    test "can optionally include county domain" do
      data = %{"case_id" => "case-id-123"}
      assert %PatientCaseData{case_id: "case-id-123", county_domain: "ny-foo-cdcms"} = PatientCaseData.new(data, "ny-foo-cdcms")
    end
  end
end
