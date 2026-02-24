from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import wikipedia
from sentence_transformers import SentenceTransformer, util
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.naive_bayes import MultinomialNB
import uvicorn

app = FastAPI()
embedder = SentenceTransformer('all-MiniLM-L6-v2')

# Middleware to allow docker intercommunication
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Classic ML: Naive Bayes Setup ---
train_texts = ["kubernetes docker orchestration", "neural networks deep learning", "digital sovereignty privacy"]
train_labels = ["DevOps", "AI/ML", "Security"]

# Term Frequency-Inverse Document Frequency
vectorizer = TfidfVectorizer()
X_train = vectorizer.fit_transform(train_texts)
classifier = MultinomialNB().fit(X_train, train_labels)

class Note(BaseModel):
    text: str
    topic: str


@app.post("/analyze")
def ingest_note(note: Note):
    wikipedia.set_user_agent("SovNoteStudyTool/1.0 (contact: student@sovnote.com)")
    
    # --- Classifier Debugging ---
    X_test = vectorizer.transform([note.text])
    # Get probabilities for each category
    probs = classifier.predict_proba(X_test)[0]
    category = classifier.predict(X_test)[0]
    confidence = max(probs)

    print(f"--- DEBUG START ---")
    print(f"INPUT TOPIC: {note.topic}")
    print(f"INPUT TEXT: {note.text[:100]}...")
    print(f"CLASSIFICATION: {category} (Confidence: {round(confidence, 4)})")

    try:
        # Search for the topic - Logging the search results specifically
        search_results = wikipedia.search(note.topic)
        print(f"WIKI SEARCH RESULTS: {search_results}")

        if not search_results:
            raise Exception(f"No results found for topic: {note.topic}")
        
        # First 3 sentences summarized, autosuggest=False for stability and precision
        wiki_summary = wikipedia.summary(search_results[0], sentences=3, auto_suggest=False)
        print(f"WIKI SUMMARY FETCHED: {wiki_summary[:100]}...")
        
        # Note and wiki embeddings
        note_emb = embedder.encode(note.text, convert_to_tensor=True)
        wiki_emb = embedder.encode(wiki_summary, convert_to_tensor=True)

        # cosine angle calculation between note and wiki vectors
        similarity = util.cos_sim(note_emb, wiki_emb).item()
        completeness_score = round(similarity * 100, 2)
        print(f"SIMILARITY SCORE: {completeness_score}%")
        
    except Exception as e:
        print(f"Wiki API Failure: {type(e).__name__} - {e}")
        # If API fails, provide generic but accurate context
        wiki_summary = "Topic context unavailable via Wikipedia API. Reverting to internal LLM knowledge."
        completeness_score = 0.0
    
    print(f"--- DEBUG END ---")
        
    return {
        "category": category,
        "completeness_score": completeness_score,
        "wiki_summary": wiki_summary,
        "knowledge_gaps": "High" if completeness_score < 50 else "Low"
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)