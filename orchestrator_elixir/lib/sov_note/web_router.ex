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
        body =
          Jason.encode!(%{
            source: source,
            message: response["message"]["content"],
            score: score,
            stats: %{
              eval_count: response["eval_count"],
              load_duration: response["load_duration"],
              total_duration: response["total_duration"]
            }
          })

        send_resp(conn, 200, body)

      error ->
        Logger.error("Inference failed: #{inspect(error)}")
        send_resp(conn, 500, Jason.encode!(%{error: "Internal Server Error"}))
    end
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
