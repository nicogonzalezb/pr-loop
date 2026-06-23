#!/usr/bin/env bash
# Renderiza prompts/decompose-epic.md sustituyendo placeholders simples.
#
# Uso:
#   plan_render <epic> <output_json_path> <arch_doc_path>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPTS_DIR="$REPO_ROOT/prompts"

plan_render() {
  local epic="$1" output="$2" arch_doc="$3"
  local path="$PROMPTS_DIR/decompose-epic.md"

  if [ ! -f "$path" ]; then
    echo "❌ Prompt no encontrado: $path" >&2
    return 1
  fi

  sed \
    -e "s|{{EPIC}}|${epic}|g" \
    -e "s|{{OUTPUT}}|${output}|g" \
    -e "s|{{ARCH_DOC}}|${arch_doc}|g" \
    "$path"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  plan_render "$@"
fi
