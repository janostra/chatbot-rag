# loaddocs.py
import os
from langchain_community.document_loaders import TextLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.vectorstores import Chroma
from langchain_openai import OpenAIEmbeddings
from dotenv import load_dotenv

load_dotenv()

# Cargar el archivo de texto
loader = TextLoader("data/info_empresa.txt", encoding="utf-8")
documents = loader.load()
print("📄 Documento cargado:")
print(documents[0].page_content)


# Dividir el texto en chunks
splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
chunks = splitter.split_documents(documents)

# Crear los embeddings y almacenar en Chroma
embeddings = OpenAIEmbeddings(openai_api_key=os.getenv("OPENAI_API_KEY"))
db = Chroma.from_documents(chunks, embedding=embeddings, persist_directory="chroma_db")
db.persist()

print("📚 Documentos cargados y almacenados en Chroma.")
