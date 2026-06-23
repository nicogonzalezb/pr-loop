#!/usr/bin/env bash
# Tests mínimos de budget.sh (sin bats — issue #8).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_STATE="$(mktemp)"
trap 'rm -f "$TMP_STATE"' EXIT

export STATE_FILE="$TMP_STATE"
export PR_LOOP_MAX_USD="0.05"
export PR_LOOP_MAX_TOKENS="100"

# shellcheck source=scripts/state.sh
source "$SCRIPT_DIR/state.sh"
# shellcheck source=scripts/budget.sh
source "$SCRIPT_DIR/budget.sh"

cat > "$TMP_STATE" <<'EOF'
{
  "sesion": null,
  "estado": "idle",
  "tarea_actual": null,
  "agente_activo": null,
  "pendientes": [],
  "completados": [],
  "notas": ""
}
EOF

state_init "issue-test" "null" "test-session"

MOCK_RAW="$(mktemp)"
trap 'rm -f "$TMP_STATE" "$MOCK_RAW"' EXIT

cat > "$MOCK_RAW" <<'EOF'
{
  "total_cost_usd": 0.03,
  "usage": { "input_tokens": 40, "output_tokens": 10 }
}
EOF

budget_record_from_raw "$MOCK_RAW" "test-phase"
budget_guard

if budget_is_exceeded; then
  echo "FAIL: no debería exceder tras primer registro bajo tope" >&2
  exit 1
fi

cat > "$MOCK_RAW" <<'EOF'
{
  "total_cost_usd": 0.03,
  "usage": { "input_tokens": 50, "output_tokens": 20 }
}
EOF

budget_record_from_raw "$MOCK_RAW" "test-phase-2"

if ! budget_is_exceeded; then
  echo "FAIL: debería exceder tokens (130 >= 100)" >&2
  exit 1
fi

echo "✓ test_budget.sh pasó"
