defmodule Exseq.MixProject do
  use Mix.Project

  def project do
    [
      app: :exseq,
      version: "0.1.2",
      elixir: "~> 1.17",
      package: package(),
      source_url: "https://github.com/sokkalf/exseq",
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

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:httpoison, "~> 2.2"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
