# SovNote: Sovereign Retrieval-Augmented Generation (RAG)

A high-performance, decentralized study system built for **Digital Sovereignty**. SovNote allows users to categorize private notes, validate them against Wikipedia context, and engage in AI-driven study sessions—all on hardware you control.

## System Architecture

The system consists of two primary microservices and a native inference engine:

1. **Orchestrator (Elixir/Erlang):** A fault-tolerant gateway using a **Circuit Breaker** pattern to route requests between an HPC cluster and a local device.
2. **AI Engine (Python/FastAPI):** Handles NLP tasks using **Naive Bayes** for classification and **SentenceTransformers** (BERT) for semantic completeness scoring.
3. **Sovereign Node (Ollama):** Native inference using local memory.

---

## Installation & Setup

Note: I've tested this on a MacBook Pro M4

### 1. Native Mac Setup (The Sovereign Node)

To utilize the M4 GPU, Ollama must be configured to accept external traffic from the Docker bridge:

```bash
# Set host to allow Docker bridge communication
export OLLAMA_HOST=0.0.0.0
ollama serve

```

_In a separate terminal, ensure the model is pulled:_ `ollama pull llama3`

### 2. Microservice Deployment

Build and launch the containerized environments:

```bash
docker-compose up --build

```

---

## Testing & Debugging

### Phase 1: Semantic Validation (Python)

Test the NLP engine's ability to categorize and check for knowledge gaps:

```bash
curl -X POST http://localhost:8000/analyze \
     -H "Content-Type: application/json" \
     -d '{"topic": "Kubernetes", "text": "K8s is an orchestrator."}'

```

### Phase 2: Interactive AI Shell (Elixir)

Access the Elixir Orchestrator to test the failover logic and Socratic interviewing:

```bash
# Attach to the running container
docker exec -it [CONTAINER_ID] iex -S mix

# Run the Socratic Interview function
iex> SovNote.InferenceRouter.start_interview("Docker", 40.0, "Docker uses layers.")

```

---

## Troubleshooting

| Issue                    | Resolution                                                                          | DevOps Concept              |
| ------------------------ | ----------------------------------------------------------------------------------- | --------------------------- |
| **404 Not Found**        | Verified route names (e.g., `/analyze` vs `/ingest`) and Uvicorn port mapping.      | **API Contract Management** |
| **Total System Failure** | Bound Ollama to `0.0.0.0` to allow the Docker Bridge to exit the container network. | **Network Sandboxing**      |
| **Compile Error**        | Resolved function name mismatches at build-time using the strict Elixir compiler.   | **Static Analysis**         |
| **HPC Timeout**          | Observed the 3-second `recv_timeout` triggering a failover to the local M4 node.    | **Circuit Breaker Pattern** |

---

## "Study Session Mode"

To engage in a continuous chat loop during the demo, use the following recursive function in the IEx shell:

```elixir
chat = fn loop ->
  input = IO.gets("\nYOU > ") |> String.trim()
  {:ok, _source, response} = SovNote.InferenceRouter.process_query(input)
  IO.puts("\nAI > #{response["message"]["content"]}")
  loop.(loop)
end

chat.(chat)
```

### Examples

sebij@sebook ~ % curl -X POST http://localhost:8000/analyze \
 -H "Content-Type: application/json" \
 -d '{"topic": "Docker", "text": "Docker is a tool that uses containers."}'

Response:
{"category":"DevOps","completeness_score":0.0,"wiki_summary":"Topic not found.","knowledge_gaps":"High"}

sebij@sebook ~ % curl -X POST http://localhost:8000/analyze \
 -H "Content-Type: application/json" \
 -d '{"topic": "Kubernetes", "text": "Kubernetes is a system for automating deployment and scaling of containerized applications."}'

Response
{"category":"DevOps","completeness_score":74.13,"wiki_summary":"Kubernetes (), also known as K8s, is an open-source container orchestration system for automating software deployment, scaling, and management. Originally designed by Google, the project is now maintained by a worldwide community of contributors, and the trademark is held by the Cloud Native Computing Foundation.\nThe name Kubernetes comes from the Ancient Greek term κυβερνήτης, kubernḗtēs (helmsman, pilot), which is also the origin of the words cybernetics and (through Latin) governor.","knowledge_gaps":"Low}

Also see image.png for example output from Elixir IEX shell:
![Example for automatic switching between HPC and local LLM](https://github.com/sturried/sov-rag/blob/web-interface/z_doc_imgs/elixir_shell_test.png)

Logging features:
![Logging](https://github.com/sturried/sov-rag/blob/web-interface/z_doc_imgs/logging.png)

WebUI:
![Web UI Chat Interface](https://github.com/sturried/sov-rag/blob/web-interface/z_doc_imgs/web_ui_chat.png)

**Disclaimer:** Note that this ReadME has been partially written using LLMs.
