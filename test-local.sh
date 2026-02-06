#!/bin/bash

# Script para testing local rápido
# Verifica que todo funcione antes de deployar

set -e

echo "🧪 Testing local del proyecto (App Service version)"
echo ""

# Verificar .env
if [ ! -f .env ]; then
    echo "❌ No se encontró .env"
    echo "   Ejecuta: ./infrastructure/setup-azure.sh"
    exit 1
fi

echo "✅ Archivo .env encontrado"

# Cargar .env
set -a
source ".env"
set +a

# Verificar variables críticas
echo "🔍 Verificando variables de entorno..."

REQUIRED_VARS=(
    "MONGO_URI"
    "SPEECH_KEY"
    "AZURE_SEARCH_ENDPOINT"
    "AZURE_SEARCH_KEY"
    "HUGGINGFACE_API_KEY"
)

MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ] || [ "${!var}" == "AGREGA_TU_TOKEN_AQUI" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo "❌ Faltan variables de entorno:"
    for var in "${MISSING_VARS[@]}"; do
        echo "   - $var"
    done
    exit 1
fi

echo "✅ Variables de entorno OK"

# Verificar Node.js
echo "🔍 Verificando Node.js..."
if ! command -v node &> /dev/null; then
    echo "❌ Node.js no está instalado"
    exit 1
fi
NODE_VERSION=$(node -v)
echo "✅ Node.js $NODE_VERSION"

# Verificar Python
echo "🔍 Verificando Python..."
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 no está instalado"
    exit 1
fi
PYTHON_VERSION=$(python3 --version)
echo "✅ $PYTHON_VERSION"

# Verificar dependencias Python
echo "🔍 Verificando backend Python..."
if [ ! -d backend/venv ]; then
    echo "⚠️  Virtual env no encontrado, creando..."
    cd backend
    python3 -m venv venv
    source venv/bin/activate
    pip install -q -r requirements.txt
    cd ..
    echo "✅ Virtual env creado"
else
    echo "✅ Virtual env existe"
fi

# Verificar gunicorn
cd backend
source venv/bin/activate
if ! python -c "import gunicorn" &> /dev/null; then
    echo "⚠️  Gunicorn no encontrado, instalando..."
    pip install -q gunicorn
fi
echo "✅ Gunicorn instalado"
deactivate
cd ..

# Verificar dependencias Node
echo "🔍 Verificando backend Node.js..."
if [ ! -d frontend/node_modules ]; then
    echo "⚠️  node_modules no encontrado, instalando..."
    cd frontend
    npm install --silent
    cd ..
    echo "✅ Dependencias instaladas"
else
    echo "✅ node_modules existe"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          ✅ TODO LISTO PARA TESTING LOCAL                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "🚀 Para iniciar en local:"
echo ""
echo "Terminal 1 - Backend Python:"
echo "   cd backend"
echo "   source venv/bin/activate"
echo "   python app.py"
echo ""
echo "Terminal 2 - Frontend Node.js:"
echo "   cd frontend"
echo "   npm start"
echo ""
echo "🌐 URLs locales:"
echo "   Usuario:  http://localhost:3000"
echo "   Admin:    http://localhost:3000/admin"
echo "   Backend:  http://localhost:8000"
echo "   Health:   http://localhost:8000/health"
echo ""
echo "🔐 Credenciales Admin:"
echo "   Usuario: ${ADMIN_USERNAME:-admin}"
echo "   Password: ${ADMIN_PASSWORD:-changeme123}"
echo ""
echo "☁️  Para deployar a Azure:"
echo "   ./infrastructure/deploy-appservice.sh"
echo ""