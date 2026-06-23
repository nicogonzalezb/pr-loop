#!/usr/bin/env bash
# Renderiza un prompt versionado de prompts/ sustituyendo placeholders.
# Placeholders soportados: {{ISSUE}}, {{PR}}, {{SESSION}}, {{REVIEWS}}
#
# Uso:
#   render_prompt <archivo.md> [ISSUE] [PR] [SESSION] [REVIEWS_PATH]
# Imprime el prompt renderizado a stdout.
set -euo pipefail

: "${REPO_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROMPTS_DIR="${PROMPTS_DIR:-$REPO_ROOT/prompts}"

render_prompt() {
  local file="$1"
  local issue="${2:-}" pr="${3:-}" session="${4:-}" reviews="${5:-}"
  local path="$PROMPTS_DIR/$file"
  if [ ! -f "$path" ]; then
    echo "❌ Prompt no encontrado: $path" >&2
    return 1
  fi
  sed \
    -e "s|{{ISSUE}}|${issue}|g" \
    -e "s|{{PR}}|${pr}|g" \
    -e "s|{{SESSION}}|${session}|g" \
    -e "s|{{REVIEWS}}|${reviews}|g" \
    "$path"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  render_prompt "$@"
fi
