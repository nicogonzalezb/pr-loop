#!/usr/bin/env bash
# Outer loop / planner — descompone issues épicos en issues atómicos (human-gated).
#
# Flujo:
#   1. Lee issue épico + doc de arquitectura (source-of-truth)
#   2. Propone sub-issues atómicos (claude -p)
#   3. Human-gated: aprobación explícita antes de crear nada
#   4. Emite issues con gh issue create (formato issues/CONTRATO.md)
#
# Uso:
#   bash plan-loop.sh 5
#   bash plan-loop.sh 5 --dry-run
#   bash plan-loop.sh 5 --arch-doc CLAUDE.md
#   bash plan-loop.sh 5 --from approve    # reanuda tras propuesta existente
#   bash plan-loop.sh 5 --proposal progress/...-proposal.json
#
# Flags:
#   --dry-run       Sin agente ni gh issue create
#   --arch-doc PATH Doc de arquitectura (default: PLAN_ARCH_DOC → ARCHITECTURE.md → CLAUDE.md)
#   --from FASE     propose | approve | create
#   --proposal FILE Usar propuesta existente (omite propose)
#
# Variables:
#   PLAN_ARCH_DOC, PLAN_MODEL, PR_LOOP_DRY_RUN, SESSION_ID
#
# Separado del inner loop (pr-loop.sh); comparte scripts/ y prompts/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"
SCRIPTS_DIR="$REPO_ROOT/scripts"
PROGRESS_DIR="$REPO_ROOT/progress"

if [ -f "$REPO_ROOT/.pr-loop.env" ]; then
  set -a
  # shellcheck source=/dev/null
  source "$REPO_ROOT/.pr-loop.env"
  set +a
fi

export REPO_ROOT
PROMPTS_DIR="$REPO_ROOT/prompts"
export PROMPTS_DIR

# ── Parseo ───────────────────────────────────────────────────────────
EPIC=""
FROM=""
DRY_RUN=0
ARCH_DOC_ARG=""
PROPOSAL_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)      DRY_RUN=1; shift;;
    --arch-doc)     ARCH_DOC_ARG="${2:?--arch-doc requiere path}"; shift 2;;
    --from)         FROM="${2:?--from requiere fase}"; shift 2;;
    --proposal)     PROPOSAL_FILE="${2:?--proposal requiere archivo}"; shift 2;;
    -h|--help)
      sed -n '2,35p' "$0"
      exit 0
      ;;
    [0-9]*)
      EPIC="$1"
      shift
      ;;
    *)
      echo "❌ Argumento no reconocido: $1" >&2
      exit 2
      ;;
  esac
done

[ -n "$EPIC" ] || { echo "❌ Indica el número del issue épico (ej. bash plan-loop.sh 5)." >&2; exit 2; }
[ "$DRY_RUN" = "1" ] && export PR_LOOP_DRY_RUN=1

SESSION_ID="${SESSION_ID:-$(date -u +%Y%m%dT%H%M%S)}"
PROPOSAL_JSON="${PROPOSAL_FILE:-$PROGRESS_DIR/${SESSION_ID}-plan-proposal.json}"
CREATED_JSON="$PROGRESS_DIR/${SESSION_ID}-plan-created.json"

# ── Resolver doc de arquitectura ─────────────────────────────────────
resolve_arch_doc() {
  local candidate="" warned=0

  if [ -n "$ARCH_DOC_ARG" ]; then
    candidate="$ARCH_DOC_ARG"
  elif [ -n "${PLAN_ARCH_DOC:-}" ]; then
    candidate="$PLAN_ARCH_DOC"
  elif [ -f "$REPO_ROOT/ARCHITECTURE.md" ]; then
    candidate="ARCHITECTURE.md"
  elif [ -f "$REPO_ROOT/CLAUDE.md" ]; then
    candidate="CLAUDE.md"
  fi

  if [ -n "$candidate" ]; then
    if [ -f "$REPO_ROOT/$candidate" ]; then
      ARCH_DOC="$REPO_ROOT/$candidate"
    elif [ -f "$candidate" ]; then
      ARCH_DOC="$candidate"
    else
      echo "⚠ Doc de arquitectura no encontrado: $candidate — descomposición con menos contexto." >&2
      ARCH_DOC="$(mktemp)"
      : > "$ARCH_DOC"
      warned=1
    fi
  else
    echo "⚠ Sin doc de arquitectura (PLAN_ARCH_DOC / ARCHITECTURE.md / CLAUDE.md) — descomposición con menos contexto." >&2
    ARCH_DOC="$(mktemp)"
    : > "$ARCH_DOC"
    warned=1
  fi

  ARCH_DOC_WARN="$warned"
}

# ── Preflight ────────────────────────────────────────────────────────
preflight() {
  echo "=== Preflight (plan-loop) ==="
  local fail=0
  for tool in bash gh jq claude; do
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
      echo "  ✗ gh no autenticado"
      fail=1
    fi
  fi

  for f in issues/CONTRATO.md issues/TEMPLATE.md prompts/decompose-epic.md; do
    if [ -f "$REPO_ROOT/$f" ]; then
      echo "  ✓ $f"
    else
      echo "  ✗ $f falta"
      fail=1
    fi
  done

  if [ "$fail" = "1" ]; then
    echo "❌ Preflight falló." >&2
    [ "$DRY_RUN" = "1" ] && echo "  (dry-run: continúo)" || exit 1
  fi
  echo ""
}

# ── Mostrar propuesta ────────────────────────────────────────────────
show_proposal() {
  echo "=== Propuesta de descomposición (épico #$EPIC) ==="
  jq -r '
    if .atomic then
      "  ℹ Issue ya es ATÓMICO — no se descompondrá.\n  Motivo: \(.atomic_reason)\n  → Usa: bash pr-loop.sh issue-\(.epic)"
    else
      "  Sub-issues propuestos: \(.sub_issues | length)\n" +
      (if (.assumptions | length) > 0 then
        "  Supuestos globales:\n" + (.assumptions | map("    - " + .) | join("\n")) + "\n"
      else "" end) +
      (.sub_issues | to_entries[] |
        "\n  [\(.key + 1)] \(.value.title)" +
        (if (.value.assumptions | length) > 0 then
          "\n      Supuestos: " + (.value.assumptions | join("; "))
        else "" end)
      )
    end
  ' "$PROPOSAL_JSON"
  echo ""
  echo "  Archivo completo: $PROPOSAL_JSON"
  echo ""
}

# ── Human gate ───────────────────────────────────────────────────────
human_gate() {
  local atomic
  atomic="$(jq -r '.atomic' "$PROPOSAL_JSON")"
  if [ "$atomic" = "true" ]; then
    echo "ℹ Issue épico ya es atómico. No hay nada que crear."
    return 2
  fi

  while true; do
    show_proposal
    echo "¿Aprobar descomposición y crear issues en GitHub?"
    echo "  s = sí, crear   |   n = no, cancelar   |   r = re-proponer"
    read -r -p "> " ans
    case "$ans" in
      s|S|si|sí|y|Y|yes)
        return 0
        ;;
      n|N|no)
        echo "Cancelado — no se creó ningún issue."
        return 1
        ;;
      r|R|re)
        echo "→ Re-proponiendo..."
        phase_propose
        ;;
      *)
        echo "  Respuesta no reconocida. Usa s, n o r."
        ;;
    esac
  done
}

# ── Fases ────────────────────────────────────────────────────────────
phase_propose() {
  echo "=== Fase: Proponer descomposición ==="
  if [ -n "$PROPOSAL_FILE" ] && [ -f "$PROPOSAL_FILE" ]; then
    echo "  Usando propuesta existente: $PROPOSAL_FILE"
    bash "$SCRIPTS_DIR/plan_validate.sh" "$PROPOSAL_FILE"
    echo ""
    return 0
  fi
  bash "$SCRIPTS_DIR/plan_propose.sh" "$EPIC" "$ARCH_DOC" "$SESSION_ID" "$PROPOSAL_JSON"
  echo ""
}


phase_create() {
  echo "=== Fase: Crear issues ==="
  bash "$SCRIPTS_DIR/plan_create.sh" "$PROPOSAL_JSON" "$CREATED_JSON"
  echo ""
}

should_run() {
  local phase="$1"
  if [ -z "$FROM" ]; then return 0; fi
  local started=0
  for p in propose approve create; do
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
  resolve_arch_doc

  echo "Outer loop / planner (plan-loop)"
  echo "  Épico:      #$EPIC"
  echo "  Arch doc:   ${ARCH_DOC}$([ "$ARCH_DOC_WARN" = "1" ] && echo ' (degradado)')"
  echo "  Sesión:     $SESSION_ID"
  echo "  Dry-run:    $([ "$DRY_RUN" = 1 ] && echo sí || echo no)"
  echo "  Propuesta:  $PROPOSAL_JSON"
  echo ""

  local approved=0

  if should_run propose; then
    phase_propose
  fi

  if should_run approve; then
    if [ ! -f "$PROPOSAL_JSON" ]; then
      if [ "$DRY_RUN" = "1" ]; then
        echo "  [dry-run] sin propuesta — fase propose no genera JSON en dry-run."
      else
        echo "❌ No hay propuesta en $PROPOSAL_JSON" >&2
        exit 1
      fi
    elif [ "$DRY_RUN" = "1" ]; then
      bash "$SCRIPTS_DIR/plan_validate.sh" "$PROPOSAL_JSON"
      show_proposal
      echo "  [dry-run] human-gate omitido — no se crearían issues sin aprobación explícita."
    else
      bash "$SCRIPTS_DIR/plan_validate.sh" "$PROPOSAL_JSON"
      if human_gate; then
        approved=1
      else
        exit 0
      fi
    fi
  fi

  if should_run create; then
    if [ "$DRY_RUN" = "1" ]; then
      if [ -f "$PROPOSAL_JSON" ]; then
        phase_create
      fi
    elif [ "$approved" = "1" ] || [ "$FROM" = "create" ]; then
      phase_create
    fi
  fi

  echo "✅ plan-loop completado."
  if [ -f "$CREATED_JSON" ]; then
    echo "  Issues creados: $CREATED_JSON"
  fi
}

main
