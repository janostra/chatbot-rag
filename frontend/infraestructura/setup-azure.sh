#!/bin/bash

# Script COMPLETO para configurar TODOS los recursos de Azure
# Incluye: Cosmos DB, AI Search, Speech, Blob Storage, App Insights

set -e

echo " Configurando TODOS los recursos de Azure para Chatbot RAG PRO"

# Variables
RESOURCE_GROUP="rg-chatbot-rag"
LOCATION="westus3"
TIMESTAMP=$(date +%s)
COSMOS_ACCOUNT="cosmos-chatbot-${TIMESTAMP}"
SEARCH_SERVICE="search-chatbot-${TIMESTAMP}"
SPEECH_SERVICE="speech-chatbot-${TIMESTAMP}"
STORAGE_ACCOUNT="storage${TIMESTAMP}"
APPINSIGHTS="appinsights-chatbot-${TIMESTAMP}"

echo ""
echo " Configuración:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Location: $LOCATION"
echo ""

# 1. Login
echo " Verificando login en Azure..."
az account show &> /dev/null || az login

# 2. Crear Resource Group
echo " Creando Resource Group..."
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION \
  --output none

echo " Resource Group creado"

# 3. Crear Cosmos DB (GRATIS)
echo "  Creando Cosmos DB (GRATIS - 1000 RU/s)..."
az cosmosdb create \
  --name $COSMOS_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --kind MongoDB \
  --server-version "4.2" \
  --default-consistency-level Eventual \
  --enable-free-tier true \
  --locations regionName=$LOCATION failoverPriority=0 \
  --output none

echo "✅ Cosmos DB creado"
echo "⏳ Esperando a que Cosmos DB esté listo..."
sleep 60

# Crear DB y colecciones
az cosmosdb mongodb database create \
  --account-name $COSMOS_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --name chatbot \
  --output none

az cosmosdb mongodb collection create \
  --account-name $COSMOS_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --database-name chatbot \
  --name conversations \
  --output none

az cosmosdb mongodb collection create \
  --account-name $COSMOS_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --database-name chatbot \
  --name documents \
  --output none

MONGO_URI=$(az cosmosdb keys list \
  --name $COSMOS_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --type connection-strings \
  --query "connectionStrings[0].connectionString" -o tsv)

# 4. Crear Azure AI Search (GRATIS)
echo " Creando Azure AI Search (GRATIS)..."
az search service create \
  --name $SEARCH_SERVICE \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku free \
  --output none

echo " Azure AI Search creado"

SEARCH_KEY=$(az search admin-key show \
  --service-name $SEARCH_SERVICE \
  --resource-group $RESOURCE_GROUP \
  --query "primaryKey" -o tsv)

SEARCH_ENDPOINT="https://${SEARCH_SERVICE}.search.windows.net"

# 5. Crear Speech Service
echo "  Creando Speech Service..."
# Intentar F0 (gratis), si falla usar S0
az cognitiveservices account create \
  --name $SPEECH_SERVICE \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --kind SpeechServices \
  --sku F0 \
  --yes \
  --output none 2>/dev/null || \
az cognitiveservices account create \
  --name $SPEECH_SERVICE \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --kind SpeechServices \
  --sku S0 \
  --yes \
  --output none

echo " Speech Service creado"

SPEECH_KEY=$(az cognitiveservices account keys list \
  --name $SPEECH_SERVICE \
  --resource-group $RESOURCE_GROUP \
  --query "key1" -o tsv)

# 6. Crear Storage Account para Blob Storage
echo "🗂️  Creando Storage Account..."
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --output none

echo " Storage Account creado"

# Crear container para documentos
STORAGE_CONNECTION=$(az storage account show-connection-string \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query connectionString -o tsv)

az storage container create \
  --name documents \
  --account-name $STORAGE_ACCOUNT \
  --connection-string "$STORAGE_CONNECTION" \
  --public-access blob \
  --output none

# 7. Crear Application Insights
echo " Creando Application Insights..."
az monitor app-insights component create \
  --app $APPINSIGHTS \
  --location $LOCATION \
  --resource-group $RESOURCE_GROUP \
  --application-type web \
  --output none

echo " Application Insights creado"

APPINSIGHTS_CONNECTION=$(az monitor app-insights component show \
  --app $APPINSIGHTS \
  --resource-group $RESOURCE_GROUP \
  --query "connectionString" -o tsv)

APPINSIGHTS_KEY=$(az monitor app-insights component show \
  --app $APPINSIGHTS \
  --resource-group $RESOURCE_GROUP \
  --query "instrumentationKey" -o tsv)

# 8. Generar archivo .env
echo ""
echo " Generando archivo .env..."

cat > .env << EOF
# ============================================
# AZURE CONFIGURATION - PROYECTO COMPLETO
# ============================================

# Node.js Backend
PORT=3000
NODE_ENV=development

# ============================================
# AZURE COSMOS DB (GRATIS - Permanente)
# ============================================
MONGO_URI="$MONGO_URI"

# ============================================
# AZURE SPEECH SERVICES (STT + TTS)
# ============================================
SPEECH_KEY=$SPEECH_KEY
SPEECH_REGION=$LOCATION

# ============================================
# AZURE BLOB STORAGE (Documentos)
# ============================================
AZURE_STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION
AZURE_STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT

# ============================================
# AZURE APPLICATION INSIGHTS (Telemetría)
# ============================================
APPINSIGHTS_CONNECTION_STRING=$APPINSIGHTS_CONNECTION
APPINSIGHTS_INSTRUMENTATION_KEY=$APPINSIGHTS_KEY

# ============================================
# RAG Backend Endpoint
# ============================================
RAG_ENDPOINT=http://localhost:8000

# ============================================
# HUGGING FACE (IA - GRATIS)
# Obtén tu token en: https://huggingface.co/settings/tokens
# ============================================
HUGGINGFACE_API_KEY=AGREGA_TU_TOKEN_AQUI

# ============================================
# AZURE AI SEARCH (Vector DB - GRATIS)
# ============================================
AZURE_SEARCH_ENDPOINT=$SEARCH_ENDPOINT
AZURE_SEARCH_KEY=$SEARCH_KEY
AZURE_SEARCH_INDEX=travel-docs
EOF

echo "✔ Archivo .env creado"
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║        CONFIGURACIÓN COMPLETA - PROYECTO PRO           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo " Recursos Azure creados:"
echo "   ✔ Resource Group: $RESOURCE_GROUP"
echo "   ✔ Cosmos DB: $COSMOS_ACCOUNT (GRATIS)"
echo "   ✔ AI Search: $SEARCH_SERVICE (GRATIS)"
echo "   ✔ Speech Service: $SPEECH_SERVICE (STT + TTS)"
echo "   ✔ Storage Account: $STORAGE_ACCOUNT"
echo "   ✔ Application Insights: $APPINSIGHTS"
echo ""
echo "Servicios implementados:"
echo "   •  Chat conversacional con RAG"
echo "   •  Speech-to-Text (entrada por voz)"
echo "   •  Text-to-Speech (respuestas en voz)"
echo "   •  Blob Storage (subir documentos)"
echo "   •  Application Insights (monitoreo en tiempo real)"
echo "   •  Cosmos DB (persistencia)"
echo "   •  Azure AI Search (búsqueda semántica)"
echo ""
echo " Costos estimados:"
echo "   - Cosmos DB: GRATIS (tier permanente)"
echo "   - AI Search: GRATIS (tier permanente)"
echo "   - Speech (F0): GRATIS (5h/mes) o S0: ~\$1/hora"
echo "   - Storage: ~\$0.02/GB/mes"
echo "   - App Insights: GRATIS (primeros 5GB/mes)"
echo ""
echo "   ⚡ TOTAL: \$0-5/mes (mayoría GRATIS)"
echo ""
echo " PRÓXIMOS PASOS:"
echo ""
echo "1️  Obtener token de Hugging Face:"
echo "     https://huggingface.co/settings/tokens"
echo ""
echo "2️  Editar .env y agregar el token:"
echo "    nano .env"
echo "    Buscar: HUGGINGFACE_API_KEY=AGREGA_TU_TOKEN_AQUI"
echo ""
echo "3️  Instalar dependencias Python:"
echo "    cd backend"
echo "    python3 -m venv venv"
echo "    source venv/bin/activate"
echo "    pip install -r requirements.txt"
echo ""
echo "4️  Indexar documentos:"
echo "    python index_documents.py"
echo ""
echo "5️  Iniciar backend Python:"
echo "    python app.py"
echo ""
echo "6️  En otra terminal, instalar Node:"
echo "    cd frontend"
echo "    npm install"
echo ""
echo "7️  Iniciar servidor Node:"
echo "    npm start"
echo ""
echo "8️  Abrir navegador:"
echo "    http://localhost:3000"
echo ""
echo " Ver métricas en Application Insights:"
echo "    https://portal.azure.com → $APPINSIGHTS"
echo ""
echo " ¡Todo listo!"