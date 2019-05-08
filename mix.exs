defmodule Rib.MixProject do
  use Mix.Project

  def project do
    [
      app: :rib,
      version: "0.1.0",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Rib.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:circuits_i2c, "~> 0.3"},
      {:circuits_spi, "~> 0.1"},
      {:circuits_gpio, "~> 0.1"},
      {:circuits_uart, "~> 1.3"},
      {:tortoise, "~> 0.9"}
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
