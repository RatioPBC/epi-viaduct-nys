defmodule JsonEncodingHttpoison do
  @moduledoc """
  Implements the Jason.Encoder protocol for HTTPoison.Error structs.

  This is executed (at the least) in the context of errors interacting with external services, where the error may
  be reported to Sentry.
  """

  require Protocol

  Protocol.derive(Jason.Encoder, HTTPoison.Error, only: [:id, :reason])
end
