#!/usr/bin/env bash
# Propone descomposición de un issue épico vía Claude Code (claude -p).
#
# Uso:
#   plan_propose.sh <epic_num> <arch_doc_path> <session_id> <out_json>
# Variables:
#   PR_LOOP_DRY_RUN=1  -> no invoca agente
#   PLAN_MODEL         -> default sonnet
#   CLAUDE_ALLOWED_TOOLS -> herramientas del planner
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPTS_DIR="$REPO_ROOT/prompts"
source "$SCRIPT_DIR/plan_render.sh"

EPIC_NUM="${1:?epic_num requerido}"
ARCH_DOC="${2:?arch_doc_path requerido}"
SESSION="${3:?session_id requerido}"
OUT_JSON="${4:?out_json requerido}"
PLAN_MODEL="${PLAN_MODEL:-sonnet}"

DEFAULT_TOOLS="Read,Write,Bash(gh *)"
ALLOWED_TOOLS="${PLANNER_ALLOWED_TOOLS:-${CLAUDE_ALLOWED_TOOLS:-$DEFAULT_TOOLS}}"

PROPOSAL_JSON="$REPO_ROOT/.plan-loop-proposal.json"
RAW_JSON="${OUT_JSON%.json}.raw.json"

if ! command -v gh &>/dev/null; then
  echo "❌ gh no está instalado." >&2
  exit 1
fi

if ! command -v claude &>/dev/null; then
  echo "❌ Claude Code CLI 'claude' no está instalado." >&2
  exit 1
fi

PROMPT="$(plan_render "$EPIC_NUM" "$PROPOSAL_JSON" "$ARCH_DOC")"

echo "→ [plan] claude -p --model $PLAN_MODEL  (épico #$EPIC_NUM → $OUT_JSON)"

if [ "${PR_LOOP_DRY_RUN:-0}" = "1" ]; then
  echo "  [dry-run] no se ejecuta el planner."
  echo "  [dry-run] doc arquitectura: $ARCH_DOC"
  echo "  [dry-run] salida esperada: $OUT_JSON"
  exit 0
fi

mkdir -p "$(dirname "$OUT_JSON")"
rm -f "$PROPOSAL_JSON"

cd "$REPO_ROOT"
claude -p "$PROMPT" \
  --model "$PLAN_MODEL" \
  --output-format json \
  --allowedTools "$ALLOWED_TOOLS" \
  > "$RAW_JSON" || {
    echo "⚠ claude -p falló al proponer descomposición." >&2
    exit 1
  }

is_valid_proposal() {
  local f="$1"
  [ -s "$f" ] && bash "$SCRIPT_DIR/plan_validate.sh" "$f" &>/dev/null
}

copy_proposal() {
  cp "$1" "$OUT_JSON"
}

extract_from_raw() {
  local raw="$1" dest="$2"
  [ -f "$raw" ] || return 1

  local candidate=""
  candidate="$(jq -r '
    [.permission_denials[]?
      | select(.tool_name == "Write")
      | .tool_input.content // empty]
    | map(select(length > 0))
    | last // empty
  ' "$raw" 2>/dev/null || true)"
  if [ -n "$candidate" ] && printf '%s' "$candidate" | jq -e . &>/dev/null; then
    printf '%s\n' "$candidate" > "$dest"
    is_valid_proposal "$dest" && return 0
  fi

  candidate="$(jq -r '.result // empty' "$raw" 2>/dev/null \
    | awk '/^```json[[:space:]]*$/{flag=1;next} /^```[[:space:]]*$/{if(flag){exit}; flag=0} flag' \
    || true)"
  if [ -n "$candidate" ] && printf '%s' "$candidate" | jq -e . &>/dev/null; then
    printf '%s\n' "$candidate" > "$dest"
    is_valid_proposal "$dest" && return 0
  fi

  candidate="$(jq -r '.result // empty' "$raw" 2>/dev/null | sed -n '/^{/,/^}/p' || true)"
  if [ -n "$candidate" ] && printf '%s' "$candidate" | jq -e . &>/dev/null; then
    printf '%s\n' "$candidate" > "$dest"
    is_valid_proposal "$dest" && return 0
  fi

  return 1
}

if is_valid_proposal "$PROPOSAL_JSON"; then
  copy_proposal "$PROPOSAL_JSON"
elif is_valid_proposal "$OUT_JSON"; then
  :
else
  TMP="$(mktemp)"
  if extract_from_raw "$RAW_JSON" "$TMP"; then
    copy_proposal "$TMP"
    echo "  ✓ Propuesta recuperada del output de claude -p."
  fi
  rm -f "$TMP"
fi

rm -f "$PROPOSAL_JSON"

if ! is_valid_proposal "$OUT_JSON"; then
  echo "❌ Propuesta inválida o no generada: $OUT_JSON" >&2
  echo "  Revisa $RAW_JSON" >&2
  exit 1
fi

echo "✓ Propuesta escrita en $OUT_JSON"
