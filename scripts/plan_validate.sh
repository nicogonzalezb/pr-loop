#!/usr/bin/env bash
# Valida el JSON de propuesta del outer loop (plan-loop).
#
# Uso:
#   plan_validate.sh <proposal.json>
# Exit 0 = válido; exit 1 = inválido (mensaje en stderr).
set -euo pipefail

PROPOSAL="${1:?proposal.json requerido}"

if ! command -v jq &>/dev/null; then
  echo "❌ jq no está instalado." >&2
  exit 1
fi

if [ ! -s "$PROPOSAL" ]; then
  echo "❌ Propuesta vacía o inexistente: $PROPOSAL" >&2
  exit 1
fi

if ! jq -e . "$PROPOSAL" &>/dev/null; then
  echo "❌ JSON inválido: $PROPOSAL" >&2
  exit 1
fi

# Campos obligatorios de nivel raíz
for field in version epic atomic sub_issues; do
  if ! jq -e "has(\"$field\")" "$PROPOSAL" &>/dev/null; then
    echo "❌ Falta campo obligatorio: $field" >&2
    exit 1
  fi
done

local_atomic="$(jq -r '.atomic' "$PROPOSAL")"
local_count="$(jq '.sub_issues | length' "$PROPOSAL")"

if [ "$local_atomic" = "true" ]; then
  if [ "$local_count" -ne 0 ]; then
    echo "❌ atomic=true pero sub_issues no está vacío ($local_count items)" >&2
    exit 1
  fi
  reason="$(jq -r '.atomic_reason // ""' "$PROPOSAL")"
  if [ -z "$reason" ]; then
    echo "❌ atomic=true requiere atomic_reason no vacío" >&2
    exit 1
  fi
  exit 0
fi

if [ "$local_atomic" != "false" ]; then
  echo "❌ atomic debe ser true o false (got: $local_atomic)" >&2
  exit 1
fi

if [ "$local_count" -lt 1 ]; then
  echo "❌ atomic=false requiere al menos un sub-issue" >&2
  exit 1
fi

# Validar cada sub-issue contra el contrato mínimo
idx=0
while [ "$idx" -lt "$local_count" ]; do
  title="$(jq -r ".sub_issues[$idx].title // \"\"" "$PROPOSAL")"
  body="$(jq -r ".sub_issues[$idx].body // \"\"" "$PROPOSAL")"

  if [ -z "$title" ]; then
    echo "❌ sub_issues[$idx]: title vacío" >&2
    exit 1
  fi

  if [ -z "$body" ]; then
    echo "❌ sub_issues[$idx]: body vacío" >&2
    exit 1
  fi

  for section in "Contexto" "Entra" "Criterios de aceptación"; do
    if ! printf '%s' "$body" | grep -q "$section"; then
      echo "❌ sub_issues[$idx] ($title): falta sección '$section' en body" >&2
      exit 1
    fi
  done

  idx=$(( idx + 1 ))
done

exit 0
