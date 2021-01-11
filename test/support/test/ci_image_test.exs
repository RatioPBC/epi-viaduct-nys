defmodule CiImageTest do
  use NYSETL.DataCase, async: true

  # This becomes tautological when running in CI, and that's fine.º
  test "the version used by Gitlab's CI is the same we use when running the tests" do
    {:ok, ci_config} = YamlElixir.read_from_file(".gitlab-ci.yml")
    image = ci_config["test"]["image"]
    [_, image_version] = Regex.run(~r/elixir:([.0-9]+)/, image)
    assert image_version == System.version()
  end
end
