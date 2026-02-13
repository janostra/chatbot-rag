#!/bin/bash

# Script para crear y configurar Azure Key Vault
# Migra todos los secrets desde .env a Key Vault

set -e

echo "🔐 Configurando Azure Key Vault..."

# Variables
RESOURCE_GROUP="rg-chatbot-rag"
LOCATION="westus3"
TIMESTAMP=$(date +%s)
VAULT_NAME="kv-chatbot-${TIMESTAMP}"

# Verificar que existe .env
if [ ! -f .env ]; then
    echo "❌ Error: No se encontró archivo .env"
    echo "   Ejecuta primero: ./infrastructure/setup-azure.sh"
    exit 1
fi

echo ""
echo "📋 Configuración:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Key Vault: $VAULT_NAME"
echo ""

# Login
echo "🔐 Verificando login en Azure..."
az account show &> /dev/null || az login

# Crear Key Vault
echo "🏗️  Creando Key Vault..."
az keyvault create \
  --name $VAULT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --enable-rbac-authorization false \
  --output none

echo "✅ Key Vault creado: $VAULT_NAME"

# Obtener usuario actual para permisos
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

az keyvault set-policy \
  --name $VAULT_NAME \
  --object-id $USER_OBJECT_ID \
  --secret-permissions get list set delete \
  --output none

echo "✅ Permisos configurados para usuario actual"

# Buscar App Services deployadas (frontend y backend)
echo "🔍 Buscando App Services deployadas..."
FRONTEND_APP=$(az webapp list \
  --resource-group $RESOURCE_GROUP \
  --query "[?contains(name, 'chatbot-frontend')].name | [0]" -o tsv 2>/dev/null || echo "")

BACKEND_APP=$(az webapp list \
  --resource-group $RESOURCE_GROUP \
  --query "[?contains(name, 'chatbot-backend')].name | [0]" -o tsv 2>/dev/null || echo "")

# Configurar Managed Identity para las apps si existen
if [ ! -z "$FRONTEND_APP" ]; then
    echo "🪪 Activando Managed Identity en $FRONTEND_APP..."
    az webapp identity assign \
      --name $FRONTEND_APP \
      --resource-group $RESOURCE_GROUP \
      --output none 2>/dev/null || true
    
    FRONTEND_PRINCIPAL_ID=$(az webapp identity show \
      --name $FRONTEND_APP \
      --resource-group $RESOURCE_GROUP \
      --query principalId -o tsv 2>/dev/null || echo "")
    
    if [ ! -z "$FRONTEND_PRINCIPAL_ID" ]; then
        az keyvault set-policy \
          --name $VAULT_NAME \
          --object-id $FRONTEND_PRINCIPAL_ID \
          --secret-permissions get list \
          --output none
        echo "   ✅ Permisos configurados para $FRONTEND_APP"
    fi
fi

if [ ! -z "$BACKEND_APP" ]; then
    echo "🪪 Activando Managed Identity en $BACKEND_APP..."
    az webapp identity assign \
      --name $BACKEND_APP \
      --resource-group $RESOURCE_GROUP \
      --output none 2>/dev/null || true
    
    BACKEND_PRINCIPAL_ID=$(az webapp identity show \
      --name $BACKEND_APP \
      --resource-group $RESOURCE_GROUP \
      --query principalId -o tsv 2>/dev/null || echo "")
    
    if [ ! -z "$BACKEND_PRINCIPAL_ID" ]; then
        az keyvault set-policy \
          --name $VAULT_NAME \
          --object-id $BACKEND_PRINCIPAL_ID \
          --secret-permissions get list \
          --output none
        echo "   ✅ Permisos configurados para $BACKEND_APP"
    fi
fi

if [ -z "$FRONTEND_APP" ] && [ -z "$BACKEND_APP" ]; then
    echo "⚠️  No se encontraron App Services deployadas"
    echo "   Puedes configurar permisos más tarde con:"
    echo "   az webapp identity assign --name <APP_NAME> --resource-group $RESOURCE_GROUP"
fi

# Cargar .env
echo "📦 Cargando secrets desde .env..."
source .env

# Migrar secrets a Key Vault
echo "🔄 Migrando secrets..."

if [ ! -z "$MONGO_URI" ]; then
    az keyvault secret set --vault-name $VAULT_NAME --name "MONGO-URI" --value "$MONGO_URI" --output none
    echo "   ✅ MONGO-URI"
fi

if [ ! -z "$SPEECH_KEY" ]; then
    az keyvault secret set --vault-name $VAULT_NAME --name "SPEECH-KEY" --value "$SPEECH_KEY" --output none
    echo "   ✅ SPEECH-KEY"
fi

if [ ! -z "$AZURE_SEARCH_KEY" ]; then
    az keyvault secret set --vault-name $VAULT_NAME --name "AZURE-SEARCH-KEY" --value "$AZURE_SEARCH_KEY" --output none
    echo "   ✅ AZURE-SEARCH-KEY"
fi

if [ ! -z "$HUGGINGFACE_API_KEY" ] && [ "$HUGGINGFACE_API_KEY" != "AGREGA_TU_TOKEN_AQUI" ]; then
    az keyvault secret set --vault-name $VAULT_NAME --name "HUGGINGFACE-API-KEY" --value "$HUGGINGFACE_API_KEY" --output none
    echo "   ✅ HUGGINGFACE-API-KEY"
fi

if [ ! -z "$AZURE_STORAGE_CONNECTION_STRING" ]; then
    az keyvault secret set --vault-name $VAULT_NAME --name "STORAGE-CONNECTION" --value "$AZURE_STORAGE_CONNECTION_STRING" --output none
    echo "   ✅ STORAGE-CONNECTION"
fi

echo "✅ Secrets migrados a Key Vault"

# Actualizar .env con VAULT_URL
VAULT_URL="https://${VAULT_NAME}.vault.azure.net/"

echo ""
echo "📝 Actualizando .env con VAULT_URL..."

# Agregar o actualizar VAULT_URL en .env
if grep -q "^VAULT_URL=" .env; then
    # Actualizar existente (compatible con macOS y Linux)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|^VAULT_URL=.*|VAULT_URL=$VAULT_URL|" .env
    else
        sed -i "s|^VAULT_URL=.*|VAULT_URL=$VAULT_URL|" .env
    fi
else
    # Agregar nueva línea
    echo "" >> .env
    echo "# Azure Key Vault (generado por setup-keyvault.sh)" >> .env
    echo "VAULT_URL=$VAULT_URL" >> .env
fi

echo "✅ .env actualizado"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           🎉 KEY VAULT CONFIGURADO                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Información:"
echo "   Vault Name: $VAULT_NAME"
echo "   Vault URL: $VAULT_URL"
echo ""
echo "🔐 Secrets almacenados:"
echo "   • MONGO-URI"
echo "   • SPEECH-KEY"
echo "   • AZURE-SEARCH-KEY"
echo "   • HUGGINGFACE-API-KEY"
echo "   • STORAGE-CONNECTION"
echo ""
echo "🪪 Managed Identity configurada para:"
if [ ! -z "$FRONTEND_APP" ]; then
    echo "   • $FRONTEND_APP"
fi
if [ ! -z "$BACKEND_APP" ]; then
    echo "   • $BACKEND_APP"
fi
echo ""
echo "📝 Próximos pasos:"
echo ""
echo "1️⃣  Los secrets ya están en Key Vault"
echo "2️⃣  El archivo .env fue actualizado con VAULT_URL"
echo "3️⃣  Al deployar nuevas apps a Azure, configura Managed Identity:"
echo "   az webapp identity assign --name <APP_NAME> --resource-group $RESOURCE_GROUP"
echo "   az keyvault set-policy --name $VAULT_NAME --object-id <PRINCIPAL_ID> --secret-permissions get list"
echo ""
echo "💡 Para acceso local:"
echo "   - Asegúrate de estar logueado: az login"
echo "   - El código usará DefaultAzureCredential (CLI credential)"
echo ""
echo "🔍 Ver secrets en portal:"
echo "   https://portal.azure.com/#resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$VAULT_NAME/secrets"
echo ""