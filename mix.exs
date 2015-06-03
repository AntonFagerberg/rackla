defmodule Rackla.Mixfile do
  use Mix.Project

  def project do
    [
      app: :rackla,
      version: "0.1.0",
      elixir: "~> 1.0",
      deps: deps,
      escript: escript,
      package: package,
      description: "Rackla is library used for building API-gateways."
    ]
  end

  # Configuration for the OTP application
  def application do
    [
      applications: [:logger, :cowboy, :plug, :hackney],
      mod: {Rackla.Application, []}
    ]
  end

  defp deps do
    [
      {:poison, "~> 1.4"},
      {:hackney, "~> 1.1"},
      {:cowboy, "~> 1.0"},
      {:plug, "~> 0.12"},
      {:earmark, "~> 0.1", only: :dev},
      {:ex_doc, "~> 0.7", only: :dev}
    ]
  end
  
  defp package do
    [
      contributors: ["Anton Fagerberg"],
      licenses: ["Apache 2"],
      links: %{"GitHub" => "https://github.com/AntonFagerberg/rackla"},
      files: [
        "lib/rackla/rackla.ex",
        "lib/rackla/request.ex",
        "lib/rackla/response.ex",
        "mix.ex",
        "README.md",
        "LICENSE"
      ]
    ]
  end
  
  def escript do
    [main_module: Rackla.Application]
  end
end
