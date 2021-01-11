defmodule NYSETL.ECLRS.FileTest do
  use NYSETL.DataCase, async: true

  alias NYSETL.ECLRS

  describe "changeset" do
    setup do
      attrs = %{
        filename: "path/to/file",
        processing_started_at: DateTime.utc_now(),
        processing_completed_at: DateTime.utc_now(),
        statistics: %{}
      }

      [attrs: attrs]
    end

    test "validates filename presence", context do
      {:error, changeset} =
        %ECLRS.File{}
        |> ECLRS.File.changeset(Map.drop(context.attrs, [:filename]))
        |> Repo.insert()

      assert %{filename: ["can't be blank"]} = errors_on(changeset)
    end
  end
end
