#!/usr/bin/env bash
# Wrapper de OpenAI Codex CLI (codex review) para la segunda review.
# Nativo de Codex (suscripción ChatGPT) — NO pasa por Cursor.
# Read-only por diseño: `codex review` no toca el working tree.
#
# Uso:
#   codex_review.sh <worktree_dir> <out_md> [base_branch]
# Variables opcionales:
#   PR_LOOP_DRY_RUN=1   -> solo imprime el comando
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"
PROMPTS_DIR="${PROMPTS_DIR:-$REPO_ROOT/prompts}"

WORKTREE="${1:?worktree_dir requerido}"
OUT_MD="${2:?out_md requerido}"
BASE_BRANCH="${3:-main}"

if ! command -v codex &>/dev/null; then
  echo "❌ Codex CLI 'codex' no está instalado. Instala: curl -fsSL https://codex.openai.com/install.sh | sh" >&2
  exit 1
fi

INSTRUCTIONS="$(cat "$PROMPTS_DIR/review-codex.md")"

CODEX_REVIEW_CMD=(codex exec review --base "$BASE_BRANCH" -o "$OUT_MD")
echo "→ [codex] codex exec review --base $BASE_BRANCH -o <out>"

if [ "${PR_LOOP_DRY_RUN:-0}" = "1" ]; then
  echo "  [dry-run] no se ejecuta la review. Instrucciones:"
  echo "$INSTRUCTIONS" | sed 's/^/    | /'
  echo "  [dry-run] no se genera $OUT_MD"
  exit 0
fi

cd "$WORKTREE"
"${CODEX_REVIEW_CMD[@]}" || {
  echo "⚠ codex review devolvió un error (¿login ChatGPT o límite de plan?)." >&2
  exit 1
}

if [ ! -s "$OUT_MD" ]; then
  echo "⚠ codex review no produjo salida en $OUT_MD." >&2
  exit 1
fi

echo "✓ Review Codex escrita en $OUT_MD"
