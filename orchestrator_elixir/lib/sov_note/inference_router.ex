defmodule SovNote.InferenceRouter do
  require Logger

  # Update these to use correct URL for HPC
  @hpc_url "http://vllm-service.default.svc.cluster.local:8000/v1/chat/completions"
  @ollama_url "http://host.docker.internal:11434/api/chat"
  @python_engine_url "http://ai-engine:8000/analyze"

  def process_query(prompt) do
    payload =
      Jason.encode!(%{
        model: "llama3",
        messages: [%{role: "user", content: prompt}],
        stream: false
      })

    # Try HPC
    case HTTPoison.post(@hpc_url, payload, [{"Content-Type", "application/json"}],
           recv_timeout: 3000
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, :hpc_cluster, Jason.decode!(body)}

      _error ->
        fallback_to_local_mac(payload)
    end
  end

  defp fallback_to_local_mac(payload) do
    Logger.warning("HPC Cluster unavailable. Failing over to Local Mac M4 (Ollama).")

    case HTTPoison.post(@ollama_url, payload, [{"Content-Type", "application/json"}],
           recv_timeout: 15000
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, :local_mac, Jason.decode!(body)}

      {:error, reason} ->
        Logger.error("Ollama connection failed: #{inspect(reason)}")
        {:error, :total_system_failure, "Check if Ollama is running with OLLAMA_HOST=0.0.0.0"}
    end
  end

  def analyze_and_interview(topic, text) do
    payload = Jason.encode!(%{topic: topic, text: text})

    Logger.info("Sending to Python: #{payload}")

    case HTTPoison.post(@python_engine_url, payload, [{"Content-Type", "application/json"}]) do
      {:ok, %{status_code: 200, body: body}} ->
        analysis = Jason.decode!(body)
        Logger.info("Received from Python: #{inspect(analysis)}")

        score = analysis["completeness_score"]
        wiki = analysis["wiki_summary"]

        case start_interview(topic, score, wiki) do
          {:ok, source, response} ->
            {:ok, source, response, score}

          error ->
            error
        end

      _error ->
        case start_interview(topic, 0.0, "Could not fetch wiki context.") do
          {:ok, source, response} ->
            {:ok, source, response, 0.0}

          error ->
            error
        end
    end
  end

  def start_interview(topic, completeness_score, wiki_context) do
    prompt = """
    SYSTEM: You are a strict but encouraging Socratic tutor.
    CONTEXT: The user is learning about "#{topic}".
    FACTUAL DATA FROM WIKIPEDIA: "#{wiki_context}"
    USER NOTE SCORE: #{completeness_score}%

    TASK:
    1. Compare the user's notes to the Wikipedia data.
    2. If the user's note is factually incorrect, gently correct them using the Wikipedia data.
    3. If the score is low, identify a major missing concept.
    4. Ask ONE challenging question to help them improve.

    Keep your response brief and focused on the topic.
    """

    process_query(prompt)
  end
end
