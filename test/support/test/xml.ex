defmodule NYSETL.Test.Xml do
  alias Euclid.Extra

  def attr(document, css_selector, attribute_name),
    do: document |> Floki.attribute(css_selector, attribute_name) |> Extra.List.only!()

  def text(document, css_selector),
    do: document |> Floki.find(css_selector |> String.downcase()) |> Floki.text()
end
