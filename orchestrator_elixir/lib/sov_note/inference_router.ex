defmodule SovNote.InferenceRouter do
  require Logger

  # Update these to use correct URL for HPC
  @hpc_url "http://vllm-service.default.svc.cluster.local:8000/v1/chat/completions"
  @ollama_url "http://host.docker.internal:11434/api/chat"

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

  def start_interview(topic, score, context) do
    prompt =
      "I am a study assistant. Topic: #{topic}. Score: #{score}. Wiki: #{context}. Ask one question."

    process_query(prompt)
  end
end
