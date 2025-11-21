# Chatbot RAG para Atención al Cliente

Asistente virtual con IA que responde preguntas sobre destinos, precios, paquetes turísticos y servicios. Implementado con **RAG (Retrieval-Augmented Generation)** para recuperar información desde una base de conocimientos.

---

## Descripción

Chatbot conversacional basado en RAG que proporciona información precisa y actualizada sobre viajes, destinos y servicios turísticos.

### **Características principales**

* 🔍 **Búsqueda semántica (Azure AI Search)** — Vector + Hybrid Search
* 🧠 **IA conversacional (Mistral 7B - HuggingFace)**
* 🗣️ **Text-to-Speech (Azure Speech Services)**
* 💾 **Historial persistente (Cosmos DB)**
* 🌐 **Arquitectura cloud completa**
* 🎨 **Frontend moderno (HTML + Tailwind + JS)**

---

## 📁 Arquitectura

```
Frontend (HTML/JS)
       ↓
Backend Node.js (Express)
       ↓
Backend Python (FastAPI + RAG)
       ↓
HuggingFace (Mistral 7B) + Azure AI Search
```

---

## 🧰 Stack Tecnológico

### Frontend

* HTML5
* Tailwind CSS
* JavaScript ES6

### Backend Node.js

* Express.js
* Azure SDK
* Cognitive Services Speech SDK
* Cosmos DB (Mongo API)

### Backend Python (RAG)

* FastAPI
* LangChain
* Azure AI Search
* HuggingFace Embeddings

### Azure Cloud

* Azure AI Search
* Cosmos DB
* Azure Speech Services

---

## ⚙️ Instalación

### **Prerrequisitos**

* Node.js 18+
* Python 3.11+
* Azure CLI
* Cuenta de Azure
* Hugging Face API Key

---

### 1️⃣ Clonar el repositorio

```bash
git clone https://github.com/tu-usuario/chatbot-rag-azure.git
cd chatbot-rag-azure
```

### 2️⃣ Instalar Azure CLI (una sola vez)

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### 3️⃣ Iniciar sesión en Azure

```bash
az login
```

---

## 4️⃣ Configurar Azure Resources

Hacer ejecutable el script de setup:

```bash
chmod +x setup-azure.sh
```

Ejecutar la configuración de recursos (crea RG, Cosmos, Search, Speech, App Service):

```bash
./setup-azure.sh
```

Este script también genera automáticamente el archivo `.env`.

---

## 5️⃣ Indexar documentos

```bash
cd backend-python
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python index_documents.py
```

---

## 6️⃣ Ejecutar localmente

### Backend Python (RAG)

```bash
cd backend-python
source venv/bin/activate
uvicorn app:app --reload --port 8000
```

### Backend Node.js

```bash
cd backend-node
npm install
npm start
```

Abrir en el navegador:
**[http://localhost:3000](http://localhost:3000)**

---

## 💬 Ejemplos de uso

**Usuario:** "¿Qué destinos ofrecen?"
**Bot:** "Ofrecemos viajes a Florianópolis y Cataratas del Iguazú."

**Usuario:** "¿Cuánto cuesta el viaje a Florianópolis?"
**Bot:** "Desde USD 250 en temporada baja y USD 300 en verano."

**Usuario:** "¿Cómo reservo?"
**Bot:** "Podés contactarnos por WhatsApp al 221 316 0988."

---

## 📜 Licencia

Este proyecto es open source. Usalo, modificalo y disfrutalo.
