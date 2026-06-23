#!/usr/bin/env bash
# Tests de validación del outer loop (plan-loop).
# Exit 0 = todos pasan.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/plan_validate.sh"
FIXTURES="$REPO_ROOT/tests/plan/fixtures"

ok()   { echo "✓ $*"; }
fail() { echo "✗ $*" >&2; exit 1; }

echo "=== tests/plan_validate ==="

if bash "$VALIDATE" "$FIXTURES/valid-proposal.json"; then
  ok "valid-proposal.json aceptado"
else
  fail "valid-proposal.json debería ser válido"
fi

if bash "$VALIDATE" "$FIXTURES/atomic-proposal.json"; then
  ok "atomic-proposal.json aceptado"
else
  fail "atomic-proposal.json debería ser válido"
fi

if bash "$VALIDATE" "$FIXTURES/invalid-proposal.json" 2>/dev/null; then
  fail "invalid-proposal.json debería rechazarse"
else
  ok "invalid-proposal.json rechazado"
fi

# plan_create dry-run
CREATED="$(mktemp)"
export PR_LOOP_DRY_RUN=1
if bash "$REPO_ROOT/scripts/plan_create.sh" "$FIXTURES/valid-proposal.json" "$CREATED"; then
  ok "plan_create dry-run"
else
  fail "plan_create dry-run falló"
fi
rm -f "$CREATED"

# plan-loop dry-run (preflight)
if bash "$REPO_ROOT/plan-loop.sh" 5 --dry-run &>/dev/null; then
  ok "plan-loop.sh --dry-run"
else
  fail "plan-loop.sh --dry-run falló"
fi

# plan-loop con propuesta fixture (human-gate omitido en dry-run)
if bash "$REPO_ROOT/plan-loop.sh" 99 --dry-run \
  --proposal "$FIXTURES/valid-proposal.json" &>/dev/null; then
  ok "plan-loop --proposal + dry-run"
else
  fail "plan-loop --proposal dry-run falló"
fi

echo ""
ok "Todos los tests plan-loop pasaron"
