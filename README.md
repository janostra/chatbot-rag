# Chatbot RAG para Atención al Cliente - Los Amigos Turismo

Asistente virtual empresarial con IA avanzada que responde preguntas sobre destinos, precios, paquetes turísticos y servicios.  
Implementado con **RAG (Retrieval-Augmented Generation)** para recuperar información actualizada desde una base de conocimientos con **entrada y salida de voz bidireccional**.

---

## Descripción

Chatbot conversacional nivel enterprise con inteligencia artificial que utiliza RAG (Retrieval-Augmented Generation) para proporcionar información precisa sobre paquetes turísticos, destinos, precios y servicios de la agencia. Integra **6 servicios de Azure Cloud** con monitoreo en tiempo real y gestión inteligente de documentos.

## Características Principales

- 🔍 **Búsqueda semántica (Azure AI Search)** — Vector search + hybrid search  
- 🧠 **IA conversacional (Hugging Face Mistral 7B)** — Modelo state-of-the-art  
- 🎤 **Speech-to-Text (Azure Speech)** — Entrada por voz, manos libres  
- 🗣️ **Text-to-Speech (Azure Speech)** — Respuestas auditivas en español argentino  
- 💾 **Historial persistente (Cosmos DB)** — Base de datos NoSQL serverless  
- 🗂️ **Gestión de documentos (Blob Storage)** — Subida dinámica de archivos  
- 📊 **Monitoreo enterprise (Application Insights)** — Telemetría en tiempo real  
- 🌐 **Arquitectura 100% cloud** — Escalable y resiliente  
- 🎨 **Frontend moderno (HTML + Tailwind + JS)** — UI/UX profesional  
- 📈 **Estadísticas en vivo** — Dashboard con métricas actualizadas  

---

## Arquitectura

```
Usuario (Navegador)
       ↓
Frontend (HTML/JS con STT/TTS)
       ↓
Backend Node.js (Express + App Insights)
       ↓
├─> Cosmos DB (historial + analytics)
├─> Speech Services (STT + TTS bidireccional)
├─> Blob Storage (documentos)
└─> Backend Python (FastAPI + RAG)
          ↓
    ├─> Hugging Face (Mistral 7B)
    └─> Azure AI Search (vector database)
```
---

## Stack Tecnológico

### Frontend

- **HTML5** — Estructura semántica  
- **Tailwind CSS** — Diseño moderno y responsive  
- **JavaScript ES6+** — Lógica del cliente  
- **Web Speech API** — Integración con micrófono  

### Backend (Node.js)

- **Express.js** — Framework web minimalista  
- **Mongoose** — ODM para Cosmos DB (MongoDB API)  
- **Azure SDK** — Integración nativa con servicios  
- **Cognitive Services Speech SDK** — STT + TTS  
- **Application Insights** — Telemetría y monitoreo  
- **Multer** — Manejo de uploads de archivos  
- **Blob Storage Client** — Gestión de documentos  

### Backend (Python - RAG)

- **FastAPI** — API de alto rendimiento  
- **LangChain** — Framework para aplicaciones con LLMs  
- **Hugging Face Hub** — Acceso a modelos (Mistral 7B)  
- **Azure AI Search SDK** — Búsqueda vectorial híbrida  
- **Sentence Transformers** — Embeddings multilingües  

### Cloud Services (Azure)

1. **Cosmos DB** — Base de datos NoSQL (MongoDB API) con tier gratuito  
2. **Azure AI Search** — Vector database para RAG con búsqueda híbrida  
3. **Speech Services** — Text-to-Speech + Speech-to-Text  
4. **Blob Storage** — Almacenamiento escalable de documentos  
5. **Application Insights** — Monitoreo, logs y telemetría  
6. **Resource Group** — Gestión unificada de recursos  

### IA y Machine Learning

- **Hugging Face Mistral 7B** — Modelo de lenguaje de 7B parámetros  
- **paraphrase-multilingual-MiniLM** — Embeddings para español  

---

## 🧰 Stack Tecnológico

### Prerrequisitos

- Node.js 18+ y npm  
- Python 3.11+  
- Azure CLI  
- Cuenta de Azure (Azure for Students recomendado)  
- Token de Hugging Face (gratuito)  

### 1. Clonar el repositorio

```bash
git clone https://github.com/tu-usuario/chatbot-rag-azure.git
cd chatbot-rag-azure
```

### 2. Instalar Azure CLI (una sola vez)

```bash
# WSL/Linux
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# macOS
brew install azure-cli

# Windows
winget install Microsoft.AzureCLI
```

### 3. Login a Azure (una sola vez)

```bash
az login
```

### 4. Configurar Azure Resources

Hacer ejecutable el script de setup:

```bash
chmod +x setup-azure.sh
```

**Este script creará automáticamente:**
- Resource Group  
- Cosmos DB (MongoDB API) - **GRATIS**  
- Azure AI Search - **GRATIS**  
- Speech Services (STT + TTS)  
- Blob Storage  
- Application Insights - **GRATIS** (5GB/mes)  

Ejecutar (esto crea todos los recursos en Azure):

```bash
./setup-azure.sh
```

⏱️ **Tiempo estimado:** 8-10 minutos

### 5. Configurar Hugging Face

1. Crear cuenta en: https://huggingface.co/join (2 minutos)
2. Obtener token en: https://huggingface.co/settings/tokens
3. Editar `.env` y agregar el token:

```bash
nano .env
# Buscar: HUGGINGFACE_API_KEY=AGREGA_TU_TOKEN_AQUI
# Reemplazar con tu token
```

**El script setup-azure.sh genera automáticamente el archivo `.env` con todas las credenciales de Azure.**

### 6. Indexar documentos

```bash
cd backend
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
python index_documents.py
```

### 7. Ejecutar localmente

**Terminal 1 (Backend Python):**

```bash
cd backend
source venv/bin/activate
python app.py
```

**Terminal 2 (Backend Node.js):**

```bash
cd backend
npm install
npm start
```

**Abrir navegador:**

```
http://localhost:3000
```

---

## Uso

### Chat por Texto

1. Escribe tu pregunta en el input  
2. Presiona **Enter** o click en **Enviar**  
3. El bot responde usando RAG (información de los documentos)  

### Chat por Voz 🎤 (NUEVO)

1. Click en el botón **🎤 Micrófono** verde  
2. Habla tu pregunta claramente  
3. Click en **⏹️ Detener** cuando termines  
4. El sistema transcribe automáticamente (Speech-to-Text)  
5. El bot responde por texto **y por voz** si está activado 🔊  

### Activar/Desactivar Voz de Respuestas

- Click en **🔊 Voz: ON** para escuchar respuestas  
- Click en **🔇 Voz: OFF** para solo texto  

## API Endpoints

| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/health` | GET | Health check de todos los servicios |
| `/ask` | POST | Enviar pregunta al chatbot (RAG) |
| `/stt` | POST | Speech-to-Text (voz → texto) |
| `/tts` | POST | Text-to-Speech (texto → voz) |
| `/upload-document` | POST | Subir documento a Blob Storage |
| `/documents` | GET | Listar documentos subidos |
| `/history/:id` | GET | Historial de conversación |
| `/stats` | GET | Estadísticas del sistema |

---

## Características 
### 🎤 Entrada por Voz (Speech-to-Text)
- Reconocimiento en español argentino  
- Transcripción automática en tiempo real  
- Manos libres para mejor UX  

### 🗣️ Salida por Voz (Text-to-Speech)
- Voz neural femenina (Elena) en español argentino  
- Audio MP3 de alta calidad  
- Reproducción automática en el navegador  

### 📊 Monitoreo Avanzado
- Telemetría completa con Application Insights  
- Tracking de eventos custom (ChatQuery, SpeechToText, etc.)  
- Métricas de performance (responseTime)  
- Detección automática de errores  

### 🗂️ Gestión de Documentos
- Upload de archivos a Blob Storage  
- Metadata tracking en Cosmos DB  
- Re-indexación para actualizar base de conocimientos  

### 💾 Persistencia Completa
- Historial de conversaciones en Cosmos DB  
- Tracking de tiempo de respuesta  
- Identificación de usuarios (opcional)  

## Tecnologías y Conceptos de Cloud

- ✅ **Serverless Computing** (Cosmos DB, App Insights)  
- ✅ **PaaS** (Azure AI Search, Speech Services)  
- ✅ **NoSQL Database** (Cosmos DB con MongoDB API)  
- ✅ **Object Storage** (Blob Storage)  
- ✅ **Observability** (Application Insights, telemetría)  
- ✅ **Microservices** (Node.js + Python separados)  
- ✅ **API REST** (Express + FastAPI)  
- ✅ **RAG Pattern** (Retrieval-Augmented Generation)  
- ✅ **Vector Search** (embeddings + similarity search)  
- ✅ **Hybrid Search** (keyword + semantic)  

---

## Licencia

Este proyecto es open source, como tu mejor amigo que nunca te falla.  
Úsalo, modifícalo y pásalo bien.

⭐ **Si este proyecto te sirvió, considera darle una estrella en GitHub**

**Desarrollado como proyecto final de Cloud Computing** 🎓☁️
