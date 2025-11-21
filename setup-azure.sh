#!/bin/bash

# Script para configurar recursos de Azure 
# Usaremos Hugging Face para IA
# USA SERVICIOS GRATIS DE AZURE

set -e

echo "🚀 Configurando recursos de Azure (GRATIS)"
echo "💡 Nota: Usaremos Hugging Face para IA (también gratis)"

# Variables
RESOURCE_GROUP="rg-chatbot-rag"
LOCATION="westus" 
COSMOS_ACCOUNT="cosmos-chatbot-$(date +%s)"
SEARCH_SERVICE="search-chatbot-$(date +%s)"
SPEECH_SERVICE="speech-chatbot-$(date +%s)"

echo ""
echo "   Configuración:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Location: $LOCATION"
echo ""

# 1. Verificar login
echo "🔐 Verificando login en Azure..."
az account show &> /dev/null || az login

# 2. Crear Resource Group 
echo "📦 Creando Resource Group..."
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION \
  --output none

echo "✅ Resource Group creado"

# 3. Crear Cosmos DB con tier GRATUITO 
echo "🗄️  Creando Cosmos DB (GRATIS - 1000 RU/s)..."
az cosmosdb create \
  --name $COSMOS_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --kind MongoDB \
  --server-version "4.2" \
  --default-consistency-level Eventual \
  --enable-free-tier true \
  --locations regionName=$LOCATION failoverPriority=0 \
  --output none

echo "✅ Cosmos DB creado (GRATIS)"
echo "⏳ Esperando a que Cosmos DB esté completamente listo..."
sleep 60

# Verificar que está listo
echo "🔍 Verificando estado de Cosmos DB..."
az cosmosdb show \
  --name $COSMOS_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --output none

# Crear DB y colección
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

# Obtener connection string
MONGO_URI=$(az cosmosdb keys list \
  --name $COSMOS_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --type connection-strings \
  --query "connectionStrings[0].connectionString" -o tsv)

# 4. Crear Azure AI Search (GRATIS hasta 50MB)
echo "🔍 Creando Azure AI Search (GRATIS)..."
az search service create \
  --name $SEARCH_SERVICE \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku free \
  --output none

echo "✅ Azure AI Search creado (GRATIS)"

# Obtener keys
SEARCH_KEY=$(az search admin-key show \
  --service-name $SEARCH_SERVICE \
  --resource-group $RESOURCE_GROUP \
  --query "primaryKey" -o tsv)

SEARCH_ENDPOINT="https://${SEARCH_SERVICE}.search.windows.net"

# 5. Crear Speech Service (GRATIS - 5 horas/mes)
echo "🗣️  Creando Speech Service (GRATIS 5h/mes)..."
az cognitiveservices account create \
  --name $SPEECH_SERVICE \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --kind SpeechServices \
  --sku F0 \
  --yes \
  --output none

echo "✅ Speech Service creado (GRATIS)"

# Obtener key
SPEECH_KEY=$(az cognitiveservices account keys list \
  --name $SPEECH_SERVICE \
  --resource-group $RESOURCE_GROUP \
  --query "key1" -o tsv)

# 6. Generar archivo .env
echo ""
echo "📄 Generando archivo .env..."

cat > .env << EOF
# ============================================
# AZURE CONFIGURATION (TODO GRATIS)
# ============================================

# Node.js Backend
PORT=3000
NODE_ENV=development

# Azure Cosmos DB (GRATIS - 1000 RU/s permanente)
MONGO_URI=$MONGO_URI

# Azure Speech Services (GRATIS - 5 horas/mes)
SPEECH_KEY=$SPEECH_KEY
SPEECH_REGION=$LOCATION

# RAG Backend Endpoint (local por ahora)
RAG_ENDPOINT=http://localhost:8000

# ============================================
# HUGGING FACE (IA - GRATIS)
# ============================================

# Obtén tu token en: https://huggingface.co/settings/tokens
HUGGINGFACE_API_KEY=AGREGA_TU_TOKEN_AQUI

# ============================================
# Azure AI Search (GRATIS - hasta 50MB)
# ============================================

AZURE_SEARCH_ENDPOINT=$SEARCH_ENDPOINT
AZURE_SEARCH_KEY=$SEARCH_KEY
AZURE_SEARCH_INDEX=travel-docs
EOF

echo "✅ Archivo .env creado"
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║        🎉 CONFIGURACIÓN COMPLETADA EXITOSAMENTE        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Recursos Azure creados (TODOS GRATIS):"
echo "   ✅ Resource Group: $RESOURCE_GROUP"
echo "   ✅ Cosmos DB: $COSMOS_ACCOUNT"
echo "   ✅ AI Search: $SEARCH_SERVICE"
echo "   ✅ Speech Service: $SPEECH_SERVICE"
echo ""
echo "💰 Costos mensuales de Azure:"
echo "   - Cosmos DB: GRATIS (tier gratuito permanente)"
echo "   - AI Search: GRATIS (tier gratuito permanente)"
echo "   - Speech Service: GRATIS (primeras 5 horas/mes)"
echo ""
echo "   ⚡ TOTAL AZURE: \$0/mes"
echo ""
echo "🤗 Hugging Face (IA):"
echo "   - API gratuita sin límites"
echo "   - No requiere aprobación"
echo ""
echo "📝 SIGUIENTE PASO IMPORTANTE:"
echo "   1. Obtén tu token de Hugging Face:"
echo "      👉 https://huggingface.co/settings/tokens"
echo ""
echo "   2. Edita .env y agrega el token:"
echo "      nano .env"
echo "      Buscar: HUGGINGFACE_API_KEY=AGREGA_TU_TOKEN_AQUI"
echo "      Reemplazar con tu token real"
echo ""
echo "   3. Instalar dependencias Python:"
echo "      python3 -m venv venv"
echo "      source venv/bin/activate"
echo "      pip install -r requirements.txt"
echo ""
echo "   4. Indexar documentos:"
echo "      python index_documents.py"
echo ""
echo "   5. Iniciar backend Python:"
echo "      python app.py"
echo ""
echo "   6. En otra terminal, instalar dependencias Node:"
echo "      npm install"
echo ""
echo "   7. Iniciar servidor Node:"
echo "      npm start"
echo ""
echo "   8. Abrir navegador:"
echo "      http://localhost:3000"
echo ""
echo "🎉 ¡Listo para usar!"