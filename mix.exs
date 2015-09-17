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
      {:poison, "~> 1.5.0"},
      {:hackney, "~> 1.3.0"},
      {:cowboy, "~> 1.0.0", optional: true},
      {:plug, "~> 1.0.0"},
      {:earmark, "~> 0.1.17", only: :docs},
      {:ex_doc, "~> 0.9.0", only: :docs}
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
        "mix.exs",
        "README.md",
        "LICENSE"
      ]
    ]
  end
  
  def escript do
    [main_module: Rackla.Application]
  end
end
