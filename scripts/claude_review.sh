#!/usr/bin/env bash
# Wrapper de Claude Code (claude -p) para la review profunda en contexto limpio.
# Read-only sobre el código: el reviewer lee, corre tests y escribe un JSON de veredicto.
#
# IMPORTANTE (15 jun 2026): claude -p consume el crédito mensual Agent SDK,
# separado del uso interactivo de Claude Code. Requiere opt-in del crédito.
# Ver README.md → sección Billing.
#
# Uso:
#   claude_review.sh <worktree_dir> <pr_num> <session> <out_json>
# Variables opcionales:
#   PR_LOOP_DRY_RUN=1    -> solo imprime el comando
#   CLAUDE_MODEL          -> default opus
#   CLAUDE_ALLOWED_TOOLS  -> herramientas permitidas (ver default abajo)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"
source "$SCRIPT_DIR/render_prompt.sh"

WORKTREE="${1:?worktree_dir requerido}"
PR_NUM="${2:?pr_num requerido}"
SESSION="${3:?session requerido}"
OUT_JSON="${4:?out_json requerido}"
CLAUDE_MODEL="${CLAUDE_MODEL:-opus}"

# Herramientas permitidas al reviewer. Solo lectura + Write para el JSON efímero.
# Personaliza vía CLAUDE_ALLOWED_TOOLS si tu proyecto tiene comandos de test específicos.
# Ejemplo: export CLAUDE_ALLOWED_TOOLS="Read,Grep,Write,Bash(gh *),Bash(npm test),Bash(cat *),Bash(ls *)"
DEFAULT_TOOLS="Read,Grep,Write,Bash(gh *),Bash(cat *),Bash(ls *)"
ALLOWED_TOOLS="${CLAUDE_ALLOWED_TOOLS:-$DEFAULT_TOOLS}"

WORKTREE_JSON="$WORKTREE/.pr-loop-claude-review.json"
RAW_JSON="${OUT_JSON%.json}.raw.json"

if ! command -v claude &>/dev/null; then
  echo "❌ Claude Code CLI 'claude' no está instalado. Ver https://code.claude.com" >&2
  exit 1
fi

PROMPT="$(render_prompt review-claude.md "" "$PR_NUM" "$SESSION" "$WORKTREE_JSON")"

echo "→ [claude] claude -p --model $CLAUDE_MODEL  (PR #$PR_NUM, out: $OUT_JSON)"

if [ "${PR_LOOP_DRY_RUN:-0}" = "1" ]; then
  echo "  [dry-run] no se ejecuta la review. Prompt:"
  echo "$PROMPT" | sed 's/^/    | /'
  echo "  [dry-run] worktree json: $WORKTREE_JSON → $OUT_JSON"
  exit 0
fi

mkdir -p "$(dirname "$OUT_JSON")"
rm -f "$WORKTREE_JSON"

cd "$WORKTREE"
claude -p "$PROMPT" \
  --model "$CLAUDE_MODEL" \
  --output-format json \
  --allowedTools "$ALLOWED_TOOLS" \
  > "$RAW_JSON" || {
    echo "⚠ claude -p devolvió un error (¿crédito Agent SDK agotado o sin opt-in?)." >&2
    echo "  Revisa README.md → sección Billing." >&2
    exit 1
  }

# ── Resolver JSON final ───────────────────────────────────────────────
is_valid_review_json() {
  local f="$1"
  [ -s "$f" ] && command -v jq &>/dev/null && jq -e '.veredicto' "$f" &>/dev/null
}

copy_review_to_dest() {
  local src="$1"
  mkdir -p "$(dirname "$OUT_JSON")"
  cp "$src" "$OUT_JSON"
}

extract_review_from_raw() {
  local raw="$1" dest="$2"
  [ -f "$raw" ] || return 1
  command -v jq &>/dev/null || return 1

  local candidate=""

  # 1) Intentos Write denegados o exitosos registrados en permission_denials.
  candidate="$(jq -r '
    [.permission_denials[]?
      | select(.tool_name == "Write")
      | .tool_input.content // empty]
    | map(select(length > 0))
    | last // empty
  ' "$raw" 2>/dev/null || true)"
  if [ -n "$candidate" ] && printf '%s' "$candidate" | jq -e '.veredicto' &>/dev/null; then
    printf '%s\n' "$candidate" > "$dest"
    return 0
  fi

  # 2) Bloque ```json en .result (markdown).
  candidate="$(jq -r '.result // empty' "$raw" 2>/dev/null \
    | awk '/^```json[[:space:]]*$/{flag=1;next} /^```[[:space:]]*$/{if(flag){exit}; flag=0} flag' \
    || true)"
  if [ -n "$candidate" ] && printf '%s' "$candidate" | jq -e '.veredicto' &>/dev/null; then
    printf '%s\n' "$candidate" > "$dest"
    return 0
  fi

  # 3) JSON suelto al inicio de línea en .result.
  candidate="$(jq -r '.result // empty' "$raw" 2>/dev/null | sed -n '/^{/,/^}/p' || true)"
  if [ -n "$candidate" ] && printf '%s' "$candidate" | jq -e '.veredicto' &>/dev/null; then
    printf '%s\n' "$candidate" > "$dest"
    return 0
  fi

  return 1
}

if is_valid_review_json "$WORKTREE_JSON"; then
  copy_review_to_dest "$WORKTREE_JSON"
  rm -f "$WORKTREE_JSON"
elif is_valid_review_json "$OUT_JSON"; then
  : # ya existe (re-run)
else
  echo "  Reviewer no dejó JSON en worktree; intento extraer de ${RAW_JSON##*/}."
  TMP_EXTRACT="$(mktemp)"
  if extract_review_from_raw "$RAW_JSON" "$TMP_EXTRACT"; then
    copy_review_to_dest "$TMP_EXTRACT"
    echo "  ✓ JSON recuperado del output de claude -p."
  fi
  rm -f "$TMP_EXTRACT"
fi

rm -f "$WORKTREE_JSON"

if ! is_valid_review_json "$OUT_JSON"; then
  echo "⚠ No se obtuvo JSON de review válido en $OUT_JSON." >&2
  echo "  Revisa $RAW_JSON (permission_denials / .result)." >&2
  exit 1
fi

echo "✓ Review Claude escrita en $OUT_JSON"
