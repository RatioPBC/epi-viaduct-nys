defmodule NYSETL.ReleaseTest do
  use NYSETL.DataCase, async: true

  alias NYSETL.Release
  alias NYSETL.Repo
  require Ecto.Query

  describe "seed" do
    test "inserts an ECLRS.County record for each county that CommCare provides in its county fixture" do
      NYSETL.Commcare.County.all_counties()
      |> Euclid.Enum.pluck("fips")
      |> Enum.sort()
      |> assert_eq(["1111", "1234", "5678", "905", "907", "9999"])

      assert_that(Release.seed(),
        changes: NYSETL.ECLRS.County |> Ecto.Query.order_by(asc: :id) |> Repo.all() |> Euclid.Enum.pluck(:id),
        from: [],
        to: [905, 907, 1111, 1234, 5678, 9999]
      )
    end
  end
end
