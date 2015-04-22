defmodule CrocodilePear.Mixfile do
  use Mix.Project

  def project do
    [
      app: :crocodile_pear,
      version: "0.0.1",
      elixir: "~> 1.0",
      deps: deps,
      escript: escript,
      package: package,
      description: "CrocodilePear is library used for building API-gateways."
    ]
  end

  # Configuration for the OTP application
  def application do
    [
      applications: [:logger, :httpoison, :cowboy, :plug],
      mod: {CrocodilePear.Application, []}
    ]
  end

  defp deps do
    [
      {:poison, "~> 1.3"},
      {:httpoison, "~> 0.6"},
      {:cowboy, "~> 1.0", only: :dev},
      {:plug, "~> 0.10", only: :dev},
      {:earmark, "~> 0.1", only: :dev},
      {:ex_doc, "~> 0.7", only: :dev}
    ]
  end
  
  defp package do
    [
      contributors: ["Anton Fagerberg"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/AntonFagerberg/crocodile_pear"},
      files: [
        "lib/crocodile_pear/crocodile_pear.ex",
        "mix.ex",
        "README.md",
        "LICENSE"
      ]
    ]
  end
  
  def escript do
    [main_module: CrocodilePear.Application]
  end
end
