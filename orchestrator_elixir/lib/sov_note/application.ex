defmodule SovNote.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Web interface planned
    ]

    opts = [strategy: :one_for_one, name: SovNote.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
