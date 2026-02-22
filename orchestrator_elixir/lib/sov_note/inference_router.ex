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
    is_followup = String.contains?(text, "Last Question:")

    if is_followup do
      Logger.info("CHAT FOLLOW-UP detected for topic: #{topic}")

      case start_interview(topic, 0.0, "Continue Socratic dialogue.", text) do
        {:ok, source, response} = result ->
          # LOG THE RESPONSE
          Logger.info("AI Response (Follow-up) from #{source}: #{response["message"]["content"]}")
          result

        error ->
          error
      end
    else
      payload = Jason.encode!(%{topic: topic, text: text})
      Logger.info("INITIAL INGESTION for topic: #{topic}")

      case HTTPoison.post(@python_engine_url, payload, [{"Content-Type", "application/json"}]) do
        {:ok, %{status_code: 200, body: body}} ->
          analysis = Jason.decode!(body)
          Logger.info("Python Analysis: #{inspect(analysis)}")

          score = analysis["completeness_score"]
          wiki = analysis["wiki_summary"]

          case start_interview(topic, score, wiki, text) do
            {:ok, source, response} ->
              # LOG THE RESPONSE
              Logger.info(
                "AI Response (Initial) from #{source}: #{response["message"]["content"]}"
              )

              {:ok, source, response, score}

            error ->
              error
          end

        _error ->
          Logger.error("Python Engine Unreachable. Using fallback context.")
          start_interview(topic, 0.0, "Fallback context.", text)
      end
    end
  end

  def start_interview(topic, completeness_score, wiki_context, user_input) do
    # Determine if this is a follow-up answer or a fresh note
    is_followup = String.contains?(user_input, "Last Question:")

    role_instruction =
      if is_followup do
        "The user is responding to your previous question. Evaluate their answer based on the reference data and continue the Socratic dialogue."
      else
        "The user has submitted a new note. Compare it to the reference data, provide a score, and ask an opening question to start the interview."
      end

    prompt = """
    SYSTEM: You are a strict but encouraging Socratic tutor.
    #{role_instruction}

    CONTEXT:
    - Topic: #{topic}
    - Reference Data: #{wiki_context}
    - Initial Note Accuracy: #{completeness_score}%

    USER INPUT (Notes or Answer):
    "#{user_input}"

    TASK:
    1. Acknowledge the user's input.
    2. If the user is factually incorrect based on the reference data, gently correct them.
    3. Ask ONE follow-up question to deepen their understanding.

    Keep your response brief and focused.
    """

    process_query(prompt)
  end
end
