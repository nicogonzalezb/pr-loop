#!/usr/bin/env bash
# Renderiza un prompt versionado sustituyendo placeholders.
# Resolución: prompts-local/<archivo> si existe; si no, prompts/<archivo>.
# Placeholders soportados: {{ISSUE}}, {{PR}}, {{SESSION}}, {{REVIEWS}}
#
# Uso:
#   render_prompt <archivo.md> [ISSUE] [PR] [SESSION] [REVIEWS_PATH]
# Imprime el prompt renderizado a stdout.
set -euo pipefail

: "${REPO_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROMPTS_DIR="${PROMPTS_DIR:-$REPO_ROOT/prompts}"
PROMPTS_LOCAL_DIR="${PROMPTS_LOCAL_DIR:-$REPO_ROOT/prompts-local}"

# Devuelve la ruta del prompt: overlay local tiene prioridad sobre el núcleo.
resolve_prompt_path() {
  local file="$1"
  local local_path="$PROMPTS_LOCAL_DIR/$file"
  local base_path="$PROMPTS_DIR/$file"
  if [ -f "$local_path" ]; then
    echo "$local_path"
  elif [ -f "$base_path" ]; then
    echo "$base_path"
  else
    echo "❌ Prompt no encontrado: $local_path ni $base_path" >&2
    return 1
  fi
}

render_prompt() {
  local file="$1"
  local issue="${2:-}" pr="${3:-}" session="${4:-}" reviews="${5:-}"
  local path
  path="$(resolve_prompt_path "$file")" || return 1
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
