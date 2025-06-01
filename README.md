# Chatbot RAG para Atención al Cliente

Un chatbot con IA que responde preguntas clave sobre la empresa usando Retrieval-Augmented Generation (RAG).  
Ideal para reemplazar ese empleado que sabe todo, pero sin café ni descansos.

---

## Descripción

Este proyecto combina FastAPI, LangChain y Chroma para crear un chatbot capaz de responder consultas sobre la empresa basándose en documentos cargados (info, promociones, servicios, etc.). Además, integra ElevenLabs para texto-voz y reconocimiento de voz.

El objetivo:  
- Contestar solo preguntas relacionadas con la empresa (si no sabe, lo dice).  
- Guardar info de clientes en base de datos para mejorar la experiencia.  
- Comunicación por WhatsApp (próximamente).

---

## Estructura

- `src/rag/`: Código para carga de documentos y servidor RAG en FastAPI.  
- `src/controllers/`: Controladores para manejar mensajes.  
- `src/services/`: Servicios para OpenAI, ElevenLabs y RAG.  
- `src/routes/`: Definición de rutas HTTP.  
- `data/`: Documentos de información de la empresa para RAG.  

---

## Instalación

1. Clonar repo:  
   ```bash
   git clone https://github.com/janostra/chatbot-rag.git
   cd chatbot-rag


2. Crear y activar entorno virtual:

    python -m venv venv
    source venv/bin/activate  # Linux/Mac
    .\venv\Scripts\activate   # Windows


3. Instalar dependencias:
    pip install -r requirements.txt


4. Configurar variables de entorno en .env:
    OPENAI_API_KEY=tu_api_key_aqui


5. Cargar documentos para RAG:
    python src/rag/loaddocs.py


6. Levantar servidor:
    uvicorn src.rag.rag_server:app --host 0.0.0.0 --port 8000 --reload


7. Iniciar backend del chatbot (Node.js):
    npm install
    npm run dev


Uso
Enviar mensajes al endpoint /message (o interfaz WhatsApp cuando esté lista) y el bot responderá basado en la info cargada. Si la pregunta es irrelevante, responderá educadamente que no está preparado para eso.


Próximos pasos
Integrar WhatsApp API para chat en vivo.

Añadir base de datos para almacenar datos de clientes y consultas.

Mejorar manejo de contextos y memoria conversacional.

Licencia
Este proyecto es open source, como tu mejor amigo que nunca te falla.
Usalo, modificalo y pásalo bien.