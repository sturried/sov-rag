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
    X_test = vectorizer.transform([note.text])
    category = classifier.predict(X_test)[0]

    try:
        wiki_summary = wikipedia.summary(note.topic, sentences=3)
        
        # Create Vector Embeddings
        note_emb = embedder.encode(note.text, convert_to_tensor=True)
        wiki_emb = embedder.encode(wiki_summary, convert_to_tensor=True)
        
        # Calculate Cosine Similarity
        similarity = util.cos_sim(note_emb, wiki_emb).item()
        completeness_score = round(similarity * 100, 2)
    except wikipedia.exceptions.DisambiguationError:
        wiki_summary = "Topic too broad. Please refine."
        completeness_score = 0.0
    except Exception:
        wiki_summary = "Topic not found."
        completeness_score = 0.0
        
    return {
        "category": category,
        "completeness_score": completeness_score,
        "wiki_summary": wiki_summary,
        "knowledge_gaps": "High" if completeness_score < 50 else "Low"
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)