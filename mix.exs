defmodule Rackla.Mixfile do
  use Mix.Project

  def project do
    [
      app: :rackla,
      version: "1.2.1",
      elixir: "~> 1.0",
      deps: deps,
      package: package,
      description: "Rackla is library for building API-gateways."
    ]
  end

  # Configuration for the OTP application
  def application do
    [applications: applications(Mix.env)]
  end

  defp applications(:dev), do: applications(:all) ++ [:remix]
  defp applications(_all), do: [:logger, :plug, :hackney, :poison]

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
        "lib/proxy.ex",
        "lib/rackla.ex",
        "lib/request.ex",
        "lib/response.ex",
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md"
      ]
    ]
  end
end
