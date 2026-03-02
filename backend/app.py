from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from huggingface_hub import InferenceClient
from azure.core.credentials import AzureKeyCredential
from azure.search.documents import SearchClient
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

# Detectar si estamos en Azure o local
USE_LOCAL_EMBEDDINGS = os.getenv("USE_LOCAL_EMBEDDINGS", "false").lower() == "true"

if not HUGGINGFACE_API_KEY:
    raise ValueError("Falta HUGGINGFACE_API_KEY")
if not AZURE_SEARCH_ENDPOINT:
    raise ValueError("Falta AZURE_SEARCH_ENDPOINT")
if not AZURE_SEARCH_KEY:
    raise ValueError("Falta AZURE_SEARCH_KEY")


# ======================
# SETUP SEGÚN MODO
# ======================
if USE_LOCAL_EMBEDDINGS:
    logger.info("🏠 Modo LOCAL: Usando embeddings locales con LangChain")
    try:
        from langchain_huggingface import HuggingFaceEmbeddings
        from langchain_community.vectorstores.azuresearch import AzureSearch
        from langchain_core.prompts import PromptTemplate
        from langchain_core.runnables import RunnableParallel, RunnablePassthrough
        
        embeddings = HuggingFaceEmbeddings(
            model_name="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
            model_kwargs={"device": "cpu"}
        )
        
        vector_store = AzureSearch(
            azure_search_endpoint=AZURE_SEARCH_ENDPOINT,
            azure_search_key=AZURE_SEARCH_KEY,
            index_name=AZURE_SEARCH_INDEX,
            embedding_function=embeddings.embed_query
        )
        
        retriever = vector_store.as_retriever(search_type="hybrid", k=3)
        
    except ImportError as e:
        logger.error(f"Error importando dependencias locales: {e}")
        logger.info("Cambiando automáticamente a modo remoto")
        USE_LOCAL_EMBEDDINGS = False

if not USE_LOCAL_EMBEDDINGS:
    logger.info("☁️  Modo AZURE: Usando búsqueda simple de texto")
    search_client = SearchClient(
        endpoint=AZURE_SEARCH_ENDPOINT,
        index_name=AZURE_SEARCH_INDEX,
        credential=AzureKeyCredential(AZURE_SEARCH_KEY)
    )


# ======================
# LLM
# ======================
hf_client = InferenceClient(
    model="meta-llama/Llama-3.1-8B-Instruct",
    token=HUGGINGFACE_API_KEY
)


def call_Llama(prompt: str) -> str:
    """Llama al modelo LLAMA."""
    try:
        response = hf_client.chat_completion(
            messages=[{"role": "user", "content": prompt}],
            max_tokens=500,
            temperature=0.3
        )
        return response.choices[0].message["content"]
    except Exception as e:
        logger.error(f"Error llamando a Llama: {e}")
        return "Lo siento, hubo un error. Contacta por WhatsApp 221 316 0988."


def search_documents_local(query: str) -> str:
    """Búsqueda con embeddings locales (LangChain)"""
    docs = retriever.get_relevant_documents(query)
    return "\n\n".join(doc.page_content for doc in docs)


def search_documents_remote(query: str, top_k: int = 3) -> str:
    """Búsqueda simple de texto (sin embeddings)"""
    try:
        results = search_client.search(
            search_text=query,
            top=top_k,
            select=["content"]
        )
        
        docs = []
        for result in results:
            content = result.get("content") or result.get("page_content") or str(result)
            docs.append(content)
        
        return "\n\n".join(docs) if docs else "No se encontró información."
    except Exception as e:
        logger.error(f"Error en búsqueda: {e}")
        return "Error buscando información."


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


# ======================
# ENDPOINT /ask
# ======================
@app.post("/ask", response_model=Answer)
async def ask_question(q: Question):
    try:
        logger.info(f"Pregunta: {q.question}")
        
        # Búsqueda según modo
        if USE_LOCAL_EMBEDDINGS:
            context = search_documents_local(q.question)
        else:
            context = search_documents_remote(q.question)
        
        # Crear prompt
        full_prompt = PROMPT_TEMPLATE.format(
            context=context,
            question=q.question
        )
        
        # Llamar a Llama
        answer = call_Llama(full_prompt)
        
        return Answer(answer=answer)

    except Exception as e:
        logger.error(f"Error: {e}")
        raise HTTPException(500, str(e))


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "mode": "local" if USE_LOCAL_EMBEDDINGS else "remote",
        "azure_search": "connected",
        "index": AZURE_SEARCH_INDEX
    }


@app.get("/")
async def root():
    return {
        "service": "RAG Los Amigos Turismo",
        "mode": "🏠 LOCAL" if USE_LOCAL_EMBEDDINGS else "☁️ AZURE",
        "status": "running"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)