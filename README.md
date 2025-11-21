# Chatbot RAG para Atención al Cliente


Asistente virtual con IA que responde preguntas sobre destinos, precios, paquetes turísticos y servicios.  
Implementado con **RAG (Retrieval-Augmented Generation)** para recuperar información actualizada desde una base de conocimientos

---

## Descripción

Chatbot conversacional con inteligencia artificial que utiliza RAG (Retrieval-Augmented Generation) para proporcionar información precisa sobre paquetes turísticos, destinos, precios y servicios de la agencia

 Características Principales

- 🔍 **Búsqueda semántica (Azure AI Search)** — Vector search + hybrid search  
- 🧠 **IA conversacional (HuggingFace Mistral 7B)**  
- 🗣️ **Text-to-Speech (Azure Speech)**  
- 💾 **Historial persistente (Cosmos DB)**  
- 🌐 **Arquitectura 100% cloud**  
- 🎨 **Frontend moderno (HTML + Tailwind + JS)**  
- 🔐 **Secrets seguros (Azure Key Vault)**  
---

## Estructura

Frontend (HTML/JS)
       ↓
Backend Node.js (Express)
       ↓
Backend Python (FastAPI + RAG)
       ↓
HuggingFace (Mistral 7B) + Azure AI Search
---

## Stack Tecnológico
# Frontend

- HTML5  
- Tailwind CSS  
- JavaScript ES6  

# Backend (Node.js)

- Express.js  
- Mongoose (Cosmos DB)  
- Azure SDK  
- Cognitive Services Speech SDK  

# Backend (Python - RAG)

- FastAPI  
- LangChain  
- Azure AI Search SDK  
- HuggingFace 

# Cloud Services (Azure)

- Cosmos DB: Base de datos NoSQL (MongoDB API)
- Azure AI Search: Vector database para RAG
- Azure Speech Services: Text-to-Speech

---

## Instalación
# Prerrequisitos

- Node.js 18+ y npm
- Python 3.11+
- Azure CLI
- Cuenta de Azure (Azure for Students recomendado)
- Hugging Face Key

1. Clonar el repositorio
git clone  https://github.com/tu-usuario/chatbot-rag-azure.git
cd chatbot-rag-azure

2. Instalar Azure CLI (una sola vez)
     curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

3. Login a Azure (una sola vez)
     az login

4. Configurar Azure Resources
- Hacer ejecutable el script de setup
     chmod +x setup-azure.sh

# Este script creará:
- Resource Group
- Cosmos DB (MongoDB API)
- Azure AI Search
- Speech Services
- App Service Plan

5. Configurar variables de entorno
El script setup-azure.sh genera automáticamente un archivo .env con todas las credenciales.

## Ejecutar (esto crea todos los recursos en Azure)
./setup-azure.sh

6. Indexar documentos

- cd backend-python
- python -m venv venv
- source venv/bin/activate
- pip install -r requirements.txt
- python index_documents.py

7. Ejecutar localmente

# Terminal 1 (Backend Python):
- cd backend-python
- source venv/bin/activate
- uvicorn app:app --reload --port 8000

# Terminal 2 (Backend Node):
- cd backend-node
- npm install
- npm start

Abrir: http://localhost:3000

## Uso
# Ejemplos de preguntas

Usuario: "¿Qué destinos ofrecen?"
Bot: Ofrecemos paquetes turísticos a Brasil (Florianópolis) y 
     Cataratas del Iguazú en Argentina 🌴✈️

Usuario: "¿Cuánto cuesta el viaje a Florianópolis?"
Bot: Temporada baja desde USD 250 y temporada de verano desde 
     USD 300. Incluye traslado, hospedaje y excursiones 💰

Usuario: "¿Cómo puedo reservar?"
Bot: Contactanos por WhatsApp al 221 316 0988 o visitá nuestra 
     oficina en La Plata 📞

Licencia
Este proyecto es open source, como tu mejor amigo que nunca te falla.
Usalo, modificalo y pásalo bien.