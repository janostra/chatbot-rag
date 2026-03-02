# Chatbot RAG para Atención al Cliente - Los Amigos Turismo

Asistente virtual empresarial con IA avanzada que responde preguntas sobre destinos, precios, paquetes turísticos y servicios.  
Implementado con **RAG (Retrieval-Augmented Generation)** para recuperar información actualizada desde una base de conocimientos con **entrada y salida de voz bidireccional** y auto-indexación de documentos y **deployment completo en Azure App Service (PaaS)**.

---

## Descripción

Chatbot conversacional nivel enterprise con inteligencia artificial que utiliza RAG (Retrieval-Augmented Generation) para proporcionar información precisa sobre paquetes turísticos, destinos, precios y servicios de la agencia. Integra **8 servicios de Azure Cloud** con monitoreo en tiempo real y gestión inteligente de documentos.

## Características Principales

- 🔍 **Búsqueda semántica (Azure AI Search)** — Vector search + hybrid search  
- 🧠 **IA conversacional (Hugging Face Llama 8B)** — Modelo state-of-the-art  
- 🎤 **Speech-to-Text (Azure Speech)** — Entrada por voz, manos libres  
- 🗣️ **Text-to-Speech (Azure Speech)** — Respuestas auditivas en español argentino  
- 💾 **Historial persistente (Cosmos DB)** — Base de datos NoSQL serverless  
- 🗂️ **Gestión de documentos (Blob Storage)** — Subida dinámica de archivos  
- 📊 **Monitoreo enterprise (Application Insights)** — Telemetría en tiempo real  
- 🌐 **Arquitectura 100% cloud** — Escalable y resiliente  
- 🎨 **Frontend moderno (HTML + Tailwind + JS)** — UI/UX profesional  
- 📈 **Estadísticas en vivo** — Dashboard con métricas actualizadas  
- ⚡ **Auto-indexación** — Azure Function serverless
- 🔐 **Panel de administración** — Interfaz separada para gestión
- 🔑 **Azure Key Vault** — Gestión segura de secrets


---

## Arquitectura

```
Usuario (Navegador) / Admin (Panel Administrativo)
       ↓
Frontend (HTML/JS con STT/TTS)
       ↓
Azure App Service Node.js (Express)
       ↓
├─> Cosmos DB (historial + analytics)
├─> Speech Services (STT + TTS bidireccional)
├─> Blob Storage (documentos)
├─> Azure Key Vault (secrets)
└─> Azure App Service Python (FastAPI + RAG)
          ↓
    ├─> Hugging Face (Llama 8B)
    └─> Azure AI Search (vector database)
          ↓
    Azure Function (auto-indexación)
          ↓
    Application Insights (telemetría)
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
- **Key Vault SDK** — Gestión segura de secrets 

### Backend (Python - RAG)

- **FastAPI** — API de alto rendimiento  
- **LangChain** — Framework para aplicaciones con LLMs  
- **Hugging Face Hub** — Acceso a modelos (Llama 8B)  
- **Azure AI Search SDK** — Búsqueda vectorial híbrida  
- **Sentence Transformers** — Embeddings multilingües  
- **Gunicorn + Uvicorn** — Production ASGI server

### Cloud Services (Azure)

1. **Cosmos DB** — Base de datos NoSQL (MongoDB API) con tier gratuito  
2. **Azure AI Search** — Vector database para RAG con búsqueda híbrida  
3. **Speech Services** — Text-to-Speech + Speech-to-Text  
4. **Blob Storage** — Almacenamiento escalable de documentos  
5. **Application Insights** — Monitoreo, logs y telemetría  
6. **Azure Functions** Auto-indexacion de documentos
7. **App Service** - Hosting Backend y Frontend
8. **Key Vault** - Manejo de secretos

### IA y Machine Learning

- **Hugging Face Llama 8B** — Modelo de lenguaje de 7B parámetros  
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
chmod +x infrastructure/setup-azure.sh
./infrastructure/setup-azure.sh
```

**Este script creará automáticamente:**
- Resource Group  
- Cosmos DB (MongoDB API) - **GRATIS**  
- Azure AI Search - **GRATIS**  
- Speech Services (STT + TTS)  
- Blob Storage  
- Application Insights - **GRATIS** (5GB/mes)  
- **Genera archivo .env con las credenciales**

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
### 6. (Opcional) Configurar Key Vault
Para gestión segura de secrets en producción:
```bash
chmod +x infrastructure/setup-keyvault.sh
./infrastructure/setup-keyvault.sh
```
**Tiempo**: 2 minutos
Esto migra todos los secrets desde .env a Key Vault.

### 7. Indexar documentos

```bash
cd backend
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
cd ..
python index_documents.py
```

### 8. Deployment a Azure (Producción)

#### Opción A: Deployment Completo (Recomendado)
```bash
chmod +x infrastructure/deploy-appservice.sh
./infrastructure/deploy-appservice.sh
```
El script te preguntará:
•	F1 (Gratis): Para demos y testing
•	B1 ($13/mes): Para producción, siempre activo

**Tiempo total**: 8-12 minutos
**Resultado**: URLs públicas HTTPS para tu aplicación.

**Azure Function (Auto-indexación)**
•	Flujo para autoindexear documentos al subirlos

```bash
chmod +x infrastructure/deploy-function.sh
./infrastructure/deploy-function.sh
```

#### Opción B: Testing Local (antes de deployar)

**Terminal 1 (Backend Python):**

```bash
cd backend
source venv/bin/activate
python app.py
```

**Terminal 2 (Frontend Node.js):**

```bash
cd frontend
npm install
npm start
```

**Abrir navegador:**

```
Usuario: http://localhost:3000
Admin: http://localhost:3000/admin
```

---
### Azure Function (Auto-indexación)
Deploy la función serverless que indexa automáticamente documentos nuevos:
```bash
chmod +x infrastructure/deploy-function.sh
./infrastructure/deploy-function.sh
```
**Flujo automático:**
1. Admin sube documento en /admin → Blob Storage
2. Azure Function detecta nuevo archivo (trigger)
3. Function indexa en Azure AI Search
4. Function actualiza Cosmos DB (indexed: true)
5. Usuario puede preguntar sobre el contenido inmediatamente

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

### Panel de Administración (/admin)
**Credenciales por defecto:**
```
Usuario: admin
Password: changeme123
```

**IMPORTANTE: Cambiar en .env antes de producción:**
ADMIN_USERNAME=tu_usuario_seguro
ADMIN_PASSWORD=tu_password_complejo_123


## API Endpoints
**Públicos (sin autenticación)**

| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/health` | GET | Health check de todos los servicios |
| `/ask` | POST | Enviar pregunta al chatbot (RAG) |
| `/stt` | POST | Speech-to-Text (voz → texto) |
| `/tts` | POST | Text-to-Speech (texto → voz) |

**Admin (requieren autenticación)**
| Endpoint | Método | Descripción |
|----------|--------|-------------|
| `/admin` | GET | Panel de administración |
| `/admin/login` | POST | Login de administrador |
| `/admin/stats` | GET | Estadísticas del sistema |
| `/admin/documents` | GET | Listar todos los documentos |
| `/admin/upload-documents` | POST | Subir nuevo documento |
| `/admin/documents/:id` | DELETE | Eliminar documento |
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
## Comandos Útiles
### Gestión de App Services
# Reiniciar aplicaciones
```bash
az webapp restart -n chatbot-frontend-XXXXX -g rg-chatbot-rag
az webapp restart -n chatbot-backend-XXXXX -g rg-chatbot-rag
```

# Detener (para ahorrar en tier B1)
```bash
az webapp stop -n chatbot-frontend-XXXXX -g rg-chatbot-rag
az webapp stop -n chatbot-backend-XXXXX -g rg-chatbot-rag
```

# Iniciar
```bash
az webapp start -n chatbot-frontend-XXXXX -g rg-chatbot-rag
az webapp start -n chatbot-backend-XXXXX -g rg-chatbot-rag
```

# Cambiar tier (de F1 a B1)
```bash
az appservice plan update \
  --name plan-chatbot \
  --resource-group rg-chatbot-rag \
  --sku B1
```

# Ver configuración
```bash
az webapp config show -n chatbot-frontend-XXXXX -g rg-chatbot-rag
```

# Ver variables de entorno
```bash
az webapp config appsettings list \
  -n chatbot-frontend-XXXXX \
  -g rg-chatbot-rag
Testing y Debugging
```
# Verificar health
```bash
curl https://chatbot-frontend-XXXXX.azurewebsites.net/health
```

# Test del backend RAG
```bash
curl -X POST https://chatbot-backend-XXXXX.azurewebsites.net/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"¿Cuánto cuesta ir a Brasil?"}'
```

# Abrir SSH en App Service (solo Linux)
```bash
az webapp ssh -n chatbot-backend-XXXXX -g rg-chatbot-rag
```
# Ver métricas de uso
```bash
az monitor metrics list \
  --resource chatbot-frontend-XXXXX \
  --resource-group rg-chatbot-rag \
  --metric-names CpuPercentage MemoryPercentage
```

# Eliminar solo las apps (mantener plan)
```bash
az webapp delete -n chatbot-frontend-XXXXX -g rg-chatbot-rag
az webapp delete -n chatbot-backend-XXXXX -g rg-chatbot-rag
```

# Eliminar TODO el proyecto (cuando termines)
```bash
az group delete -n rg-chatbot-rag --yes --no-wait
```

## Comandos Útiles
### Gestión de App Services
# Reiniciar aplicaciones
```bash
az webapp restart -n chatbot-frontend-XXXXX -g rg-chatbot-rag
az webapp restart -n chatbot-backend-XXXXX -g rg-chatbot-rag
```

# Detener (para ahorrar en tier B1)
```bash
az webapp stop -n chatbot-frontend-XXXXX -g rg-chatbot-rag
az webapp stop -n chatbot-backend-XXXXX -g rg-chatbot-rag
```

# Iniciar
```bash
az webapp start -n chatbot-frontend-XXXXX -g rg-chatbot-rag
az webapp start -n chatbot-backend-XXXXX -g rg-chatbot-rag
```

# Cambiar tier (de F1 a B1)
```bash
az appservice plan update \
  --name plan-chatbot \
  --resource-group rg-chatbot-rag \
  --sku B1
```

# Ver configuración
```bash
az webapp config show -n chatbot-frontend-XXXXX -g rg-chatbot-rag
```

# Ver variables de entorno
```bash
az webapp config appsettings list \
  -n chatbot-frontend-XXXXX \
  -g rg-chatbot-rag
Testing y Debugging
```
# Verificar health
```bash
curl https://chatbot-frontend-XXXXX.azurewebsites.net/health
```

# Test del backend RAG
```bash
curl -X POST https://chatbot-backend-XXXXX.azurewebsites.net/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"¿Cuánto cuesta ir a Brasil?"}'
```

# Abrir SSH en App Service (solo Linux)
```bash
az webapp ssh -n chatbot-backend-XXXXX -g rg-chatbot-rag
```
# Ver métricas de uso
```bash
az monitor metrics list \
  --resource chatbot-frontend-XXXXX \
  --resource-group rg-chatbot-rag \
  --metric-names CpuPercentage MemoryPercentage
```

# Eliminar solo las apps (mantener plan)
```bash
az webapp delete -n chatbot-frontend-XXXXX -g rg-chatbot-rag
az webapp delete -n chatbot-backend-XXXXX -g rg-chatbot-rag
```

# Eliminar TODO el proyecto (cuando termines)
```bash
az group delete -n rg-chatbot-rag --yes --no-wait
```

## Licencia

Este proyecto es open source, como tu mejor amigo que nunca te falla.  
Úsalo, modifícalo y pásalo bien.

⭐ **Si este proyecto te sirvió, considera darle una estrella en GitHub**

**Desarrollado como proyecto final de Cloud Computing** 🎓☁️
