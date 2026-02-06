"""
Azure Function: Auto-indexación de documentos en Azure AI Search
Se ejecuta automáticamente cuando se sube un archivo a Blob Storage
"""

import logging
import os
import json
import azure.functions as func
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import AzureSearch
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_core.documents import Document
from datetime import datetime


def main(myBlob: func.InputStream, outputDocument: func.Out[func.Document]):
    """
    Trigger: Se ejecuta cuando se sube un archivo a Blob Storage
    Input: Archivo del blob
    Output: Actualiza documento en Cosmos DB
    """
    
    logging.info(f"🔔 Azure Function triggered: {myBlob.name}")
    logging.info(f"📦 Blob size: {myBlob.length} bytes")
    
    try:
        # 1. Leer contenido del blob
        content = myBlob.read().decode('utf-8')
        logging.info(f"✅ Contenido leído: {len(content)} caracteres")
        
        # 2. Dividir en chunks
        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=500,
            chunk_overlap=50,
            length_function=len,
        )
        
        chunks = text_splitter.split_text(content)
        logging.info(f"✅ Creados {len(chunks)} chunks")
        
        # 3. Crear documentos de LangChain
        documents = []
        filename = myBlob.name.split('/')[-1]  # Extraer solo el nombre
        
        for i, chunk in enumerate(chunks):
            doc = Document(
                page_content=chunk,
                metadata={
                    "source": filename,
                    "chunk_id": i,
                    "total_chunks": len(chunks),
                    "type": "uploaded_document",
                    "uploaded_at": datetime.utcnow().isoformat()
                }
            )
            documents.append(doc)
        
        # 4. Configurar embeddings
        logging.info("🔧 Configurando embeddings...")
        embeddings = HuggingFaceEmbeddings(
            model_name="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
            model_kwargs={"device": "cpu"}
        )
        
        # 5. Indexar en Azure AI Search
        logging.info("🔍 Indexando en Azure AI Search...")
        vector_store = AzureSearch(
            azure_search_endpoint=os.environ["AZURE_SEARCH_ENDPOINT"],
            azure_search_key=os.environ["AZURE_SEARCH_KEY"],
            index_name=os.environ.get("AZURE_SEARCH_INDEX", "travel-docs"),
            embedding_function=embeddings.embed_query
        )
        
        vector_store.add_documents(documents)
        logging.info(f"✅ {len(documents)} documentos indexados en Azure AI Search")
        
        # 6. Actualizar estado en Cosmos DB
        # Extraer el documentId del nombre del archivo (formato: {uuid}-{filename})
        document_id = filename.split('-')[0] if '-' in filename else filename
        
        cosmos_update = {
            "id": document_id,
            "documentId": document_id,
            "filename": filename,
            "indexed": True,
            "indexedAt": datetime.utcnow().isoformat(),
            "totalChunks": len(chunks)
        }
        
        outputDocument.set(func.Document.from_dict(cosmos_update))
        logging.info(f"✅ Cosmos DB actualizado: {document_id}")
        
        logging.info("=" * 60)
        logging.info(f"✅ INDEXACIÓN COMPLETADA: {filename}")
        logging.info(f"   - Chunks creados: {len(chunks)}")
        logging.info(f"   - Estado en Cosmos DB: indexed=True")
        logging.info("=" * 60)
        
    except Exception as e:
        logging.error(f"❌ ERROR en indexación: {str(e)}")
        logging.exception(e)
        
        # Intentar marcar como error en Cosmos DB
        try:
            document_id = myBlob.name.split('/')[-1].split('-')[0]
            cosmos_error = {
                "id": document_id,
                "documentId": document_id,
                "indexed": False,
                "error": str(e),
                "errorAt": datetime.utcnow().isoformat()
            }
            outputDocument.set(func.Document.from_dict(cosmos_error))
        except:
            pass
        
        raise