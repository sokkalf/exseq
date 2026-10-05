defmodule Exseq.MixProject do
  use Mix.Project

  def project do
    [
      app: :exseq,
      version: "0.2.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      source_url: "https://github.com/sokkalf/exseq",
      docs: docs(),
      deps: deps()
    ]
  end

  def package do
    [
      name: "exseq",
      description: "Exseq is an Elixir library for logging to Seq",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/sokkalf/exseq"
      },
      maintainers: ["sokkalf"],
      files: ["lib", "mix.exs", "README.md"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExSeq.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:httpoison, "~> 2.2"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:bypass, "~> 2.1", only: :test}
    ]
  end
end
