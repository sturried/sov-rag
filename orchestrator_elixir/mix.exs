defmodule SovNote.MixProject do
  use Mix.Project

  def project do
    [app: :sov_note, version: "0.1.0", elixir: "~> 1.15", deps: deps()]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SovNote.Application, []}
    ]
  end

  def deps do
    [
      {:plug_cowboy, "~> 2.6"},
      {:jason, "~> 1.4"},
      {:httpoison, "~> 2.0"}
    ]
  end
end
