defmodule SovNote.WebRouter do
  use Plug.Router
  require Logger

  # Match incoming URL to defined route, parse application/json
  plug(:match)
  plug(Plug.Static, at: "/", from: :sov_note)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:dispatch)

  # Get index.html
  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Application.app_dir(:sov_note, "priv/static/index.html"))
  end

  # AI Interview Endpoint
  post "/chat" do
    topic = conn.body_params["topic"]
    text = conn.body_params["context"]

    case SovNote.InferenceRouter.analyze_and_interview(topic, text) do
      # Standard path after initial ingestion
      {:ok, source, response, score} ->
        send_json_success(conn, source, response, score)

      # Path for followup questions
      {:ok, source, response} ->
        send_json_success(conn, source, response, 0.0)

      {:error, _type, reason} ->
        Logger.error("Inference Error: #{inspect(reason)}")
        send_resp(conn, 500, Jason.encode!(%{error: "AI Timeout"}))

      other ->
        Logger.error("Unexpected response shape: #{inspect(other)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end

  # JSON structuring
  defp send_json_success(conn, source, response, score) do
    # Construct map and convert to JSON
    body =
      Jason.encode!(%{
        source: source,
        message: response["message"]["content"],
        score: score,
        stats: %{
          eval_count: response["eval_count"] || 0,
          load_duration: response["load_duration"] || 0,
          total_duration: response["total_duration"] || 0
        }
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  # Fallback incase invalid URl accessed
  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
