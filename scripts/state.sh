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
#   state_append_history   # requiere HISTORY_* (ver función)
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
  local tmp; tmp="$(mktemp)"
  jq \
    --arg issue "$issue" \
    --argjson pr "$pr_json" \
    --arg session "$session" \
    '.pr_loop = {
      issue: $issue,
      pr: $pr,
      fase: "init",
      session_id: $session,
      intentos_fix: 0,
      reviews: { claude: null, codex: null }
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

HISTORY_FILE="${HISTORY_FILE:-$REPO_ROOT/progress/history.md}"

# state_append_history — append de metadata de corrida a progress/history.md
# Variables de entorno (exportadas por pr-loop.sh antes de invocar):
#   HISTORY_SESSION, HISTORY_ISSUE, HISTORY_ISSUE_NUM (opcional)
#   HISTORY_PR, HISTORY_FROM (opcional), HISTORY_PHASES (csv)
#   HISTORY_FIX_ATTEMPTS, HISTORY_BLOQUEANTES, HISTORY_FIX_STATUS
#   HISTORY_GATE_VERDICT, HISTORY_GATE_RC
#   HISTORY_GASTO (opcional, cuando exista presupuesto #1)
state_append_history() {
  _state_dry && return 0

  local session="${HISTORY_SESSION:?HISTORY_SESSION requerido}"
  local issue="${HISTORY_ISSUE:?HISTORY_ISSUE requerido}"
  local issue_num="${HISTORY_ISSUE_NUM:-}"
  local pr="${HISTORY_PR:-}"
  local from_phase="${HISTORY_FROM:-}"
  local phases="${HISTORY_PHASES:-}"
  local fix_attempts="${HISTORY_FIX_ATTEMPTS:-0}"
  local bloqueantes="${HISTORY_BLOQUEANTES:-0}"
  local fix_status="${HISTORY_FIX_STATUS:-}"
  local gate_verdict="${HISTORY_GATE_VERDICT:-}"
  local gate_rc="${HISTORY_GATE_RC:-}"
  local gasto="${HISTORY_GASTO:-}"

  mkdir -p "$(dirname "$HISTORY_FILE")"
  if [ ! -f "$HISTORY_FILE" ]; then
    cat > "$HISTORY_FILE" <<'EOF'
# pr-loop — historial de corridas

Log append-only de sesiones del pipeline (gitignored junto con `progress/`).

EOF
  fi

  local issue_label="$issue"
  [ -n "$issue_num" ] && issue_label="${issue} (#${issue_num})"

  local pr_label="—"
  [ -n "$pr" ] && [ "$pr" != "null" ] && pr_label="#${pr}"

  local from_label="—"
  [ -n "$from_phase" ] && from_label="\`${from_phase}\`"

  local phases_label="${phases:-—}"
  [ -n "$phases" ] && phases_label="\`${phases}\`"

  local gate_label="—"
  if [ -n "$gate_verdict" ]; then
    gate_label="${gate_verdict}"
    [ -n "$gate_rc" ] && gate_label="${gate_label} (exit ${gate_rc})"
  fi

  {
    echo "## ${session} — ${issue}"
    echo ""
    echo "| Campo | Valor |"
    echo "|-------|-------|"
    echo "| Issue | \`${issue_label}\` |"
    echo "| PR | ${pr_label} |"
    echo "| Reanudado desde | ${from_label} |"
    echo "| Fases completadas | ${phases_label} |"
    echo "| Intentos fix | ${fix_attempts} |"
    [ -n "$fix_status" ] && echo "| Fix loop | ${fix_status} |"
    echo "| Bloqueantes finales (Claude) | ${bloqueantes} |"
    echo "| Gate | ${gate_label} |"
    [ -n "$gasto" ] && echo "| Gasto acumulado | ${gasto} |"
    echo ""
    echo "---"
    echo ""
  } >> "$HISTORY_FILE"
}
