#!/usr/bin/env bash
# Warning no bloqueante sobre el orden de issues.
# Lee ORDER_FILE (default: issues/orden-de-trabajo.md) y avisa si el issue
# parece estar fuera de la secuencia recomendada. Nunca bloquea por sí solo:
# el orquestador decide con --force.
#
# Uso:
#   check_order <issue_num>
# Exit code: 0 = en orden o sin datos; 1 = posible fuera de orden (warning).
#
# Variables:
#   ORDER_FILE   Ruta al documento de orden (default: $REPO_ROOT/issues/orden-de-trabajo.md)
set -euo pipefail

: "${REPO_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ORDER_FILE="${ORDER_FILE:-$REPO_ROOT/issues/orden-de-trabajo.md}"

check_order() {
  local issue_num="$1"

  if [ ! -f "$ORDER_FILE" ]; then
    echo "  (sin $ORDER_FILE — omito chequeo de orden)"
    return 0
  fi

  if ! grep -qE "#${issue_num}\b|issues/${issue_num}\b|issue-${issue_num}\b" "$ORDER_FILE"; then
    echo "  ⚠ Issue #${issue_num} no aparece en $(basename "$ORDER_FILE")."
    echo "    Verifica que sea un issue válido y planificado."
    return 1
  fi

  local ctx
  ctx="$(grep -nE "#${issue_num}\b" "$ORDER_FILE" | head -n 3 || true)"
  echo "  Contexto en $(basename "$ORDER_FILE"):"
  echo "$ctx" | sed 's/^/    /'

  if echo "$ctx" | grep -qiE "bloquead|⛔|blocked"; then
    echo "  ⚠ Issue #${issue_num} parece estar BLOQUEADO según el documento."
    return 1
  fi

  echo "  ✓ Issue #${issue_num} está en el plan de trabajo."
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  check_order "$@"
fi
