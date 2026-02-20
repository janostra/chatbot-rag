#!/bin/bash

# =============================================================
# setup-keyvault.sh
# Crea Azure Key Vault y migra secrets desde .env
#
# Uso:
#   ./infrastructure/setup-keyvault.sh
#
# Puede correrse ANTES o DESPUÉS de deploy-appservice.sh.
# Si las App Services ya existen, les asigna permisos automáticamente.
# Si no existen todavía, los permisos se asignan en deploy-appservice.sh.
# =============================================================

set -e

RESOURCE_GROUP="rg-chatbot-rag"
LOCATION="westus3"
TIMESTAMP=$(date +%s)
VAULT_NAME="kv-chatbot-${TIMESTAMP}"

echo "🔐 Configurando Azure Key Vault"
echo ""
echo "📋 Configuración:"
echo "   Resource Group : $RESOURCE_GROUP"
echo "   Key Vault      : $VAULT_NAME"
echo ""

# ── Verificar .env ──────────────────────────────────────────
if [ ! -f .env ]; then
    echo "❌ No se encontró archivo .env"
    echo "   Ejecuta primero: ./infrastructure/setup-azure.sh"
    exit 1
fi

source .env

# ── Login ───────────────────────────────────────────────────
echo "🔐 Verificando login en Azure..."
az account show &>/dev/null || az login

# ── Crear Key Vault ─────────────────────────────────────────
echo "🏗️  Creando Key Vault..."
az keyvault create \
    --name "$VAULT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --enable-rbac-authorization false \
    --output none

echo "✅ Key Vault creado: $VAULT_NAME"
VAULT_URL="https://${VAULT_NAME}.vault.azure.net/"

# ── Permisos para el usuario actual (dev local) ──────────────
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
az keyvault set-policy \
    --name "$VAULT_NAME" \
    --object-id "$USER_OBJECT_ID" \
    --secret-permissions get list set delete \
    --output none
echo "✅ Permisos configurados para usuario local"

# ── Migrar secrets al Vault ──────────────────────────────────
echo ""
echo "🔄 Migrando secrets desde .env..."

migrate_secret() {
    local vault="$1"
    local secret_name="$2"
    local secret_value="$3"
    local skip_pattern="${4:-}"

    if [ -z "$secret_value" ]; then
        echo "   ⚠️  $secret_name vacío, saltando"
        return
    fi
    if [ -n "$skip_pattern" ] && echo "$secret_value" | grep -q "$skip_pattern"; then
        echo "   ⚠️  $secret_name tiene valor placeholder, saltando"
        return
    fi
    az keyvault secret set \
        --vault-name "$vault" \
        --name "$secret_name" \
        --value "$secret_value" \
        --output none
    echo "   ✅ $secret_name"
}

migrate_secret "$VAULT_NAME" "MONGO-URI"              "$MONGO_URI"
migrate_secret "$VAULT_NAME" "SPEECH-KEY"             "$SPEECH_KEY"
migrate_secret "$VAULT_NAME" "AZURE-SEARCH-KEY"       "$AZURE_SEARCH_KEY"
migrate_secret "$VAULT_NAME" "HUGGINGFACE-API-KEY"    "$HUGGINGFACE_API_KEY"   "AGREGA_TU"
migrate_secret "$VAULT_NAME" "STORAGE-CONNECTION"     "$AZURE_STORAGE_CONNECTION_STRING"
migrate_secret "$VAULT_NAME" "ADMIN-USERNAME"         "${ADMIN_USERNAME:-admin}"
migrate_secret "$VAULT_NAME" "ADMIN-PASSWORD"         "${ADMIN_PASSWORD:-changeme123}"

# ── Conectar App Services existentes (si ya fueron deployadas) ─
echo ""
echo "🔍 Buscando App Services deployadas..."

connect_app_to_vault() {
    local app_name="$1"
    local vault="$2"

    if [ -z "$app_name" ]; then return; fi

    echo "   🪪 Asignando Managed Identity a $app_name..."
    az webapp identity assign \
        --name "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --output none 2>/dev/null || true

    local principal_id
    principal_id=$(az webapp identity show \
        --name "$app_name" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId -o tsv 2>/dev/null || echo "")

    if [ -n "$principal_id" ]; then
        az keyvault set-policy \
            --name "$vault" \
            --object-id "$principal_id" \
            --secret-permissions get list \
            --output none
        echo "   ✅ $app_name conectado al vault"
    else
        echo "   ⚠️  No se pudo obtener identity de $app_name"
    fi
}

FRONTEND_APP=$(az webapp list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?contains(name, 'chatbot-frontend')].name | [0]" -o tsv 2>/dev/null || echo "")

BACKEND_APP=$(az webapp list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?contains(name, 'chatbot-backend')].name | [0]" -o tsv 2>/dev/null || echo "")

if [ -n "$FRONTEND_APP" ]; then
    connect_app_to_vault "$FRONTEND_APP" "$VAULT_NAME"
fi
if [ -n "$BACKEND_APP" ]; then
    connect_app_to_vault "$BACKEND_APP" "$VAULT_NAME"
fi

if [ -z "$FRONTEND_APP" ] && [ -z "$BACKEND_APP" ]; then
    echo "   ℹ️  No hay App Services deployadas aún."
    echo "      Cuando corras deploy-appservice.sh, el script detectará"
    echo "      el VAULT_URL del .env y conectará las apps automáticamente."
fi

# ── Actualizar .env con VAULT_URL ────────────────────────────
echo ""
echo "📝 Actualizando .env con VAULT_URL..."

if grep -q "^VAULT_URL=" .env; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|^VAULT_URL=.*|VAULT_URL=$VAULT_URL|" .env
    else
        sed -i "s|^VAULT_URL=.*|VAULT_URL=$VAULT_URL|" .env
    fi
else
    echo "" >> .env
    echo "# Azure Key Vault" >> .env
    echo "VAULT_URL=$VAULT_URL" >> .env
fi

echo "✅ .env actualizado con VAULT_URL=$VAULT_URL"

# ── Resumen ──────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              🔐 KEY VAULT CONFIGURADO                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "   Vault URL : $VAULT_URL"
echo ""
echo "📌 Secrets almacenados:"
echo "   MONGO-URI · SPEECH-KEY · AZURE-SEARCH-KEY"
echo "   HUGGINGFACE-API-KEY · STORAGE-CONNECTION"
echo "   ADMIN-USERNAME · ADMIN-PASSWORD"
echo ""
echo "🚀 Próximo paso:"
echo "   Si aún no deployaste: ./infrastructure/deploy-appservice.sh"
echo "   (Detectará VAULT_URL y conectará las apps automáticamente)"
echo ""
echo "💡 Para desarrollo local sin vault:"
echo "   Comentá o borrá la línea VAULT_URL= del .env"
echo "   El server caerá a leer las variables directamente del .env"
echo ""