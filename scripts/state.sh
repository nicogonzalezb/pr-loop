#!/usr/bin/env bash
# Helpers de estado para el pipeline PR multi-agente.
# Lee/escribe el sub-objeto `pr_loop` en progress/current.json.
# Requiere jq.
#
# Uso (sourced):
#   source scripts/state.sh
#   state_init "issue-35" 57 "$SESSION_ID"
#   state_set_fase "review-claude"
#   state_set_review claude "progress/...-claude-review.json"
#   state_get_fase
set -euo pipefail

: "${REPO_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_FILE="${STATE_FILE:-$REPO_ROOT/progress/current.json}"

_state_require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "❌ jq no está instalado — requerido por el pipeline PR." >&2
    echo "   Instala con: brew install jq" >&2
    exit 1
  fi
}

_state_ensure_file() {
  mkdir -p "$(dirname "$STATE_FILE")"
  if [ ! -s "$STATE_FILE" ]; then
    cat > "$STATE_FILE" <<'EOF'
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
  fi
}

_state_dry() { [ "${PR_LOOP_DRY_RUN:-0}" = "1" ]; }

# state_init <issue> <pr|null> <session_id>
state_init() {
  _state_dry && return 0
  _state_require_jq
  _state_ensure_file
  local issue="$1" pr="$2" session="$3"
  local pr_json="null"
  [ "$pr" != "null" ] && [ -n "$pr" ] && pr_json="$pr"
  local max_usd="null" max_tokens="null"
  [ -n "${PR_LOOP_MAX_USD:-}" ] && max_usd="${PR_LOOP_MAX_USD}"
  [ -n "${PR_LOOP_MAX_TOKENS:-}" ] && max_tokens="${PR_LOOP_MAX_TOKENS}"
  local tmp; tmp="$(mktemp)"
  jq \
    --arg issue "$issue" \
    --argjson pr "$pr_json" \
    --arg session "$session" \
    --argjson max_usd "$max_usd" \
    --argjson max_tokens "$max_tokens" \
    '.pr_loop = {
      issue: $issue,
      pr: $pr,
      fase: "init",
      session_id: $session,
      intentos_fix: 0,
      reviews: { claude: null, codex: null },
      budget: {
        max_usd: (if $max_usd == null then null else ($max_usd | tonumber) end),
        max_tokens: (if $max_tokens == null then null else ($max_tokens | tonumber) end),
        spent_usd: 0,
        tokens: 0,
        entries: [],
        exceeded: false,
        exceeded_reason: null
      }
    }' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# state_set_fase <fase>
state_set_fase() {
  _state_dry && return 0
  _state_require_jq
  local tmp; tmp="$(mktemp)"
  jq --arg fase "$1" '.pr_loop.fase = $fase' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# state_set_pr <pr>
state_set_pr() {
  _state_dry && return 0
  _state_require_jq
  local tmp; tmp="$(mktemp)"
  jq --argjson pr "$1" '.pr_loop.pr = $pr' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# state_set_review <claude|codex> <path>
state_set_review() {
  _state_dry && return 0
  _state_require_jq
  local key="$1" path="$2"
  local tmp; tmp="$(mktemp)"
  jq --arg k "$key" --arg p "$path" '.pr_loop.reviews[$k] = $p' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# state_inc_fix  -> incrementa intentos_fix y lo imprime
state_inc_fix() {
  if _state_dry; then echo 0; return 0; fi
  _state_require_jq
  local tmp; tmp="$(mktemp)"
  jq '.pr_loop.intentos_fix += 1' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  jq -r '.pr_loop.intentos_fix' "$STATE_FILE"
}

# state_get <campo>   ej: state_get fase / state_get pr / state_get intentos_fix
state_get() {
  _state_require_jq
  jq -r ".pr_loop.$1 // empty" "$STATE_FILE"
}

state_get_fase() { state_get fase; }

# state_clear -> deja current.json en idle (sin pr_loop)
state_clear() {
  _state_require_jq
  _state_ensure_file
  local tmp; tmp="$(mktemp)"
  jq 'del(.pr_loop) | .estado = "idle"' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}
