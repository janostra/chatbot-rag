from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from huggingface_hub import InferenceClient
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores.azuresearch import AzureSearch
from langchain_core.prompts import PromptTemplate
from langchain_core.runnables import RunnableParallel, RunnablePassthrough
from dotenv import load_dotenv
import os
import logging

# ======================
# LOAD ENV
# ======================
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
load_dotenv(os.path.join(BASE_DIR, ".env"))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="RAG Service - Los Amigos Turismo")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class Question(BaseModel):
    question: str

class Answer(BaseModel):
    answer: str


# ======================
# ENV VARS
# ======================
HUGGINGFACE_API_KEY = os.getenv("HUGGINGFACE_API_KEY")
AZURE_SEARCH_ENDPOINT = os.getenv("AZURE_SEARCH_ENDPOINT")
AZURE_SEARCH_KEY = os.getenv("AZURE_SEARCH_KEY")
AZURE_SEARCH_INDEX = os.getenv("AZURE_SEARCH_INDEX", "travel-docs")

if not HUGGINGFACE_API_KEY:
    raise ValueError("Falta HUGGINGFACE_API_KEY")
if not AZURE_SEARCH_ENDPOINT:
    raise ValueError("Falta AZURE_SEARCH_ENDPOINT")
if not AZURE_SEARCH_KEY:
    raise ValueError("Falta AZURE_SEARCH_KEY")


# ======================
# EMBEDDINGS
# ======================
embeddings = HuggingFaceEmbeddings(
    model_name="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
    model_kwargs={"device": "cpu"}
)


# ======================
# VECTOR STORE
# ======================
vector_store = AzureSearch(
    azure_search_endpoint=AZURE_SEARCH_ENDPOINT,
    azure_search_key=AZURE_SEARCH_KEY,
    index_name=AZURE_SEARCH_INDEX,
    embedding_function=embeddings.embed_query
)

retriever = vector_store.as_retriever(
    search_type="hybrid",
    k=3
)


# ======================
# LLM (HuggingFace InferenceClient)
# ======================
client = InferenceClient(
    model="mistralai/Mistral-7B-Instruct-v0.2",
    token=HUGGINGFACE_API_KEY
)


def call_mistral(prompt: str) -> str:
    """Llama al modelo Mistral por chat."""
    response = client.chat_completion(
        messages=[{"role": "user", "content": prompt}],
        max_tokens=500,
        temperature=0.3
    )
    return response.choices[0].message["content"]


# ======================
# PROMPT TEMPLATE
# ======================
PROMPT_TEMPLATE = """
Eres un asistente virtual de "Los Amigos Turismo".

Contexto:
{context}

Pregunta:
{question}

Instrucciones:
- Responde en español
- Sé breve y profesional
- Si no hay información suficiente, sugiere contactar por WhatsApp 221 316 0988

Respuesta:
"""

prompt = PromptTemplate(
    input_variables=["context", "question"],
    template=PROMPT_TEMPLATE
)

def format_docs(docs):
    return "\n\n".join(doc.page_content for doc in docs)


# ======================
# RAG CHAIN — SOLO HASTA ARMAR EL PROMPT
# ======================
prompt_chain = RunnableParallel({
        "context": retriever | format_docs,
        "question": RunnablePassthrough()
    }) | prompt


# ======================
# ENDPOINT /ask
# ======================
@app.post("/ask", response_model=Answer)
async def ask_question(q: Question):
    try:
        
        prompt_value = prompt_chain.invoke(q.question)

        full_prompt = prompt_value.to_string()

        answer = call_mistral(full_prompt)

        return Answer(answer=answer)

    except Exception as e:
        logger.error(f"Error: {e}")
        raise HTTPException(500, str(e))


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/")
async def root():
    return {"service": "RAG Los Amigos Turismo"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
