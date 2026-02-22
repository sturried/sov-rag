defmodule SovNote.MixProject do
  use Mix.Project
  def project do
    [app: :sov_note, version: "0.1.0", elixir: "~> 1.15", deps: deps()]
  end
  defp deps do
    [{:httpoison, "~> 2.1"}, {:jason, "~> 1.4"}]
  end
end