#!/usr/bin/env bash
# health_check.sh — script de ejemplo para verificar entorno y correr tests.
#
# INSTRUCCIONES DE USO:
#   1. Copia este archivo a la raíz de tu proyecto como `init.sh`
#   2. Ajusta las secciones marcadas con "# ADAPTAR:" según tu stack
#   3. Apunta la variable INIT_SCRIPT en el pipeline a ese archivo:
#        export INIT_SCRIPT="/ruta/a/tu-proyecto/init.sh"
#
# Contrato:
#   exit 0 → entorno OK y tests pasan (gate_merge lo interpreta como sin bloqueantes)
#   exit 1 → algo falla (gate_merge lo interpreta como bloqueante real)
#
# Dependencias: solo bash estándar. Agrega las tuyas en la sección de checks.
set -euo pipefail

# ── Colores para salida legible ───────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # sin color

ok()   { echo -e "${GREEN}✓${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

echo ""
echo "=== health_check.sh — verificación de entorno y tests ==="
echo ""

FAILED=0

# ── 1. Dependencias del sistema ───────────────────────────────────────
# ADAPTAR: agrega o quita comandos según tu stack.
echo "--- Dependencias del sistema ---"

REQUIRED_CMDS=(
  # "node"      # Node.js / npm
  # "python3"   # Python
  # "go"        # Go
  # "cargo"     # Rust
  # "docker"    # Docker
  "bash"
  "git"
)

for cmd in "${REQUIRED_CMDS[@]}"; do
  if command -v "$cmd" &>/dev/null; then
    ok "$cmd disponible ($(command -v "$cmd"))"
  else
    fail "$cmd NO encontrado — instálalo antes de continuar"
    FAILED=1
  fi
done

echo ""

# ── 2. Archivos / directorios clave del proyecto ──────────────────────
# ADAPTAR: lista los archivos que deben existir para que el proyecto funcione.
echo "--- Archivos clave del proyecto ---"

# El directorio donde vive este script (asume que está en la raíz del proyecto).
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REQUIRED_FILES=(
  # "package.json"       # Node.js
  # "requirements.txt"  # Python
  # "go.mod"            # Go
  # "Cargo.toml"        # Rust
  # ".env"              # Variables de entorno (¡no versionar!)
)

for f in "${REQUIRED_FILES[@]}"; do
  if [ -e "$PROJECT_ROOT/$f" ]; then
    ok "$f existe"
  else
    fail "$f NO encontrado en $PROJECT_ROOT"
    FAILED=1
  fi
done

# Si no hay nada que verificar, avisar.
if [ "${#REQUIRED_FILES[@]}" -eq 0 ]; then
  warn "Sin archivos clave configurados — edita REQUIRED_FILES en este script"
fi

echo ""

# ── 3. Variables de entorno obligatorias ──────────────────────────────
# ADAPTAR: lista las env vars que tu app necesita en runtime o en tests.
echo "--- Variables de entorno ---"

REQUIRED_ENV=(
  # "DATABASE_URL"
  # "API_KEY"
  # "APP_ENV"
)

for var in "${REQUIRED_ENV[@]}"; do
  if [ -n "${!var:-}" ]; then
    ok "$var definida"
  else
    fail "$var NO definida"
    FAILED=1
  fi
done

if [ "${#REQUIRED_ENV[@]}" -eq 0 ]; then
  warn "Sin env vars configuradas — edita REQUIRED_ENV en este script"
fi

echo ""

# ── 4. Tests del proyecto ─────────────────────────────────────────────
# ADAPTAR: reemplaza el bloque de abajo con el comando de tests de tu stack.
# El bloque completo debe salir con exit code != 0 si algún test falla.
echo "--- Corriendo tests ---"

# Ejemplos por stack (descomenta el que corresponda y borra el placeholder):
#
# Node.js / npm:
#   cd "$PROJECT_ROOT" && npm test
#
# Node.js / yarn:
#   cd "$PROJECT_ROOT" && yarn test
#
# Python / pytest:
#   cd "$PROJECT_ROOT" && python3 -m pytest
#
# Go:
#   cd "$PROJECT_ROOT" && go test ./...
#
# Rust:
#   cd "$PROJECT_ROOT" && cargo test
#
# Makefile genérico:
#   cd "$PROJECT_ROOT" && make test

# PLACEHOLDER — el usuario debe reemplazar esto:
warn "Comando de tests no configurado — edita la sección '4. Tests' en este script"
warn "Mientras tanto, esta sección SIEMPRE pasa (exit 0)"
# Para forzar fallo de prueba, cambia la línea de abajo a: TEST_EXIT=1
TEST_EXIT=0

if [ "$TEST_EXIT" -eq 0 ]; then
  ok "Tests pasaron"
else
  fail "Tests fallaron"
  FAILED=1
fi

echo ""

# ── Resultado final ───────────────────────────────────────────────────
echo "=== Resultado ==="
if [ "$FAILED" -eq 0 ]; then
  ok "Entorno listo — sin bloqueantes detectados"
  echo ""
  exit 0
else
  fail "Se encontraron problemas — revisa los errores arriba"
  echo ""
  exit 1
fi
