"""
Script para indexar documentos en Azure AI Search
Usa Hugging Face embeddings (GRATIS, corre local)
"""

import os
from dotenv import load_dotenv
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import AzureSearch
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_core.documents import Document

load_dotenv()

# Variables
AZURE_SEARCH_ENDPOINT = os.getenv("AZURE_SEARCH_ENDPOINT")
AZURE_SEARCH_KEY = os.getenv("AZURE_SEARCH_KEY")
AZURE_SEARCH_INDEX = os.getenv("AZURE_SEARCH_INDEX", "travel-docs")

def create_documents_from_file(file_path: str):
    """Lee el archivo y crea documentos"""
    
    print(f"📄 Leyendo: {file_path}")
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Dividir en chunks
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=500,
        chunk_overlap=50,
    )
    
    chunks = text_splitter.split_text(content)
    
    documents = []
    for i, chunk in enumerate(chunks):
        doc = Document(
            page_content=chunk,
            metadata={
                "source": file_path,
                "chunk_id": i,
                "type": "company_info"
            }
        )
        documents.append(doc)
    
    print(f"✅ Creados {len(documents)} chunks")
    return documents

def index_documents():
    """Indexa los documentos en Azure AI Search"""
    
    print("🚀 Iniciando indexación...")
    
    # Validar variables
    if not all([AZURE_SEARCH_ENDPOINT, AZURE_SEARCH_KEY]):
        print("❌ Faltan variables de entorno de Azure Search")
        print("   Verifica tu archivo .env")
        return
    
    # Configurar embeddings de Hugging Face
    print("🔧 Descargando modelo de embeddings de Hugging Face...")
    print("   (Primera vez tarda ~1 min, luego es instantáneo)")
    embeddings = HuggingFaceEmbeddings(
        model_name="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
        model_kwargs={'device': 'cpu'}
    )
    print("✅ Modelo de embeddings cargado")
    
    # Leer documentos
    documents = create_documents_from_file("data/info_empresa.txt")

    # Crear índice en Azure Search
    print(f"📊 Indexando en Azure AI Search...")
    print("   (Generando embeddings...)")
    
    vector_store = AzureSearch(
        azure_search_endpoint=AZURE_SEARCH_ENDPOINT,
        azure_search_key=AZURE_SEARCH_KEY,
        index_name=AZURE_SEARCH_INDEX,
        embedding_function=embeddings.embed_query
    )
    
    # Agregar documentos
    vector_store.add_documents(documents)
    
    print("✅ Indexación completada!")
    print(f"   Total chunks: {len(documents)}")
    print(f"   Índice: {AZURE_SEARCH_INDEX}")
    
    # Test de búsqueda
    print("\n🔍 Test de búsqueda...")
    test_query = "¿Cuáles son los destinos disponibles?"
    results = vector_store.similarity_search(test_query, k=2)
    
    print(f"\nResultados para: '{test_query}'")
    for i, doc in enumerate(results, 1):
        print(f"\n{i}. {doc.page_content[:100]}...")

def add_extra_info():
    """Agrega información adicional útil"""
    
    print("\n📚 Agregando info complementaria...")
    
    embeddings = HuggingFaceEmbeddings(
        model_name="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
        model_kwargs={'device': 'cpu'}
    )
    
    vector_store = AzureSearch(
        azure_search_endpoint=AZURE_SEARCH_ENDPOINT,
        azure_search_key=AZURE_SEARCH_KEY,
        index_name=AZURE_SEARCH_INDEX,
        embedding_function=embeddings.embed_query
    )
    
    extra_docs = [
        {
            "content": """Florianópolis: Conocida como 'La Isla de la Magia'. 
            Barra da Lagoa es un barrio de pescadores con hermosas playas.
            Playas cercanas: Mole, Joaquina, Galheta, Barra da Lagoa.
            Actividades populares: surf, sandboard, paseos en barco, vida nocturna.""",
            "metadata": {"type": "destination", "location": "florianopolis"}
        },
        {
            "content": """Cataratas del Iguazú: Patrimonio de la Humanidad UNESCO.
            Sistema de 275 saltos de agua. La Garganta del Diablo es el más impresionante.
            Actividades: paseo en lancha, recorridos por pasarelas, visita al Parque Nacional.
            Mejor época para visitar: marzo a mayo y septiembre a noviembre.""",
            "metadata": {"type": "destination", "location": "iguazu"}
        },
        {
            "content": """Preguntas frecuentes sobre los viajes:
            ¿Qué incluye el paquete? Transporte ida y vuelta, hospedaje con desayuno, excursiones guiadas.
            ¿Necesito visa para Brasil? No, los argentinos no necesitan visa.
            ¿Puedo pagar en cuotas? Sí, ofrecemos planes de cuotas sin interés.
            ¿Hay descuentos para grupos? Sí, consultá por promociones especiales para grupos.""",
            "metadata": {"type": "faq"}
        }
    ]
    
    for info in extra_docs:
        doc = Document(
            page_content=info["content"],
            metadata=info["metadata"]
        )
        vector_store.add_documents([doc])
        print(f"   ✅ {info['metadata'].get('type')}")
    
    print("\n✅ Info complementaria agregada")

if __name__ == "__main__":
    try:
        index_documents()
        add_extra_info()
        print("\n ¡Todo listo!")
        print("\n Nota: Los embeddings se generan localmente (en tu CPU)")
        print("   No requiere GPU ni servicios externos para embeddings")
        print("\n   Ahora puedes iniciar los servidores:")
        print("   Terminal 1: python app.py")
        print("   Terminal 2: npm start")
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        raise