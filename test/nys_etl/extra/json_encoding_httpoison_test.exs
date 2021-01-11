defmodule NYSETL.Extra.JsonEncodingHttpoisonTest do
  use NYSETL.SimpleCase, async: true

  test "HTTPoison errors can be json encoded" do
    exception = %HTTPoison.Error{id: nil, reason: :timeout}

    Jason.encode(exception)
    |> assert_eq({:ok, "{\"id\":null,\"reason\":\"timeout\"}"})
  end

  test "HTTPoison errors can be json encoded to weird format so that oban can record them" do
    exception = %HTTPoison.Error{id: nil, reason: :timeout}

    Jason.encode_to_iodata!(exception)
    # ^ To make sure it doesn't throw an exception
  end
end
