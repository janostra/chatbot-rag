import logging
import os
import json
import uuid
import azure.functions as func
from azure.search.documents import SearchClient
from azure.core.credentials import AzureKeyCredential
from langchain_text_splitters import RecursiveCharacterTextSplitter
from datetime import datetime, timezone
from pymongo import MongoClient


def main(myBlob: func.InputStream):
    logging.info(f"🔔 Azure Function triggered: {myBlob.name}")
    logging.info(f"📦 Blob size: {myBlob.length} bytes")

    search_endpoint = os.environ.get("AZURE_SEARCH_ENDPOINT")
    search_key      = os.environ.get("AZURE_SEARCH_KEY")
    index_name      = os.environ.get("AZURE_SEARCH_INDEX", "travel-docs")
    mongo_uri       = os.environ.get("CosmosDBConnection")

    if not search_endpoint or not search_key:
        logging.error("❌ Faltan AZURE_SEARCH_ENDPOINT o AZURE_SEARCH_KEY")
        raise EnvironmentError("Variables de entorno de Azure Search no configuradas")

    filename    = myBlob.name.split("/")[-1]
    uuid_parts = filename.split("-")
    document_id = "-".join(uuid_parts[:5])
    uploaded_at = datetime.now(timezone.utc).isoformat()

    try:
        raw = myBlob.read()
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError:
            content = raw.decode("latin-1")

        logging.info(f"✅ Contenido leído: {len(content)} caracteres")

        if not content.strip():
            logging.warning("⚠️ El archivo está vacío, se omite la indexación")
            return

        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=500,
            chunk_overlap=50,
            length_function=len,
        )
        chunks = text_splitter.split_text(content)
        logging.info(f"✅ Creados {len(chunks)} chunks")

        search_client = SearchClient(
            endpoint=search_endpoint,
            index_name=index_name,
            credential=AzureKeyCredential(search_key),
        )

        search_docs = []
        for i, chunk in enumerate(chunks):
            search_docs.append({
                "id":      f"{document_id}-chunk-{i}",
                "content": chunk,
                "metadata": json.dumps({
                    "source":       filename,
                    "chunk_id":     i,
                    "total_chunks": len(chunks),
                    "type":         "uploaded_document",
                    "uploaded_at":  uploaded_at,
                }),
            })

        total_uploaded = 0
        for start in range(0, len(search_docs), 100):
            batch = search_docs[start:start + 100]
            result = search_client.upload_documents(documents=batch)
            total_uploaded += sum(1 for r in result if r.succeeded)

        logging.info(f"✅ {total_uploaded}/{len(search_docs)} chunks subidos a Azure AI Search")

        # Actualizar Cosmos DB directamente con pymongo
        if mongo_uri:
            try:
                client = MongoClient(mongo_uri, serverSelectionTimeoutMS=5000)
                db = client["chatbot"]
                db["documents"].update_one(
                    {"documentId": document_id},
                    {"$set": {
                        "indexed":     True,
                        "indexedAt":   uploaded_at,
                        "totalChunks": len(chunks),
                        "status":      "indexed",
                    }},
                    upsert=False
                )
                client.close()
                logging.info(f"✅ Cosmos DB actualizado: documentId={document_id}")
            except Exception as e:
                logging.warning(f"⚠️ No se pudo actualizar Cosmos DB: {e}")
        else:
            logging.warning("⚠️ CosmosDBConnection no configurada, se omite actualización")

        logging.info("=" * 60)
        logging.info(f"✅ INDEXACIÓN COMPLETADA: {filename}")
        logging.info(f"   Chunks creados:  {len(chunks)}")
        logging.info(f"   Chunks subidos:  {total_uploaded}")
        logging.info("=" * 60)

    except Exception as e:
        logging.error(f"❌ ERROR en indexación: {str(e)}")
        logging.exception(e)

        if mongo_uri:
            try:
                client = MongoClient(mongo_uri, serverSelectionTimeoutMS=5000)
                db = client["chatbot"]
                db["documents"].update_one(
                    {"documentId": document_id},
                    {"$set": {"indexed": False, "error": str(e), "status": "error"}},
                    upsert=False
                )
                client.close()
            except Exception:
                pass
        raise
