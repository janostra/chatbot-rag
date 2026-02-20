#!/bin/bash

# Script para crear y deployar Azure Function
# Versión SIMPLIFICADA (sin copia temporal)

set -e

echo "⚡ Desplegando Azure Function para auto-indexación"

# Variables
RESOURCE_GROUP="rg-chatbot-rag"
LOCATION="eastus"
TIMESTAMP=$(date +%s)
FUNCTION_APP_NAME="func-indexer-${TIMESTAMP}"
STORAGE_ACCOUNT=""

echo ""
echo "📋 Configuración:"
echo "   Function App: $FUNCTION_APP_NAME"
echo "   Resource Group: $RESOURCE_GROUP"
echo ""

# Verificar login
echo "🔐 Verificando login en Azure..."
az account show &> /dev/null || az login

# Verificar y registrar provider Microsoft.Web
echo "🔍 Verificando provider Microsoft.Web..."
PROVIDER_STATE=$(az provider show --namespace Microsoft.Web --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")

if [ "$PROVIDER_STATE" != "Registered" ]; then
    echo "📝 Registrando Microsoft.Web (App Service)..."
    az provider register --namespace Microsoft.Web --output none
    
    echo "⏳ Esperando a que se complete el registro (puede tardar 2-3 min)..."
    
    COUNTER=0
    while [ $COUNTER -lt 60 ]; do
        PROVIDER_STATE=$(az provider show --namespace Microsoft.Web --query "registrationState" -o tsv)
        
        if [ "$PROVIDER_STATE" == "Registered" ]; then
            echo "✅ Microsoft.Web registrado correctamente"
            break
        fi
        
        echo "   Estado: $PROVIDER_STATE... (esperando)"
        sleep 5
        COUNTER=$((COUNTER + 1))
    done
    
    if [ "$PROVIDER_STATE" != "Registered" ]; then
        echo "⚠️  El registro está tardando más de lo normal"
        echo "   Puedes continuar, pero puede fallar. Verifica manualmente:"
        echo "   az provider show --namespace Microsoft.Web"
    fi
else
    echo "✅ Microsoft.Web ya está registrado"
fi

# Verificar que existe .env
if [ ! -f .env ]; then
    echo "❌ Error: No se encontró archivo .env"
    exit 1
fi

source .env

# Verificar que existe el storage account
if [ -z "$AZURE_STORAGE_ACCOUNT_NAME" ]; then
    echo "❌ Error: AZURE_STORAGE_ACCOUNT_NAME no está en .env"
    echo "   Ejecuta primero: ./infrastructure/setup-azure.sh"
    exit 1
fi

STORAGE_ACCOUNT=$AZURE_STORAGE_ACCOUNT_NAME

# ============================================
# VALIDAR ESTRUCTURA CORRECTA
# ============================================
echo "🔍 Validando estructura de Azure Functions..."

# Verificar que existe azure_functions/
if [ ! -d "azure_functions" ]; then
    echo "❌ Error: No se encontró carpeta azure_functions/"
    exit 1
fi

# Verificar estructura correcta
REQUIRED_FILES=(
    "azure_functions/host.json"
    "azure_functions/requirements.txt"
    "azure_functions/indexer_document/__init__.py"
    "azure_functions/indexer_document/function.json"
)

MISSING_FILES=()
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        MISSING_FILES+=("$file")
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo "❌ Error: Estructura incorrecta de Azure Functions"
    echo ""
    echo "   Archivos faltantes:"
    for file in "${MISSING_FILES[@]}"; do
        echo "   - $file"
    done
    echo ""
    echo "   Estructura esperada:"
    echo "   azure_functions/"
    echo "   ├── host.json              ← En la raíz"
    echo "   ├── requirements.txt       ← En la raíz"
    echo "   └── indexer_document/"
    echo "       ├── __init__.py"
    echo "       └── function.json"
    echo ""
    echo "   Ejecuta para reorganizar:"
    echo "   ./reorganize-functions.sh"
    exit 1
fi

echo "✅ Estructura correcta"

# 1. Crear Function App
echo "⚡ Creando Azure Function App..."

az functionapp create \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --consumption-plan-location $LOCATION \
  --runtime python \
  --runtime-version 3.11 \
  --functions-version 4 \
  --storage-account $STORAGE_ACCOUNT \
  --os-type Linux \
  --output none

echo "✅ Function App creado"

# 2. Configurar App Settings (variables de entorno)
echo "⚙️  Configurando variables de entorno..."

az functionapp config appsettings set \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --settings \
    AzureWebJobsStorage=$AZURE_STORAGE_CONNECTION_STRING \
    AZURE_SEARCH_ENDPOINT=$AZURE_SEARCH_ENDPOINT \
    AZURE_SEARCH_KEY=$AZURE_SEARCH_KEY \
    AZURE_SEARCH_INDEX=$AZURE_SEARCH_INDEX \
    APPINSIGHTS_INSTRUMENTATIONKEY=$APPINSIGHTS_INSTRUMENTATION_KEY \
    CosmosDBConnection=$MONGO_URI \
  --output none

echo "✅ Variables configuradas"

# 3. Habilitar Application Insights
echo "📊 Habilitando Application Insights..."

APPINSIGHTS_KEY=$(echo $APPINSIGHTS_CONNECTION_STRING | grep -o 'InstrumentationKey=[^;]*' | cut -d'=' -f2)

az functionapp config appsettings set \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --settings \
    APPINSIGHTS_INSTRUMENTATIONKEY=$APPINSIGHTS_KEY \
  --output none

echo "✅ Application Insights habilitado"

# ============================================
# 4. DEPLOY 
# ============================================
echo "📦 Deployando función..."

# Crear zip azure_functions/
cd azure_functions
zip -r ../function.zip . -x "*.pyc" -x "__pycache__/*" -x "*.git/*"
cd ..

# Deploy
az functionapp deployment source config-zip \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --src function.zip \
  --build-remote true \
  --output none

# Limpiar
rm function.zip

echo "✅ Función deployada"

# 5. Configurar trigger de Blob Storage
echo "🔗 Configurando blob trigger..."

# Verificar que existe el container (usando account-key en vez de connection string)
STORAGE_KEY=$(az storage account keys list \
  --account-name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query "[0].value" -o tsv)

az storage container create \
  --name documents \
  --account-name $STORAGE_ACCOUNT \
  --account-key "$STORAGE_KEY" \
  --public-access blob \
  --output none 2>/dev/null || true

# Obtener URL de la función
FUNCTION_URL=$(az functionapp show \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "defaultHostName" -o tsv)

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║      ⚡ AZURE FUNCTION DEPLOYADA                         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Información:"
echo "   Function App: $FUNCTION_APP_NAME"
echo "   URL: https://${FUNCTION_URL}"
echo ""
echo "🔔 Trigger configurado:"
echo "   • Container: documents"
echo "   • Storage Account: $STORAGE_ACCOUNT"
echo ""
echo "✅ ¿Cómo funciona?"
echo ""
echo "1️⃣  Usuario admin sube documento en /admin"
echo "2️⃣  Documento se guarda en Blob Storage (container: documents)"
echo "3️⃣  Azure Function detecta el nuevo archivo automáticamente"
echo "4️⃣  Function indexa el documento en Azure AI Search"
echo "5️⃣  Function actualiza Cosmos DB (indexed: true)"
echo "6️⃣  Usuario puede hacer preguntas sobre el nuevo documento"
echo ""
echo "📊 Monitoreo:"
echo "   Ver logs en tiempo real:"
echo "   az functionapp log tail -n $FUNCTION_APP_NAME -g $RESOURCE_GROUP"
echo ""
echo "   Ver en portal:"
echo "   https://portal.azure.com/#resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP_NAME/appServices"
echo ""
echo "💰 Costo:"
echo "   • Consumption Plan: GRATIS (1M ejecuciones/mes)"
echo "   • Solo pagas ejecuciones adicionales (~\$0.20 por 1M)"
echo ""
echo "🧪 Testing:"
echo "   Sube un archivo en /admin y revisa los logs:"
echo "   az functionapp log tail -n $FUNCTION_APP_NAME -g $RESOURCE_GROUP"
echo ""