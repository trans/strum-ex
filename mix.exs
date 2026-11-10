defmodule Strum.MixProject do
  use Mix.Project

  def project do
    [
      app: :strum,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # the fixtures' generator is a script, not a test
      test_ignore_filters: [&String.starts_with?(&1, "test/fixtures/")],
      description:
        "Structured Markdown: convert between structured data and Markdown documents " <>
          "of sections with ids, metadata and content. A port of the Crystal strum.",
      package: [licenses: ["MIT"], maintainers: ["Thomas Sawyer"]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:yamerl, "~> 0.10"}
    ]
  end
end
