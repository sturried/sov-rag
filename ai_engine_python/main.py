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

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Classic ML: Naive Bayes Setup ---
train_texts = ["kubernetes docker orchestration", "neural networks deep learning", "digital sovereignty privacy"]
train_labels = ["DevOps", "AI/ML", "Security"]
vectorizer = TfidfVectorizer()
X_train = vectorizer.fit_transform(train_texts)
classifier = MultinomialNB().fit(X_train, train_labels)

class Note(BaseModel):
    text: str
    topic: str


@app.post("/analyze")
def ingest_note(note: Note):
    wikipedia.set_user_agent("SovNoteStudyTool/1.0 (contact: student@example.com)")
    
    X_test = vectorizer.transform([note.text])
    category = classifier.predict(X_test)[0]

    try:
        search_results = wikipedia.search(note.topic)
        if not search_results:
            raise Exception("No results found")
            
        wiki_summary = wikipedia.summary(search_results[0], sentences=3, auto_suggest=False)
        
        note_emb = embedder.encode(note.text, convert_to_tensor=True)
        wiki_emb = embedder.encode(wiki_summary, convert_to_tensor=True)
        similarity = util.cos_sim(note_emb, wiki_emb).item()
        completeness_score = round(similarity * 100, 2)
        
    except Exception as e:
        print(f"Wiki API Failure: {e}")
        # If API fails, provide generic but accurate context
        wiki_summary = "Topic context unavailable via Wikipedia API. Reverting to internal LLM knowledge."
        completeness_score = 0.0
        
    return {
        "category": category,
        "completeness_score": completeness_score,
        "wiki_summary": wiki_summary,
        "knowledge_gaps": "High" if completeness_score < 50 else "Low"
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)