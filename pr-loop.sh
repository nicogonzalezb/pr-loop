#!/usr/bin/env bash
# Pipeline PR multi-agente — 100% terminal (Cursor + Claude + Codex nativos).
#
# Encadena, de forma SECUENCIAL, dentro de un worktree aislado:
#   1. agent -p (Composer 2.5)       → implement
#   2. gh pr create / push           → abre PR
#   3. claude -p (Opus)              → review profunda (read-only, JSON)
#   4. agent -p (Composer 2.5)       → fix según review (máx. 2 loops)
#   5. codex exec review --base main → segunda review (read-only, markdown)
#   6. gate                          → resumen + comentario + recomendación merge
#
# NO mergea automáticamente.
#
# Uso:
#   bash pr-loop.sh install            # preparar proyecto (git worktree, .gitignore)
#   bash pr-loop.sh issue-35
#   bash pr-loop.sh --pr 57
#   bash pr-loop.sh --pr 57 --from review-claude
#   bash pr-loop.sh issue-35 --dry-run
#   bash pr-loop.sh issue-50 --force
#
# Flags:
#   --pr N         Trabaja sobre un PR existente (deriva issue/rama con gh).
#   --from FASE    Reanuda desde una fase: worktree|implement|pr|review-claude|fix|review-codex|gate
#   --dry-run      Imprime el plan de fases sin invocar agentes ni gh.
#   --force        Ignora el warning de orden de issues.
#   --max-fix N    Máximo de loops de fix (default 2; 0 = solo reviews).
#   --no-self-heal Desactiva el self-healing automático de prompts.
#
# Variables de entorno:
#   INIT_SCRIPT        Script de health check a correr antes de cada fase (opcional).
#                      Ej: INIT_SCRIPT=./init.sh
#   PR_BASE_BRANCH     Rama base del PR (default: main).
#   CURSOR_MODEL       Modelo de implement/fix (default: composer-2.5).
#   CLAUDE_MODEL       Modelo de review Claude (default: opus).
#   CLAUDE_ALLOWED_TOOLS  Herramientas permitidas a claude -p (ver claude_review.sh).
#   PR_LOOP_DRY_RUN   Si es "1", equivale a --dry-run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
SCRIPTS_DIR="$REPO_ROOT/scripts"
PROGRESS_DIR="$REPO_ROOT/progress"

# Capa de config del proyecto (dogfooding / overlay futuro de #3).
if [ -f "$REPO_ROOT/.pr-loop.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$REPO_ROOT/.pr-loop.env"
  set +a
fi

export REPO_ROOT \
  PROMPTS_DIR="${PROMPTS_DIR:-$REPO_ROOT/prompts}" \
  PROMPTS_LOCAL_DIR="${PROMPTS_LOCAL_DIR:-$REPO_ROOT/prompts-local}"

source "$SCRIPTS_DIR/state.sh"
source "$SCRIPTS_DIR/check_order.sh"

# ── Parseo de argumentos ─────────────────────────────────────────────
ISSUE=""
PR=""
FROM=""
DRY_RUN=0
FORCE=0
MAX_FIX=2
SELF_HEAL=1

while [ $# -gt 0 ]; do
  case "$1" in
    install)        bash "$SCRIPTS_DIR/install.sh"; exit $?;;
    --pr)           PR="${2:?--pr requiere número}"; shift 2;;
    --from)         FROM="${2:?--from requiere fase}"; shift 2;;
    --dry-run)      DRY_RUN=1; shift;;
    --force)        FORCE=1; shift;;
    --max-fix)      MAX_FIX="${2:?--max-fix requiere número}"; shift 2;;
    --no-self-heal) SELF_HEAL=0; shift;;
    issue-*)        ISSUE="$1"; shift;;
    -h|--help)      sed -n '2,41p' "$0"; exit 0;;
    *)              echo "❌ Argumento no reconocido: $1" >&2; exit 2;;
  esac
done

[ "$DRY_RUN" = "1" ] && export PR_LOOP_DRY_RUN=1

# ── Fase 0: Preflight ────────────────────────────────────────────────
preflight() {
  echo "=== Fase 0: Preflight ==="
  local fail=0
  for tool in agent claude codex gh jq; do
    if command -v "$tool" &>/dev/null; then
      echo "  ✓ $tool"
    else
      echo "  ✗ $tool no encontrado"
      fail=1
    fi
  done

  if [ "$DRY_RUN" != "1" ]; then
    if gh auth status &>/dev/null; then
      echo "  ✓ gh autenticado"
    else
      echo "  ✗ gh no autenticado (gh auth login)"
      fail=1
    fi
  fi

  # init.sh es opcional; se configura vía INIT_SCRIPT.
  if [ -n "${INIT_SCRIPT:-}" ]; then
    if [ -f "$INIT_SCRIPT" ]; then
      echo "  ✓ INIT_SCRIPT=$INIT_SCRIPT"
    else
      echo "  ✗ INIT_SCRIPT=$INIT_SCRIPT no existe"
      fail=1
    fi
  fi

  if [ -n "${WORKTREE_SCRIPT:-}" ]; then
    echo "  ✗ WORKTREE_SCRIPT está deprecado; pr-loop usa git worktree de forma obligatoria." >&2
    fail=1
  fi

  if [ "$DRY_RUN" != "1" ]; then
    if bash "$SCRIPTS_DIR/worktree.sh" verify &>/dev/null; then
      echo "  ✓ git worktree"
    else
      echo "  ✗ git worktree no disponible o no es un repo git"
      echo "    Corre: bash pr-loop.sh install" >&2
      fail=1
    fi
  fi

  if [ "$fail" = "1" ]; then
    echo "❌ Preflight falló. Revisa README.md para el setup." >&2
    [ "$DRY_RUN" = "1" ] && echo "  (dry-run: continúo de todas formas)" || exit 1
  fi
  echo ""
}

# ── Resolver issue/PR según los argumentos ───────────────────────────
resolve_targets() {
  HEAD_REF=""
  if [ -n "$PR" ]; then
    if [ "$DRY_RUN" != "1" ]; then
      local head_ref pr_text
      head_ref="$(gh pr view "$PR" --json headRefName -q .headRefName 2>/dev/null || true)"
      HEAD_REF="$head_ref"
      if [ -n "$head_ref" ] && [[ "$head_ref" =~ ^issue- ]]; then
        ISSUE="$head_ref"
      fi
      if [ -z "$ISSUE" ] || [[ "$ISSUE" == pr-* ]]; then
        pr_text="$(gh pr view "$PR" --json body,title -q '.body + "\n" + .title' 2>/dev/null || true)"
        if [[ "$pr_text" =~ [Cc]loses[[:space:]]*#([0-9]+) ]]; then
          ISSUE_NUM="${BASH_REMATCH[1]}"
          ISSUE="issue-${ISSUE_NUM}"
        elif [[ "$pr_text" =~ (^|[^0-9])#([0-9]+)([^0-9]|$) ]]; then
          ISSUE_NUM="${BASH_REMATCH[2]}"
          ISSUE="issue-${ISSUE_NUM}"
        fi
      fi
    fi
    [ -z "$ISSUE" ] && ISSUE="${ISSUE:-pr-$PR}"
  fi

  if [ -z "$ISSUE" ]; then
    echo "❌ Indica un issue (issue-N) o un PR (--pr N)." >&2
    exit 2
  fi

  if [ -z "${ISSUE_NUM:-}" ]; then
    ISSUE_NUM="${ISSUE#issue-}"
    [[ "$ISSUE_NUM" =~ ^[0-9]+$ ]] || ISSUE_NUM=""
  fi

  local wt_key="${HEAD_REF:-$ISSUE}"
  WORKTREE="$REPO_ROOT/.worktrees/$wt_key"
}

# ── Fase 0b: chequeo de orden ────────────────────────────────────────
phase_order() {
  echo "=== Fase 0b: Orden de issues ==="
  if [ -z "$ISSUE_NUM" ]; then
    echo "  (sin número de issue — omito chequeo)"
    echo ""
    return 0
  fi
  if ! check_order "$ISSUE_NUM"; then
    if [ "$FORCE" = "1" ]; then
      echo "  → --force activo: continúo igualmente."
    else
      echo "❌ Issue fuera de orden recomendado. Usa --force para continuar." >&2
      exit 1
    fi
  fi
  echo ""
}

# ── Fase 1: worktree ─────────────────────────────────────────────────
phase_worktree() {
  echo "=== Fase 1: Worktree ($ISSUE) ==="
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] crear worktree para $ISSUE"
    echo ""
    return 0
  fi
  if [ -d "$WORKTREE" ]; then
    echo "  Worktree ya existe: $WORKTREE"
  elif [ -n "${PR:-}" ] && [ -n "${HEAD_REF:-}" ]; then
    bash "$SCRIPTS_DIR/worktree.sh" add-pr "$HEAD_REF" "$WORKTREE"
  else
    bash "$SCRIPTS_DIR/worktree.sh" add-issue "$ISSUE" "$WORKTREE" "${PR_BASE_BRANCH:-main}"
  fi
  echo ""
}

# ── Fase 2: implement ────────────────────────────────────────────────
phase_implement() {
  echo "=== Fase 2: Implement (agent -p / Composer 2.5) ==="
  if [ -z "$ISSUE_NUM" ]; then
    echo "❌ Fase implement requiere un issue numerado (rama issue-N o PR con 'Closes #N')." >&2
    exit 2
  fi
  state_set_fase "implement"
  bash "$SCRIPTS_DIR/cursor_implement.sh" \
    "$WORKTREE" "implement-issue.md" "$ISSUE_NUM" "$SESSION_ID"
  echo ""
}

# ── Fase 3: PR ───────────────────────────────────────────────────────
phase_pr() {
  echo "=== Fase 3: Abrir/asegurar PR ==="
  state_set_fase "pr"
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] git push + gh pr create (si no existe)"
    echo ""
    return 0
  fi
  ( cd "$WORKTREE" && git push -u origin "$ISSUE" 2>/dev/null || git push )
  if [ -z "$PR" ]; then
    PR="$(gh pr list --head "$ISSUE" --state open --json number -q '.[0].number' 2>/dev/null || true)"
    if [ -z "$PR" ] || [ "$PR" = "null" ]; then
      PR_BASE="${PR_BASE_BRANCH:-main}"
      ( cd "$WORKTREE" && gh pr create \
          --base "$PR_BASE" \
          --title "$ISSUE" \
          --body "$(printf 'Closes #%s\n\nGenerado por pipeline PR multi-agente. Base: %s.' "$ISSUE_NUM" "$PR_BASE")" )
      PR="$(gh pr list --head "$ISSUE" --state open --json number -q '.[0].number' 2>/dev/null || true)"
    fi
  fi
  state_set_pr "${PR:-null}"
  echo "  PR: #${PR:-?}"
  echo ""
}

# ── Fase 4: review Claude ────────────────────────────────────────────
phase_review_claude() {
  echo "=== Fase 4: Review Claude (claude -p / Opus) ==="
  state_set_fase "review-claude"
  CLAUDE_JSON="$PROGRESS_DIR/${SESSION_ID}-claude-review.json"
  if bash "$SCRIPTS_DIR/claude_review.sh" \
    "$WORKTREE" "${PR:-0}" "$SESSION_ID" "$CLAUDE_JSON"; then
    [ "$DRY_RUN" = "1" ] || state_set_review claude "$CLAUDE_JSON"
  else
    echo "❌ Review Claude falló; no se avanza con review vacía." >&2
    exit 1
  fi
  echo ""
}

# ── Fase 5: fix (loop agéntico) ───────────────────────────────────────
FIX_EXITOSO=0   # 0 = sin bloqueantes al salir; 1 = se agotaron los intentos

phase_fix() {
  echo "=== Fase 5: Fix (loop agéntico, máx $MAX_FIX loops) ==="
  if [ -z "$ISSUE_NUM" ]; then
    echo "❌ Fase fix requiere un issue numerado (rama issue-N o PR con 'Closes #N')." >&2
    exit 2
  fi
  if [ "$MAX_FIX" -le 0 ]; then
    echo "  --max-fix=0: se omite la fase de fix."
    FIX_EXITOSO=0
    echo ""
    return 0
  fi
  state_set_fase "fix"

  local intento=0
  while [ "$intento" -lt "$MAX_FIX" ]; do

    # 1. Incrementar contador
    if [ "$DRY_RUN" != "1" ]; then
      intento="$(state_inc_fix)"
    else
      intento=$(( intento + 1 ))
    fi
    echo "  --- Loop de fix #$intento / $MAX_FIX ---"

    # 2. Correr el fix con Cursor
    bash "$SCRIPTS_DIR/cursor_implement.sh" \
      "$WORKTREE" "fix-from-reviews.md" "$ISSUE_NUM" "$SESSION_ID" \
      "${CLAUDE_JSON:-$PROGRESS_DIR/${SESSION_ID}-claude-review.json}"

    # 3. Push al worktree
    if [ "$DRY_RUN" != "1" ]; then
      ( cd "$WORKTREE" && git push 2>/dev/null || true )
    fi

    # 4. Re-review con Claude (nuevo JSON numerado por intento)
    local re_review_json="$PROGRESS_DIR/${SESSION_ID}-claude-review-fix-${intento}.json"
    echo "  → Re-review Claude (intento $intento) → $re_review_json"
    if bash "$SCRIPTS_DIR/claude_review.sh" \
        "$WORKTREE" "${PR:-0}" "$SESSION_ID" "$re_review_json"; then
      # 5. Actualizar CLAUDE_JSON al nuevo archivo
      CLAUDE_JSON="$re_review_json"
      [ "$DRY_RUN" = "1" ] || state_set_review claude "$CLAUDE_JSON"
    else
      echo "⚠ Re-review Claude falló en el intento $intento; se conserva la review anterior." >&2
    fi

    # 6. Contar bloqueantes en el JSON actualizado
    local bloqueantes=0
    if [ "$DRY_RUN" != "1" ] && [ -f "$CLAUDE_JSON" ]; then
      bloqueantes="$(jq '.bloqueantes // [] | length' "$CLAUDE_JSON" 2>/dev/null || echo 0)"
    fi
    echo "  Bloqueantes tras fix #$intento: $bloqueantes"

    # 7. Si 0 bloqueantes, exit exitoso
    if [ "$bloqueantes" -eq 0 ]; then
      FIX_EXITOSO=0
      echo "  ✅ Sin bloqueantes — loop de fix completado."
      break
    fi

    # 8. Si se agotaron los intentos, marcar como agotado
    if [ "$intento" -ge "$MAX_FIX" ]; then
      FIX_EXITOSO=1
      echo "  ⚠ Se agotaron los $MAX_FIX intentos de fix con bloqueantes pendientes."
      break
    fi

  done

  export FIX_EXITOSO
  echo ""
}

# ── Fase 6: review Codex ─────────────────────────────────────────────
phase_review_codex() {
  echo "=== Fase 6: Review Codex (codex review) ==="
  state_set_fase "review-codex"
  CODEX_MD="$PROGRESS_DIR/${SESSION_ID}-codex-review.md"
  bash "$SCRIPTS_DIR/codex_review.sh" "$WORKTREE" "$CODEX_MD" "${PR_BASE_BRANCH:-main}" || true
  [ "$DRY_RUN" = "1" ] || state_set_review codex "$CODEX_MD"
  echo ""
}

# ── Fase 7: gate ─────────────────────────────────────────────────────
phase_gate() {
  echo "=== Fase 7: Gate de merge ==="
  state_set_fase "gate"
  if [ "$DRY_RUN" = "1" ]; then
    echo "  [dry-run] gate_merge.sh consolida reviews y comenta en el PR."
    echo ""
    return 0
  fi
  bash "$SCRIPTS_DIR/gate_merge.sh" \
    "${PR:-0}" "$ISSUE" \
    "${CLAUDE_JSON:-$PROGRESS_DIR/${SESSION_ID}-claude-review.json}" \
    "${CODEX_MD:-$PROGRESS_DIR/${SESSION_ID}-codex-review.md}"
}

# ── Orden de fases y soporte de --from ───────────────────────────────
PHASES=(worktree implement pr review-claude fix review-codex gate)

should_run() {
  local phase="$1"
  if [ -z "$FROM" ]; then return 0; fi
  local started=0
  for p in "${PHASES[@]}"; do
    [ "$p" = "$FROM" ] && started=1
    if [ "$p" = "$phase" ]; then
      [ "$started" = "1" ] && return 0 || return 1
    fi
  done
  return 1
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
  mkdir -p "$PROGRESS_DIR"
  preflight
  resolve_targets

  echo "Pipeline PR multi-agente"
  echo "  Issue:    $ISSUE${ISSUE_NUM:+ (#$ISSUE_NUM)}"
  echo "  PR:       ${PR:-(se creará)}"
  echo "  Worktree: $WORKTREE"
  echo "  PR base:  ${PR_BASE_BRANCH:-main}"
  echo "  Dry-run:  $([ "$DRY_RUN" = 1 ] && echo sí || echo no)"
  echo "  Max-fix:  $MAX_FIX"
  echo "  Self-heal: $([ "$SELF_HEAL" = 1 ] && echo activado || echo desactivado)"
  echo ""

  SESSION_ID="${SESSION_ID:-$(date -u +%Y%m%dT%H%M%S)}"
  if [ "$DRY_RUN" != "1" ]; then
    state_init "$ISSUE" "${PR:-null}" "$SESSION_ID"
  fi

  should_run worktree      && { phase_order; phase_worktree; }
  should_run implement     && phase_implement
  should_run pr            && phase_pr
  should_run review-claude && phase_review_claude
  should_run fix           && phase_fix

  # Self-healing: si el fix se agotó con bloqueantes pendientes, intentar
  # mejorar automáticamente el prompt fix-from-reviews.md para futuras ejecuciones.
  if [ "$SELF_HEAL" = "1" ] && [ "${FIX_EXITOSO:-0}" = "1" ] && should_run fix; then
    bash "$SCRIPTS_DIR/self_heal.sh" \
      "${CLAUDE_JSON:-$PROGRESS_DIR/${SESSION_ID}-claude-review.json}" \
      "$ISSUE" "$SESSION_ID" || true
  fi

  should_run review-codex  && phase_review_codex

  local gate_rc=0
  if should_run gate; then
    phase_gate || gate_rc=$?
  fi

  echo ""
  if [ "${FIX_EXITOSO:-0}" = "1" ]; then
    echo "⚠ Pipeline completado: se agotaron los $MAX_FIX intentos de fix con bloqueantes pendientes."
    echo "  Considera revisar manualmente o ejecutar --from fix con --max-fix mayor."
    if [ "$SELF_HEAL" = "1" ]; then
      echo "  Self-healing ejecutado: revisa progress/${SESSION_ID}-fix-prompt-healed.md"
    else
      echo "  Self-healing desactivado (--no-self-heal). Actívalo para mejorar prompts automáticamente."
    fi
  elif [ "$gate_rc" -eq 0 ]; then
    echo "✅ Pipeline completado. Revisa la recomendación arriba."
  else
    echo "⚠ Pipeline completado CON bloqueantes. Revisa antes de mergear."
  fi
  exit "$gate_rc"
}

main
