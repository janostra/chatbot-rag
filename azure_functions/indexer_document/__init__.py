"""
Azure Function: Auto-indexación de documentos en Azure AI Search
Se ejecuta automáticamente cuando se sube un archivo a Blob Storage.

NOTA: No usamos HuggingFaceEmbeddings aquí para evitar dependencias
pesadas (torch ~2GB) incompatibles con el plan Consumption.
En su lugar indexamos el texto directamente en Azure AI Search con
búsqueda de texto simple. Los embeddings los genera el backend Python
(app.py) cuando el usuario hace una pregunta.
"""

import logging
import os
import json
import uuid
import azure.functions as func
from azure.search.documents import SearchClient
from azure.core.credentials import AzureKeyCredential
from langchain_text_splitters import RecursiveCharacterTextSplitter
from datetime import datetime, timezone


def main(myBlob: func.InputStream, outputDocument: func.Out[func.Document]):
    """
    Trigger: Se ejecuta cuando se sube un archivo a Blob Storage
    Input:   Archivo del blob
    Output:  Actualiza documento en Cosmos DB
    """

    logging.info(f"🔔 Azure Function triggered: {myBlob.name}")
    logging.info(f"📦 Blob size: {myBlob.length} bytes")

    # ── Leer variables de entorno ────────────────────────────────────────────
    search_endpoint = os.environ.get("AZURE_SEARCH_ENDPOINT")
    search_key      = os.environ.get("AZURE_SEARCH_KEY")
    index_name      = os.environ.get("AZURE_SEARCH_INDEX", "travel-docs")

    if not search_endpoint or not search_key:
        logging.error("❌ Faltan AZURE_SEARCH_ENDPOINT o AZURE_SEARCH_KEY")
        raise EnvironmentError("Variables de entorno de Azure Search no configuradas")

    try:
        # ── 1. Leer contenido del blob ───────────────────────────────────────
        raw = myBlob.read()

        # Intentar decodificar como UTF-8, con fallback a latin-1
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError:
            content = raw.decode("latin-1")

        logging.info(f"✅ Contenido leído: {len(content)} caracteres")

        if not content.strip():
            logging.warning("⚠️  El archivo está vacío, se omite la indexación")
            return

        # ── 2. Dividir en chunks ─────────────────────────────────────────────
        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=500,
            chunk_overlap=50,
            length_function=len,
        )
        chunks = text_splitter.split_text(content)
        logging.info(f"✅ Creados {len(chunks)} chunks")

        # ── 3. Extraer nombre de archivo ─────────────────────────────────────
        # myBlob.name tiene formato "documents/uuid-filename.txt"
        filename     = myBlob.name.split("/")[-1]
        document_id  = filename.split("-")[0] if "-" in filename else str(uuid.uuid4())
        uploaded_at  = datetime.now(timezone.utc).isoformat()

        # ── 4. Crear cliente de Azure AI Search ─────────────────────────────
        search_client = SearchClient(
            endpoint=search_endpoint,
            index_name=index_name,
            credential=AzureKeyCredential(search_key),
        )

        # ── 5. Preparar documentos para Azure AI Search ──────────────────────
        #
        # El índice "travel-docs" fue creado por index_documents.py con los campos:
        #   id (String, key), content (String, searchable), metadata (String)
        #
        # Enviamos los chunks como documentos de texto plano.
        # La búsqueda semántica/vectorial la hace el backend cuando el usuario pregunta.

        search_docs = []
        for i, chunk in enumerate(chunks):
            doc_id = f"{document_id}-chunk-{i}"
            search_docs.append({
                "id":       doc_id,
                "content":  chunk,
                "metadata": json.dumps({
                    "source":       filename,
                    "chunk_id":     i,
                    "total_chunks": len(chunks),
                    "type":         "uploaded_document",
                    "uploaded_at":  uploaded_at,
                }),
            })

        # ── 6. Subir en lotes de 100 (límite de la API) ──────────────────────
        batch_size = 100
        total_uploaded = 0

        for start in range(0, len(search_docs), batch_size):
            batch = search_docs[start : start + batch_size]
            result = search_client.upload_documents(documents=batch)

            succeeded = sum(1 for r in result if r.succeeded)
            total_uploaded += succeeded

            failed = len(batch) - succeeded
            if failed:
                logging.warning(f"⚠️  {failed} documentos fallaron en este lote")

        logging.info(f"✅ {total_uploaded}/{len(search_docs)} chunks subidos a Azure AI Search")

        # ── 7. Actualizar Cosmos DB ───────────────────────────────────────────
        cosmos_doc = {
            "id":          document_id,
            "documentId":  document_id,
            "filename":    filename,
            "indexed":     True,
            "indexedAt":   uploaded_at,
            "totalChunks": len(chunks),
        }
        outputDocument.set(func.Document.from_dict(cosmos_doc))
        logging.info(f"✅ Cosmos DB actualizado: documentId={document_id}")

        logging.info("=" * 60)
        logging.info(f"✅ INDEXACIÓN COMPLETADA: {filename}")
        logging.info(f"   Chunks creados:  {len(chunks)}")
        logging.info(f"   Chunks subidos:  {total_uploaded}")
        logging.info(f"   indexed=True en Cosmos DB")
        logging.info("=" * 60)

    except Exception as e:
        logging.error(f"❌ ERROR en indexación: {str(e)}")
        logging.exception(e)

        # Marcar como error en Cosmos DB para que el admin lo vea en el panel
        try:
            err_id = myBlob.name.split("/")[-1].split("-")[0]
            outputDocument.set(func.Document.from_dict({
                "id":         err_id,
                "documentId": err_id,
                "indexed":    False,
                "error":      str(e),
                "errorAt":    datetime.now(timezone.utc).isoformat(),
            }))
        except Exception:
            pass  # Si esto también falla, no podemos hacer nada más

        raise