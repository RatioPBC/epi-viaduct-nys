defmodule NYSETL.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use NYSETL.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate
  import Mox

  using do
    quote do
      alias NYSETL.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Euclid.Assertions
      import NYSETL.DataCase
      import NYSETL.Test.Extra.Assertions
      import NYSETL.Test.Macros
      import Mox

      alias Euclid.Extra
      alias NYSETL.Test.Factory

      require Logger

      setup :verify_on_exit!
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(NYSETL.Repo)

    if tags[:async] == false do
      Ecto.Adapters.SQL.Sandbox.mode(NYSETL.Repo, {:shared, self()})
    end

    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  def mock_county_list(_) do
    NYSETL.HTTPoisonMock
    |> stub(:get, fn url, _headers, _options ->
      assert String.ends_with?(url, "fixture_type=county_list")
      {:ok, %{status_code: 200, body: NYSETL.Test.Fixtures.county_list_response()}}
    end)

    :ok
  end
end
