defmodule Rackla.Mixfile do
  use Mix.Project

  def project do
    [
      app: :rackla,
      version: "1.1.0",
      elixir: "~> 1.0",
      deps: deps,
      escript: escript,
      package: package,
      description: "Rackla is library for building API-gateways."
    ]
  end

  # Configuration for the OTP application
  def application do
    [
      applications: applications(Mix.env),
      mod: {Rackla.Application, []}
    ]
  end

  defp applications(:dev), do: applications(:all) ++ [:remix]
  defp applications(_all), do: [:logger, :cowboy, :plug, :hackney]

  defp deps do
    [
      {:poison, "~> 2.2"},
      {:hackney, "~> 1.6"},
      {:cowboy, "~> 1.0", optional: true},
      {:plug, "~> 1.2"},
      {:earmark, "~> 1.0", only: :dev},
      {:ex_doc, "~> 0.13", only: :dev},
      {:remix, "~> 0.0", only: :dev},
      {:dialyxir, "~> 0.3", only: :dev}
    ]
  end

  defp package do
    [
      maintainers: ["Anton Fagerberg"],
      licenses: ["Apache 2"],
      links: %{"GitHub" => "https://github.com/AntonFagerberg/rackla"},
      files: [
        "lib/rackla/rackla.ex",
        "lib/rackla/request.ex",
        "lib/rackla/response.ex",
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md"
      ]
    ]
  end

  def escript do
    [main_module: Rackla.Application]
  end
end
