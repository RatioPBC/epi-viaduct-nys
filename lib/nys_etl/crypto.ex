defmodule NYSETL.Crypto do
  def sha256(binary) do
    :crypto.hash(:sha256, binary) |> Base.encode64()
  end
end
