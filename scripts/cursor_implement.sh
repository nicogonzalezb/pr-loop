#!/usr/bin/env bash
# Wrapper de Cursor CLI (agent -p) para las fases implement y fix.
# Corre dentro del worktree con acceso a escritura y a la suite de tests.
# Usa tu suscripción Cursor (no Cloud, no SDK).
#
# Uso:
#   cursor_implement.sh <worktree_dir> <prompt_file> <issue_num> [session] [reviews_path]
# Variables opcionales:
#   PR_LOOP_DRY_RUN=1   -> solo imprime el comando
#   CURSOR_MODEL         -> default composer-2.5
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$SCRIPT_DIR/render_prompt.sh"

WORKTREE="${1:?worktree_dir requerido}"
PROMPT_FILE="${2:?prompt_file requerido}"
ISSUE_NUM="${3:?issue_num requerido}"
SESSION="${4:-}"
REVIEWS="${5:-}"
CURSOR_MODEL="${CURSOR_MODEL:-composer-2.5}"

if ! command -v agent &>/dev/null; then
  echo "❌ Cursor CLI 'agent' no está instalado. Instala: curl https://cursor.com/install -fsS | bash" >&2
  exit 1
fi

PROMPT="$(render_prompt "$PROMPT_FILE" "$ISSUE_NUM" "" "$SESSION" "$REVIEWS")"

echo "→ [cursor] agent -p --model $CURSOR_MODEL  (worktree: $WORKTREE, prompt: $PROMPT_FILE)"

if [ "${PR_LOOP_DRY_RUN:-0}" = "1" ]; then
  echo "  [dry-run] no se ejecuta el agente. Prompt:"
  echo "$PROMPT" | sed 's/^/    | /'
  exit 0
fi

cd "$WORKTREE"
# --force aprueba ejecuciones de herramientas sin prompt interactivo (headless).
# Los permisos finos (qué shell/escrituras se permiten) viven en .cursor/cli.json del repo.
agent -p "$PROMPT" \
  --model "$CURSOR_MODEL" \
  --force \
  --output-format text
