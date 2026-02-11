#!/bin/bash

# Script para deployar a Azure App Service (SIN Docker)
# La forma más simple y económica de deployar en Azure

set -e

echo "🚀 Desplegando Chatbot RAG a Azure App Service"
echo ""

# Variables
RESOURCE_GROUP="rg-chatbot-rag"
LOCATION="westus3"
TIMESTAMP=$(date +%s)
APP_SERVICE_PLAN="plan-chatbot"
BACKEND_APP="chatbot-backend-${TIMESTAMP}"
FRONTEND_APP="chatbot-frontend-${TIMESTAMP}"

echo "📋 Configuración:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   App Service Plan: $APP_SERVICE_PLAN"
echo "   Backend App: $BACKEND_APP"
echo "   Frontend App: $FRONTEND_APP"
echo "   Tier: F1 (GRATIS) o B1 (\$13/mes)"
echo ""

# Preguntar tier
read -p "¿Usar tier GRATIS (F1) o BÁSICO (B1 - \$13/mes)? [F1/B1]: " TIER_CHOICE
TIER_CHOICE=${TIER_CHOICE:-F1}

if [ "$TIER_CHOICE" = "B1" ] || [ "$TIER_CHOICE" = "b1" ]; then
    TIER="B1"
    echo "✅ Usando tier B1 (Básico - \$13/mes, siempre activo)"
else
    TIER="F1"
    echo "✅ Usando tier F1 (GRATIS - 60 min/día CPU)"
fi

# Verificar login
echo ""
echo "🔐 Verificando login en Azure..."
az account show &> /dev/null || az login

# Verificar y registrar provider Microsoft.Web
echo "🔍 Verificando provider Microsoft.Web..."
PROVIDER_STATE=$(az provider show --namespace Microsoft.Web --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")

if [ "$PROVIDER_STATE" != "Registered" ]; then
    echo "📝 Registrando Microsoft.Web (App Service)..."
    az provider register --namespace Microsoft.Web --output none
    
    echo "⏳ Esperando a que se complete el registro (puede tardar 2-3 min)..."
    
    # Esperar hasta que esté registrado (timeout 5 minutos)
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

# Verificar .env
if [ ! -f .env ]; then
    echo "❌ Error: No se encontró .env"
    echo "   Ejecuta primero: ./infrastructure/setup-azure.sh"
    exit 1
fi

source .env

# Verificar variables críticas
MISSING_VARS=()
[ -z "$MONGO_URI" ] && MISSING_VARS+=("MONGO_URI")
[ -z "$SPEECH_KEY" ] && MISSING_VARS+=("SPEECH_KEY")
[ -z "$AZURE_SEARCH_ENDPOINT" ] && MISSING_VARS+=("AZURE_SEARCH_ENDPOINT")
[ -z "$AZURE_SEARCH_KEY" ] && MISSING_VARS+=("AZURE_SEARCH_KEY")
[ -z "$HUGGINGFACE_API_KEY" ] || [ "$HUGGINGFACE_API_KEY" = "AGREGA_TU_TOKEN_AQUI" ] && MISSING_VARS+=("HUGGINGFACE_API_KEY")

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo "❌ Faltan variables de entorno:"
    for var in "${MISSING_VARS[@]}"; do
        echo "   - $var"
    done
    exit 1
fi

echo "✅ Variables de entorno verificadas"

# ============================================
# 1. CREAR APP SERVICE PLAN
# ============================================
echo ""
echo "📦 Creando App Service Plan..."

# Verificar si ya existe
PLAN_EXISTS=$(az appservice plan show \
  --name $APP_SERVICE_PLAN \
  --resource-group $RESOURCE_GROUP \
  2>/dev/null || echo "")

if [ -z "$PLAN_EXISTS" ]; then
    az appservice plan create \
      --name $APP_SERVICE_PLAN \
      --resource-group $RESOURCE_GROUP \
      --location $LOCATION \
      --sku $TIER \
      --is-linux \
      --output none
    
    echo "✅ App Service Plan creado (Tier $TIER)"
else
    echo "✅ App Service Plan ya existe (usando existente)"
fi

# ============================================
# 2. CREAR BACKEND APP (Python)
# ============================================
echo ""
echo "🐍 Creando Backend App (Python FastAPI)..."

az webapp create \
  --name $BACKEND_APP \
  --resource-group $RESOURCE_GROUP \
  --plan $APP_SERVICE_PLAN \
  --runtime "PYTHON:3.11" \
  --output none

echo "✅ Backend App creada"

# Configurar variables de entorno del backend
echo "⚙️  Configurando variables de entorno (Backend)..."

az webapp config appsettings set \
  --name $BACKEND_APP \
  --resource-group $RESOURCE_GROUP \
  --settings \
    AZURE_SEARCH_ENDPOINT="$AZURE_SEARCH_ENDPOINT" \
    AZURE_SEARCH_KEY="$AZURE_SEARCH_KEY" \
    AZURE_SEARCH_INDEX="$AZURE_SEARCH_INDEX" \
    HUGGINGFACE_API_KEY="$HUGGINGFACE_API_KEY" \
    SCM_DO_BUILD_DURING_DEPLOYMENT="true" \
  --output none

echo "✅ Variables configuradas"

# Configurar startup command para Gunicorn + Uvicorn
echo "🔧 Configurando startup command..."

az webapp config set \
  --name $BACKEND_APP \
  --resource-group $RESOURCE_GROUP \
  --startup-file "gunicorn -w 2 -k uvicorn.workers.UvicornWorker app:app --bind 0.0.0.0:8000 --timeout 120" \
  --output none

echo "✅ Startup command configurado"

# Deploy código del backend
echo "📦 Desplegando código del backend..."

cd backend
zip -r ../backend-deploy.zip . \
  -x "venv/*" \
  -x "__pycache__/*" \
  -x "*.pyc" \
  -x ".pytest_cache/*" \
  -x "*.log"
cd ..

az webapp deployment source config-zip \
  --name $BACKEND_APP \
  --resource-group $RESOURCE_GROUP \
  --src backend-deploy.zip \
  --output none \
  --timeout 600

rm backend-deploy.zip

echo "✅ Backend deployado"

# Obtener URL del backend
BACKEND_URL="https://${BACKEND_APP}.azurewebsites.net"
echo "   Backend URL: $BACKEND_URL"

# Esperar a que el backend esté listo
echo "⏳ Esperando a que backend compile e inicie (esto puede tardar 2-3 min)..."
sleep 90

# ============================================
# 3. CREAR FRONTEND APP (Node.js)
# ============================================
echo ""
echo "📱 Creando Frontend App (Node.js Express)..."

az webapp create \
  --name $FRONTEND_APP \
  --resource-group $RESOURCE_GROUP \
  --plan $APP_SERVICE_PLAN \
  --runtime "NODE:20-lts" \
  --output none

echo "✅ Frontend App creada"

# Configurar variables de entorno del frontend
echo "⚙️  Configurando variables de entorno (Frontend)..."

# Preparar settings como array
SETTINGS=(
  "NODE_ENV=production"
  "PORT=8080"
  "RAG_ENDPOINT=$BACKEND_URL"
  "SPEECH_REGION=$SPEECH_REGION"
  "AZURE_SEARCH_ENDPOINT=$AZURE_SEARCH_ENDPOINT"
  "AZURE_SEARCH_INDEX=$AZURE_SEARCH_INDEX"
  "MONGO_URI=$MONGO_URI"
  "AZURE_SEARCH_KEY=$AZURE_SEARCH_KEY" 
  "SPEECH_KEY=$SPEECH_KEY"
  "HUGGINGFACE_API_KEY=$HUGGINGFACE_API_KEY"
  "AZURE_STORAGE_CONNECTION_STRING=$AZURE_STORAGE_CONNECTION_STRING"
  "AZURE_STORAGE_ACCOUNT_NAME=$AZURE_STORAGE_ACCOUNT_NAME"
  "APPINSIGHTS_CONNECTION_STRING=$APPINSIGHTS_CONNECTION_STRING"
  "APPINSIGHTS_INSTRUMENTATION_KEY=$APPINSIGHTS_INSTRUMENTATION_KEY"
  "ADMIN_USERNAME=${ADMIN_USERNAME:-admin}"
  "ADMIN_PASSWORD=${ADMIN_PASSWORD:-changeme123}"
  "SCM_DO_BUILD_DURING_DEPLOYMENT=true"
  "WEBSITE_NODE_DEFAULT_VERSION=20-lts"
)

# Agregar Key Vault si está configurado
if [ ! -z "$VAULT_URL" ]; then
    SETTINGS+=("VAULT_URL=$VAULT_URL")
fi

az webapp config appsettings set \
  --name $FRONTEND_APP \
  --resource-group $RESOURCE_GROUP \
  --settings "${SETTINGS[@]}" \
  --output none

echo "✅ Variables configuradas"

# Deploy código del frontend
echo "📦 Desplegando código del frontend..."

cd frontend
zip -r ../frontend-deploy.zip . \
  -x "node_modules/*" \
  -x ".git/*" \
  -x "*.log"
cd ..

az webapp deployment source config-zip \
  --name $FRONTEND_APP \
  --resource-group $RESOURCE_GROUP \
  --src frontend-deploy.zip \
  --output none \
  --timeout 600

rm frontend-deploy.zip

echo "✅ Frontend deployado"

# Obtener URL del frontend
FRONTEND_URL="https://${FRONTEND_APP}.azurewebsites.net"

# ============================================
# 4. HABILITAR LOGS Y MONITORING
# ============================================
echo ""
echo "📊 Habilitando logs y monitoring..."

# Backend logs
az webapp log config \
  --name $BACKEND_APP \
  --resource-group $RESOURCE_GROUP \
  --application-logging filesystem \
  --detailed-error-messages true \
  --failed-request-tracing true \
  --web-server-logging filesystem \
  --output none

# Frontend logs
az webapp log config \
  --name $FRONTEND_APP \
  --resource-group $RESOURCE_GROUP \
  --application-logging filesystem \
  --detailed-error-messages true \
  --failed-request-tracing true \
  --web-server-logging filesystem \
  --output none

echo "✅ Logs habilitados"

# ============================================
# 5. HABILITAR ALWAYS ON (solo para B1+)
# ============================================
if [ "$TIER" = "B1" ]; then
    echo "🔄 Habilitando Always On (tier B1)..."
    
    az webapp config set \
      --name $BACKEND_APP \
      --resource-group $RESOURCE_GROUP \
      --always-on true \
      --output none
    
    az webapp config set \
      --name $FRONTEND_APP \
      --resource-group $RESOURCE_GROUP \
      --always-on true \
      --output none
    
    echo "✅ Always On habilitado"
fi

# ============================================
# 6. HABILITAR HTTPS ONLY
# ============================================
echo "🔒 Habilitando HTTPS only..."

az webapp update \
  --name $BACKEND_APP \
  --resource-group $RESOURCE_GROUP \
  --https-only true \
  --output none

az webapp update \
  --name $FRONTEND_APP \
  --resource-group $RESOURCE_GROUP \
  --https-only true \
  --output none

echo "✅ HTTPS habilitado"

# ============================================
# 7. GUARDAR CONFIGURACIÓN
# ============================================
echo ""
echo "💾 Guardando configuración en deploy-info.txt..."

cat > deploy-info.txt << EOF
╔══════════════════════════════════════════════════════════╗
║         INFORMACIÓN DE DEPLOYMENT                        ║
╚══════════════════════════════════════════════════════════╝

📅 Fecha: $(date)
🏷️  Tier: $TIER

🌐 URLs:
   Usuario:  $FRONTEND_URL
   Admin:    $FRONTEND_URL/admin
   Backend:  $BACKEND_URL

📋 Recursos:
   Resource Group: $RESOURCE_GROUP
   App Service Plan: $APP_SERVICE_PLAN
   Backend App: $BACKEND_APP
   Frontend App: $FRONTEND_APP

🔐 Credenciales Admin:
   Usuario: ${ADMIN_USERNAME:-admin}
   Password: ${ADMIN_PASSWORD:-changeme123}

📊 Comandos útiles:

Ver logs en tiempo real:
   az webapp log tail -n $FRONTEND_APP -g $RESOURCE_GROUP
   az webapp log tail -n $BACKEND_APP -g $RESOURCE_GROUP

Reiniciar apps:
   az webapp restart -n $FRONTEND_APP -g $RESOURCE_GROUP
   az webapp restart -n $BACKEND_APP -g $RESOURCE_GROUP

Detener apps (para ahorrar):
   az webapp stop -n $FRONTEND_APP -g $RESOURCE_GROUP
   az webapp stop -n $BACKEND_APP -g $RESOURCE_GROUP

Iniciar apps:
   az webapp start -n $FRONTEND_APP -g $RESOURCE_GROUP
   az webapp start -n $BACKEND_APP -g $RESOURCE_GROUP

Actualizar tier:
   az appservice plan update --name $APP_SERVICE_PLAN --resource-group $RESOURCE_GROUP --sku B1

Ver en portal:
   https://portal.azure.com/#resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/overview

EOF

echo "✅ Información guardada en deploy-info.txt"

# ============================================
# RESULTADO FINAL
# ============================================
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       🎉 DEPLOYMENT COMPLETADO (APP SERVICE)            ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "🌐 URLs de acceso:"
echo ""
echo "   👥 Usuario:  $FRONTEND_URL"
echo "   🛠️  Admin:    $FRONTEND_URL/admin"
echo "   🔧 Backend:  $BACKEND_URL/health"
echo ""
echo "📋 Recursos creados:"
echo "   • App Service Plan: $APP_SERVICE_PLAN ($TIER)"
echo "   • Backend App: $BACKEND_APP (Python 3.11)"
echo "   • Frontend App: $FRONTEND_APP (Node.js 18)"
echo ""
echo "💰 Costos:"
if [ "$TIER" = "F1" ]; then
    echo "   • Tier F1: **GRATIS**"
    echo "     - Límites: 1GB RAM, 60 min/día CPU, 1GB disk"
    echo "     - Cold start: 10-30 segundos"
    echo "     - Se apaga tras 20 min sin uso"
else
    echo "   • Tier B1: \$13/mes (~\$0.018/hora)"
    echo "     - Recursos: 1.75GB RAM, 100 GB disk"
    echo "     - Always on: No cold start"
    echo "     - Siempre activo"
fi
echo ""
echo "🔐 Credenciales Admin (⚠️ cambiar en producción):"
echo "   Usuario: ${ADMIN_USERNAME:-admin}"
echo "   Password: ${ADMIN_PASSWORD:-changeme123}"
echo ""
echo "📊 Monitoreo:"
echo "   Application Insights: https://portal.azure.com"
echo "   Ver logs: az webapp log tail -n $FRONTEND_APP -g $RESOURCE_GROUP"
echo ""
echo "⏱️  Estado del deployment:"
echo "   • Backend está compilando (puede tardar 2-3 min)"
echo "   • Frontend está compilando (puede tardar 1-2 min)"
echo ""
echo "🧪 Verificar que está funcionando:"
echo "   curl $BACKEND_URL/health"
echo "   curl $FRONTEND_URL/health"
echo ""
echo "💡 Próximos pasos:"
echo "   1. Espera 2-3 minutos a que termine de compilar"
echo "   2. Abre $FRONTEND_URL en tu navegador"
echo "   3. Prueba el chat de usuario"
echo "   4. Accede al admin: $FRONTEND_URL/admin"
echo "   5. Deploy Azure Function: ./infrastructure/deploy-function.sh"
echo ""
echo "⚠️  IMPORTANTE:"
if [ "$TIER" = "F1" ]; then
    echo "   • F1 tiene cold start de 10-30 seg en primera carga"
    echo "   • Se apaga automáticamente tras 20 min sin uso"
    echo "   • Límite de 60 min/día de CPU"
    echo "   • Para producción real, considera actualizar a B1:"
    echo "     az appservice plan update --name $APP_SERVICE_PLAN --resource-group $RESOURCE_GROUP --sku B1"
fi
echo ""
echo "📄 Toda la info fue guardada en: deploy-info.txt"
echo ""