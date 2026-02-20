#!/bin/bash

# =============================================================
# deploy-appservice.sh
# Deploya backend Python (FastAPI) y frontend Node.js (Express)
# en Azure App Service.
#
# Uso:
#   ./infrastructure/deploy-appservice.sh
#
# Si ya corriste setup-keyvault.sh y hay un VAULT_URL en .env,
# este script asigna Managed Identity a las apps y les da
# acceso al vault automáticamente, sin pasos manuales extra.
#
# Si no usás Key Vault, dejá VAULT_URL vacío o sin definir
# en .env — el servidor usará las variables directamente.
# =============================================================

set -e

echo "🚀 Desplegando Chatbot RAG a Azure App Service"
echo ""

RESOURCE_GROUP="rg-chatbot-rag"
LOCATION="westus3"
TIMESTAMP=$(date +%s)
APP_SERVICE_PLAN="plan-chatbot"
BACKEND_APP="chatbot-backend-${TIMESTAMP}"
FRONTEND_APP="chatbot-frontend-${TIMESTAMP}"

echo "📋 Configuración:"
echo "   Resource Group    : $RESOURCE_GROUP"
echo "   App Service Plan  : $APP_SERVICE_PLAN"
echo "   Backend App       : $BACKEND_APP"
echo "   Frontend App      : $FRONTEND_APP"
echo ""

# ── Tier ────────────────────────────────────────────────────
read -p "¿Usar tier GRATIS (F1) o BÁSICO (B1 - \$13/mes)? [F1/B1]: " TIER_CHOICE
TIER_CHOICE=${TIER_CHOICE:-F1}
if [[ "${TIER_CHOICE^^}" == "B1" ]]; then
    TIER="B1"; echo "✅ Tier B1 (Básico - siempre activo)"
else
    TIER="F1"; echo "✅ Tier F1 (Gratis - 60 min/día CPU)"
fi

# ── Login ───────────────────────────────────────────────────
echo ""
echo "🔐 Verificando login en Azure..."
az account show &>/dev/null || az login

# ── Microsoft.Web provider ──────────────────────────────────
echo "🔍 Verificando provider Microsoft.Web..."
PROVIDER_STATE=$(az provider show --namespace Microsoft.Web --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
if [ "$PROVIDER_STATE" != "Registered" ]; then
    echo "📝 Registrando Microsoft.Web..."
    az provider register --namespace Microsoft.Web --output none
    for i in $(seq 1 60); do
        PROVIDER_STATE=$(az provider show --namespace Microsoft.Web --query "registrationState" -o tsv)
        [ "$PROVIDER_STATE" == "Registered" ] && break
        echo "   [$i/60] $PROVIDER_STATE... esperando"
        sleep 5
    done
fi
echo "✅ Microsoft.Web registrado"

# ── Verificar .env ──────────────────────────────────────────
if [ ! -f .env ]; then
    echo "❌ No se encontró .env"
    echo "   Ejecuta primero: ./infrastructure/setup-azure.sh"
    exit 1
fi
source .env

# ── Validar variables críticas ───────────────────────────────
MISSING_VARS=()
[ -z "$MONGO_URI" ]                && MISSING_VARS+=("MONGO_URI")
[ -z "$SPEECH_KEY" ]               && MISSING_VARS+=("SPEECH_KEY")
[ -z "$AZURE_SEARCH_ENDPOINT" ]    && MISSING_VARS+=("AZURE_SEARCH_ENDPOINT")
[ -z "$AZURE_SEARCH_KEY" ]         && MISSING_VARS+=("AZURE_SEARCH_KEY")
[ -z "$HUGGINGFACE_API_KEY" ] || \
  [[ "$HUGGINGFACE_API_KEY" == *"AGREGA"* ]] && MISSING_VARS+=("HUGGINGFACE_API_KEY")

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo "❌ Faltan variables de entorno:"
    for v in "${MISSING_VARS[@]}"; do echo "   - $v"; done
    exit 1
fi
echo "✅ Variables de entorno verificadas"

# ── Detectar si hay Key Vault configurado ────────────────────
USE_KEY_VAULT=false
if [ -n "$VAULT_URL" ] && [[ "$VAULT_URL" == https://* ]]; then
    USE_KEY_VAULT=true
    # Extraer nombre del vault desde la URL
    VAULT_NAME=$(echo "$VAULT_URL" | sed 's|https://||' | sed 's|.vault.azure.net/||')
    echo "🔐 Key Vault detectado: $VAULT_NAME"
    echo "   Las apps se conectarán automáticamente al vault."
else
    echo "💡 Key Vault no configurado → usando variables directas del .env"
    echo "   (Para usar Key Vault: corré setup-keyvault.sh primero)"
fi

# ── App Service Plan ─────────────────────────────────────────
echo ""
echo "📦 Verificando App Service Plan..."
PLAN_EXISTS=$(az appservice plan show \
    --name "$APP_SERVICE_PLAN" \
    --resource-group "$RESOURCE_GROUP" \
    2>/dev/null || echo "")

if [ -z "$PLAN_EXISTS" ]; then
    az appservice plan create \
        --name "$APP_SERVICE_PLAN" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku "$TIER" \
        --is-linux \
        --output none
    echo "✅ App Service Plan creado ($TIER)"
else
    echo "✅ App Service Plan ya existe"
fi

# ════════════════════════════════════════════════════════════
# BACKEND (Python / FastAPI)
# ════════════════════════════════════════════════════════════
echo ""
echo "🐍 Creando Backend App (Python FastAPI)..."
az webapp create \
    --name "$BACKEND_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$APP_SERVICE_PLAN" \
    --runtime "PYTHON:3.11" \
    --output none
echo "✅ Backend App creada"

echo "⚙️  Configurando variables del backend..."
az webapp config appsettings set \
    --name "$BACKEND_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
        AZURE_SEARCH_ENDPOINT="$AZURE_SEARCH_ENDPOINT" \
        AZURE_SEARCH_KEY="$AZURE_SEARCH_KEY" \
        AZURE_SEARCH_INDEX="${AZURE_SEARCH_INDEX:-travel-docs}" \
        HUGGINGFACE_API_KEY="$HUGGINGFACE_API_KEY" \
        USE_LOCAL_EMBEDDINGS="false" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="true" \
    --output none

az webapp config set \
    --name "$BACKEND_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --startup-file "gunicorn -w 2 -k uvicorn.workers.UvicornWorker app:app --bind 0.0.0.0:8000 --timeout 120" \
    --output none
echo "✅ Backend configurado"

echo "📦 Desplegando código del backend..."
cd backend
zip -r ../backend-deploy.zip . \
    -x "venv/*" -x "__pycache__/*" -x "*.pyc" -x ".pytest_cache/*" -x "*.log"
cd ..
az webapp deployment source config-zip \
    --name "$BACKEND_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --src backend-deploy.zip \
    --output none \
    --timeout 600
rm backend-deploy.zip
echo "✅ Backend deployado"

BACKEND_URL="https://${BACKEND_APP}.azurewebsites.net"
echo "   Backend URL: $BACKEND_URL"

# ── Managed Identity para Backend (si hay Key Vault) ─────────
if [ "$USE_KEY_VAULT" = true ]; then
    echo "🔐 Conectando backend al Key Vault..."
    az webapp identity assign \
        --name "$BACKEND_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --output none
    BACKEND_PRINCIPAL=$(az webapp identity show \
        --name "$BACKEND_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId -o tsv)
    az keyvault set-policy \
        --name "$VAULT_NAME" \
        --object-id "$BACKEND_PRINCIPAL" \
        --secret-permissions get list \
        --output none
    echo "✅ Backend conectado al Key Vault"
fi

echo "⏳ Esperando que el backend compile (2-3 min)..."
sleep 90

# ════════════════════════════════════════════════════════════
# FRONTEND (Node.js / Express)
# ════════════════════════════════════════════════════════════
echo ""
echo "📱 Creando Frontend App (Node.js Express)..."
az webapp create \
    --name "$FRONTEND_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$APP_SERVICE_PLAN" \
    --runtime "NODE:20-lts" \
    --output none
echo "✅ Frontend App creada"

echo "⚙️  Configurando variables del frontend..."

# Armar array de settings
SETTINGS=(
    "NODE_ENV=production"
    "PORT=8080"
    "RAG_ENDPOINT=$BACKEND_URL"
    "SPEECH_REGION=${SPEECH_REGION:-westus3}"
    "AZURE_SEARCH_ENDPOINT=$AZURE_SEARCH_ENDPOINT"
    "AZURE_SEARCH_INDEX=${AZURE_SEARCH_INDEX:-travel-docs}"
    "APPINSIGHTS_CONNECTION_STRING=${APPINSIGHTS_CONNECTION_STRING:-}"
    "APPINSIGHTS_INSTRUMENTATION_KEY=${APPINSIGHTS_INSTRUMENTATION_KEY:-}"
    "WEBSITE_NODE_DEFAULT_VERSION=20-lts"
    "SCM_DO_BUILD_DURING_DEPLOYMENT=true"
)

# Si hay Key Vault, sólo pasar VAULT_URL (los secrets vienen del vault)
# Si NO hay Key Vault, pasar todo directamente
if [ "$USE_KEY_VAULT" = true ]; then
    SETTINGS+=("VAULT_URL=$VAULT_URL")
    echo "   🔐 Modo Key Vault: secrets no se pasan como variables planas"
else
    SETTINGS+=(
        "MONGO_URI=$MONGO_URI"
        "SPEECH_KEY=$SPEECH_KEY"
        "AZURE_SEARCH_KEY=$AZURE_SEARCH_KEY"
        "HUGGINGFACE_API_KEY=$HUGGINGFACE_API_KEY"
        "AZURE_STORAGE_CONNECTION_STRING=${AZURE_STORAGE_CONNECTION_STRING:-}"
        "AZURE_STORAGE_ACCOUNT_NAME=${AZURE_STORAGE_ACCOUNT_NAME:-}"
        "ADMIN_USERNAME=${ADMIN_USERNAME:-admin}"
        "ADMIN_PASSWORD=${ADMIN_PASSWORD:-changeme123}"
    )
    echo "   💡 Modo .env: secrets pasados como variables de entorno"
fi

az webapp config appsettings set \
    --name "$FRONTEND_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --settings "${SETTINGS[@]}" \
    --output none
echo "✅ Frontend configurado"

echo "📦 Desplegando código del frontend..."
cd frontend
zip -r ../frontend-deploy.zip . \
    -x "node_modules/*" -x ".git/*" -x "*.log"
cd ..
az webapp deployment source config-zip \
    --name "$FRONTEND_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --src frontend-deploy.zip \
    --output none \
    --timeout 600
rm frontend-deploy.zip
echo "✅ Frontend deployado"

# ── Managed Identity para Frontend (si hay Key Vault) ────────
if [ "$USE_KEY_VAULT" = true ]; then
    echo "🔐 Conectando frontend al Key Vault..."
    az webapp identity assign \
        --name "$FRONTEND_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --output none
    FRONTEND_PRINCIPAL=$(az webapp identity show \
        --name "$FRONTEND_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId -o tsv)
    az keyvault set-policy \
        --name "$VAULT_NAME" \
        --object-id "$FRONTEND_PRINCIPAL" \
        --secret-permissions get list \
        --output none
    echo "✅ Frontend conectado al Key Vault"
fi

FRONTEND_URL="https://${FRONTEND_APP}.azurewebsites.net"

# ── Logs y HTTPS ─────────────────────────────────────────────
echo ""
echo "📊 Habilitando logs..."
for APP in "$BACKEND_APP" "$FRONTEND_APP"; do
    az webapp log config \
        --name "$APP" \
        --resource-group "$RESOURCE_GROUP" \
        --application-logging filesystem \
        --detailed-error-messages true \
        --failed-request-tracing true \
        --web-server-logging filesystem \
        --output none
    az webapp update \
        --name "$APP" \
        --resource-group "$RESOURCE_GROUP" \
        --https-only true \
        --output none
done
echo "✅ Logs y HTTPS habilitados"

# ── Always On (solo B1+) ─────────────────────────────────────
if [ "$TIER" = "B1" ]; then
    echo "🔄 Habilitando Always On (B1)..."
    for APP in "$BACKEND_APP" "$FRONTEND_APP"; do
        az webapp config set \
            --name "$APP" \
            --resource-group "$RESOURCE_GROUP" \
            --always-on true \
            --output none
    done
    echo "✅ Always On habilitado"
fi

# ── Guardar info de deployment ───────────────────────────────
cat > deploy-info.txt <<EOF
╔══════════════════════════════════════════════════════════╗
║               INFORMACIÓN DE DEPLOYMENT                  ║
╚══════════════════════════════════════════════════════════╝

Fecha         : $(date)
Tier          : $TIER
Key Vault     : $([ "$USE_KEY_VAULT" = true ] && echo "$VAULT_URL" || echo "No configurado")

🌐 URLs:
   Usuario   : $FRONTEND_URL
   Admin     : $FRONTEND_URL/admin
   Backend   : $BACKEND_URL

📋 Recursos:
   Backend   : $BACKEND_APP
   Frontend  : $FRONTEND_APP
   Plan      : $APP_SERVICE_PLAN

🔐 Admin (cambiar en producción):
   Usuario   : ${ADMIN_USERNAME:-admin}
   Password  : ${ADMIN_PASSWORD:-changeme123}

📊 Logs en tiempo real:
   az webapp log tail -n $FRONTEND_APP -g $RESOURCE_GROUP
   az webapp log tail -n $BACKEND_APP  -g $RESOURCE_GROUP

🔄 Reiniciar:
   az webapp restart -n $FRONTEND_APP -g $RESOURCE_GROUP
   az webapp restart -n $BACKEND_APP  -g $RESOURCE_GROUP

💡 Cambiar tier a B1:
   az appservice plan update --name $APP_SERVICE_PLAN --resource-group $RESOURCE_GROUP --sku B1

🗑️  Eliminar todo:
   az group delete -n $RESOURCE_GROUP --yes --no-wait
EOF

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           🎉 DEPLOYMENT COMPLETADO                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "   👥 Usuario  : $FRONTEND_URL"
echo "   🛠️  Admin    : $FRONTEND_URL/admin"
echo "   🔧 Backend  : $BACKEND_URL/health"
echo ""
if [ "$USE_KEY_VAULT" = true ]; then
echo "   🔐 Secrets  : Azure Key Vault ($VAULT_NAME)"
else
echo "   💡 Secrets  : Variables de entorno directas (.env)"
fi
echo ""
echo "⏳ El backend puede tardar 2-3 min en estar listo."
echo "📄 Info guardada en deploy-info.txt"
echo ""