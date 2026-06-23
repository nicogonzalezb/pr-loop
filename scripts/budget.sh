#!/usr/bin/env bash
# Presupuesto de gasto por corrida (claude -p).
# Requiere state.sh sourced previamente.
#
# Variables:
#   PR_LOOP_MAX_USD     Tope de USD por corrida (opcional)
#   PR_LOOP_MAX_TOKENS  Tope de tokens (input+output) por corrida (opcional)
#
# Uso (sourced):
#   source scripts/budget.sh
#   budget_record_from_raw progress/foo.raw.json review-claude
#   budget_abort_if_exceeded
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"
if ! declare -f _state_require_jq &>/dev/null; then
  # shellcheck source=scripts/state.sh
  source "$SCRIPT_DIR/state.sh"
fi

budget_caps_configured() {
  [ -n "${PR_LOOP_MAX_USD:-}" ] || [ -n "${PR_LOOP_MAX_TOKENS:-}" ]
}

# budget_record_from_raw <raw_json> <fase>
budget_record_from_raw() {
  local raw="${1:?raw_json requerido}" phase="${2:?fase requerida}"
  _state_dry && return 0
  _state_require_jq
  [ -f "$raw" ] || return 0

  local cost tokens
  cost="$(jq -r '.total_cost_usd // 0' "$raw" 2>/dev/null || echo 0)"
  tokens="$(jq -r '
    ((.usage.input_tokens // 0) + (.usage.output_tokens // 0)) | tonumber
  ' "$raw" 2>/dev/null || echo 0)"

  local tmp; tmp="$(mktemp)"
  jq \
    --arg phase "$phase" \
    --argjson cost "$cost" \
    --argjson tokens "$tokens" \
    '.pr_loop.budget.spent_usd += $cost
     | .pr_loop.budget.tokens += $tokens
     | .pr_loop.budget.entries += [{phase: $phase, cost_usd: $cost, tokens: $tokens}]' \
    "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

  echo "  [budget] +$tokens tokens, +\$${cost} ($phase) — acum: $(budget_format_totals)"
}

budget_format_totals() {
  _state_require_jq
  jq -r '
    .pr_loop.budget
    | "\(.tokens) tokens, $\(.spent_usd) USD"
    + (if .max_usd != null then " / max $\(.max_usd)" else "" end)
    + (if .max_tokens != null then " / max \(.max_tokens) tokens" else "" end)
  ' "$STATE_FILE" 2>/dev/null || echo "0 tokens, $0 USD"
}

# budget_is_exceeded — exit 0 si se superó el tope configurado
budget_is_exceeded() {
  _state_dry && return 1
  _state_require_jq
  budget_caps_configured || return 1
  jq -e '
    .pr_loop.budget as $b |
    (($b.max_usd != null) and ($b.spent_usd >= $b.max_usd))
    or (($b.max_tokens != null) and ($b.tokens >= $b.max_tokens))
  ' "$STATE_FILE" &>/dev/null
}

# budget_abort_if_exceeded — sale con 2 si se superó el tope
budget_abort_if_exceeded() {
  _state_dry && return 0
  if ! budget_is_exceeded; then
    return 0
  fi

  local reason
  reason="$(jq -r '
    .pr_loop.budget as $b |
    if ($b.max_usd != null) and ($b.spent_usd >= $b.max_usd) then
      "USD: $\($b.spent_usd) >= tope $\($b.max_usd)"
    elif ($b.max_tokens != null) and ($b.tokens >= $b.max_tokens) then
      "tokens: \($b.tokens) >= tope \($b.max_tokens)"
    else "tope superado" end
  ' "$STATE_FILE")"

  local tmp; tmp="$(mktemp)"
  jq \
    --arg reason "$reason" \
    '.pr_loop.budget.exceeded = true
     | .pr_loop.budget.exceeded_reason = $reason
     | .pr_loop.fase = "budget-exceeded"' \
    "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

  echo ""
  echo "❌ Presupuesto de corrida agotado ($reason)." >&2
  echo "   Acumulado: $(budget_format_totals)" >&2
  echo "   Estado guardado en $STATE_FILE (fase: budget-exceeded)." >&2
  exit 2
}

# budget_guard — aborta antes de invocar claude si ya se superó el tope
budget_guard() {
  _state_dry && return 0
  budget_abort_if_exceeded
}

# budget_summary_line — una línea para gate / consola
budget_summary_line() {
  _state_require_jq
  if ! jq -e '.pr_loop.budget' "$STATE_FILE" &>/dev/null; then
    echo "presupuesto: no registrado"
    return 0
  fi
  jq -r '
    .pr_loop.budget as $b |
    "gasto: \($b.tokens) tokens, $\($b.spent_usd) USD"
    + (if $b.max_usd != null then " (tope $\($b.max_usd))" else "" end)
    + (if $b.max_tokens != null then " (tope \($b.max_tokens) tokens)" else "" end)
    + (if $b.exceeded then " — EXCEDIDO: \($b.exceeded_reason)" else "" end)
  ' "$STATE_FILE" 2>/dev/null || echo "presupuesto: (error al leer)"
}
