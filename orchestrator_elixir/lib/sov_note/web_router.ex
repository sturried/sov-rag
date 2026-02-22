defmodule SovNote.WebRouter do
  use Plug.Router

  plug(:match)
  plug(Plug.Static, at: "/", from: :sov_note)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:dispatch)

  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Application.app_dir(:sov_note, "priv/static/index.html"))
  end

  # The AI Interview Endpoint
  post "/chat" do
    topic = conn.body_params["topic"]
    text = conn.body_params["context"]

    case SovNote.InferenceRouter.analyze_and_interview(topic, text) do
      {:ok, source, response, score} ->
        send_json_success(conn, source, response, score)

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

  # Helper function to keep code clean
  defp send_json_success(conn, source, response, score) do
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

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
