defmodule SovNote.Application do
  use Application
  require Logger

  # Implementation of standard callback
  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT") || "4000")

    # Start cowboy webserver on port 4000
    children = [
      {Plug.Cowboy, scheme: :http, plug: SovNote.WebRouter, options: [port: 4000]}
    ]

    Logger.info("Orchestrator booting up...")
    Logger.info("Listening on port #{port} with strategy :one_for_one")

    # Incase web server crashes, supervisor restarts it
    opts = [strategy: :one_for_one, name: SovNote.Supervisor]

    # Start supervisor
    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("Supervisor started successfully (PID: #{inspect(pid)})")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start Supervisor: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
