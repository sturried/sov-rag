defmodule SovNote.InferenceRouter do
  require Logger

  # URLs
  @hpc_url "http://vllm-service.default.svc.cluster.local:8000/v1/chat/completions"
  @ollama_url "http://host.docker.internal:11434/api/chat"

  defp python_engine_url do
    base = System.get_env("PYTHON_ENGINE_URL", "http://ai-engine:8000")
    base <> "/analyze"
  end

  @doc """
  Entry point for processing a raw prompt.
  Determines whether to hit the Local/Ollama or the HPC Cluster (vLLM)
  based on the RUN_MODE environment variable.
  """
  def process_query(prompt) do
    # 1. Determine environment
    # "local" targets Ollama first, everything else targets HPC first.
    run_mode = System.get_env("RUN_MODE", "cluster")
    is_local? = String.contains?(run_mode, "local")

    {primary_url, label} =
      if is_local? do
        {@ollama_url, :local_inference}
      else
        {@hpc_url, :hpc_cluster}
      end

    Logger.info("[Inference] Mode: #{run_mode} | Primary Route: #{label}")

    payload =
      Jason.encode!(%{
        model: "llama3",
        messages: [%{role: "user", content: prompt}],
        stream: false
      })

    # 2. Execute primary request
    case perform_request(primary_url, payload, label) do
      {:ok, body} ->
        {:ok, label, body}

      {:error, _reason} ->
        handle_fallback(payload, is_local?)
    end
  end

  def analyze_and_interview(topic, text) do
    is_followup = String.contains?(text, "Last Question:")

    if is_followup do
      Logger.info("[Router] CHAT FOLLOW-UP detected for topic: #{topic}")

      case start_interview(topic, 0.0, "Continue Socratic dialogue.", text) do
        {:ok, source, response} = result ->
          Logger.info(
            "[Router] AI Response (Follow-up) from #{source}: #{response["message"]["content"]}"
          )

          result

        error ->
          error
      end
    else
      payload = Jason.encode!(%{topic: topic, text: text})
      Logger.info("[Router] INITIAL INGESTION for topic: #{topic}")

      case HTTPoison.post(python_engine_url(), payload, [{"Content-Type", "application/json"}]) do
        {:ok, %{status_code: 200, body: body}} ->
          analysis = Jason.decode!(body)
          Logger.info("[Router] Python Analysis: #{inspect(analysis)}")

          score = analysis["completeness_score"]
          wiki = analysis["wiki_summary"]

          case start_interview(topic, score, wiki, text) do
            {:ok, source, response} ->
              Logger.info(
                "[Router] AI Response (Initial) from #{source}: #{response["message"]["content"]}"
              )

              {:ok, source, response, score}

            error ->
              error
          end

        _error ->
          Logger.error(
            "[Router] Python Engine Unreachable at #{python_engine_url()}. Using fallback context."
          )

          start_interview(topic, 0.0, "Fallback context.", text)
      end
    end
  end

  def start_interview(topic, completeness_score, wiki_context, user_input) do
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

  defp handle_fallback(payload, was_local?) do
    {fallback_url, label} =
      if was_local? do
        {@hpc_url, :hpc_cluster}
      else
        {@ollama_url, :local_inference}
      end

    Logger.warning("[Inference] Primary route failed. Attempting fallback to #{label}...")

    case perform_request(fallback_url, payload, label) do
      {:ok, body} ->
        {:ok, label, body}

      {:error, reason} ->
        Logger.error("[Inference] TOTAL SYSTEM FAILURE: #{inspect(reason)}")
        {:error, :total_system_failure, "No inference engines reachable."}
    end
  end

  defp perform_request(url, payload, label) do
    # local/Ollama needs more time to load weights into Unified Memory/GPU
    timeout = if label == :local_inference, do: 15_000, else: 2_000

    case HTTPoison.post(url, payload, [{"Content-Type", "application/json"}],
           recv_timeout: timeout
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:error, reason} ->
        {:error, reason}

      %{status_code: status} ->
        {:error, "HTTP Error: #{status}"}
    end
  end
end
