defmodule Beamlens.MixProject do
  use Mix.Project

  def project do
    [
      app: :beamlens,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A minimal AI agent that monitors BEAM VM health",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Beamlens.Application, []}
    ]
  end

  defp deps do
    [
      {:strider, github: "bradleygolden/strider"},
      {:jason, "~> 1.4"},
      # BAML for type-safe LLM functions
      {:baml_elixir, "~> 1.0.0-pre.23"},
      # Required for strider compilation (sandbox store) - can be removed when strider fixes optional deps
      {:ecto_sql, "~> 3.0", runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{}
    ]
  end
end
