#!/usr/bin/env bash
# Gate final del pipeline: consolida las dos reviews, comenta en el PR y emite
# una recomendación de merge. NO mergea automáticamente (decisión humana).
#
# Uso:
#   gate_merge.sh <pr_num> <issue> <claude_json> <codex_md>
# Exit code:
#   0 = sin bloqueantes (recomendado merge)
#   1 = hay bloqueantes o no se pudieron leer las reviews
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${REPO_ROOT:=$(cd "$SCRIPT_DIR/.." && pwd)}"
# shellcheck source=scripts/budget.sh
source "$SCRIPT_DIR/budget.sh"

PR_NUM="${1:?pr_num requerido}"
ISSUE="${2:?issue requerido}"
CLAUDE_JSON="${3:?claude_json requerido}"
CODEX_MD="${4:?codex_md requerido}"

# ── Ejecutar INIT_SCRIPT si está definido ────────────────────────────
# Exporta INIT_SCRIPT=/ruta/a/init.sh antes de llamar a este script.
# El script debe salir con 0 si todo OK, 1 si hay problemas.
init_exit_code=0        # 0 = no aplica o pasó; 1 = falló
init_ran=false
init_resumen="no configurado"
if [ -n "${INIT_SCRIPT:-}" ] && [ -f "$INIT_SCRIPT" ]; then
  echo "→ Ejecutando INIT_SCRIPT: $INIT_SCRIPT"
  if bash "$INIT_SCRIPT"; then
    init_exit_code=0
    init_resumen="pasó (exit 0)"
    init_ran=true
  else
    init_exit_code=$?
    init_resumen="falló (exit $init_exit_code)"
    init_ran=true
  fi
elif [ -n "${INIT_SCRIPT:-}" ]; then
  echo "⚠ INIT_SCRIPT definido pero no encontrado: $INIT_SCRIPT" >&2
  init_resumen="archivo no encontrado: $INIT_SCRIPT"
fi

# ── Parse review Claude (JSON estructurado) ──────────────────────────
claude_veredicto="(sin review)"
claude_bloqueantes=0
if [ -s "$CLAUDE_JSON" ] && command -v jq &>/dev/null; then
  claude_veredicto="$(jq -r '.veredicto // "(desconocido)"' "$CLAUDE_JSON" 2>/dev/null || echo "(parse error)")"
  claude_bloqueantes="$(jq -r '(.bloqueantes // []) | length' "$CLAUDE_JSON" 2>/dev/null || true)"
  claude_bloqueantes="${claude_bloqueantes:-0}"
fi

# ── Veredicto Codex: determinista vía INIT_SCRIPT, fallback heurístico ──
codex_bloqueantes=0
codex_resumen="sin bloqueantes críticos"
codex_metodo=""
if [ "$init_ran" = true ]; then
  # Veredicto determinista: el exit code de INIT_SCRIPT es la fuente de verdad.
  # codex_bloqueantes se deja en 0 — init_exit_code ya se suma en total_bloqueantes.
  codex_bloqueantes=0
  codex_metodo="determinista (INIT_SCRIPT)"
  if [ "$init_exit_code" -gt 0 ]; then
    codex_resumen="$init_resumen — revisar salida de $INIT_SCRIPT"
  else
    codex_resumen="$init_resumen"
  fi
elif [ -s "$CODEX_MD" ]; then
  # Fallback heurístico: grep sobre el markdown de Codex.
  # ADVERTENCIA: puede producir falsos positivos (ej. "no hay issues críticos"
  # suma al contador). Instala INIT_SCRIPT para obtener un veredicto real.
  codex_metodo="heurístico (instala INIT_SCRIPT para veredicto real)"
  codex_bloqueantes="$(grep -ciE 'blocker|must fix|critical|crítico|bloqueante|high severity|severidad alta' "$CODEX_MD" 2>/dev/null || true)"
  codex_bloqueantes="${codex_bloqueantes:-0}"
  if [ "$codex_bloqueantes" -gt 0 ]; then
    codex_resumen="$codex_bloqueantes posible(s) bloqueante(s) — revisar $CODEX_MD"
  fi
else
  codex_resumen="(sin review)"
  codex_metodo="sin datos"
fi

# ── CI de GitHub (si gh disponible) ──────────────────────────────────
ci_estado="desconocido"
if command -v gh &>/dev/null; then
  if gh pr checks "$PR_NUM" &>/dev/null; then
    if gh pr checks "$PR_NUM" 2>/dev/null | grep -qiE '\bfail|✗|error'; then
      ci_estado="rojo"
    else
      ci_estado="verde/pending"
    fi
  fi
fi

# ── Presupuesto de corrida (claude -p) ───────────────────────────────
budget_line="$(budget_summary_line)"
budget_exceeded=0
if jq -e '.pr_loop.budget.exceeded == true' "${STATE_FILE:-$REPO_ROOT/progress/current.json}" &>/dev/null; then
  budget_exceeded=1
fi

# ── Decisión ─────────────────────────────────────────────────────────
# init_exit_code ya vale 0 si INIT_SCRIPT no corrió (no suma bloqueante).
total_bloqueantes=$(( claude_bloqueantes + codex_bloqueantes + init_exit_code ))
recomendacion=""
exit_code=0
if [ "$total_bloqueantes" -eq 0 ] && [ "$ci_estado" != "rojo" ]; then
  recomendacion="MERGE OK (decisión humana)"
  exit_code=0
else
  recomendacion="NO mergear aún — $total_bloqueantes bloqueante(s); CI=$ci_estado"
  exit_code=1
fi

# ── Resumen en consola ───────────────────────────────────────────────
summary="$(cat <<EOF
PR #$PR_NUM — $ISSUE
  Claude Opus:   $claude_veredicto ($claude_bloqueantes bloqueantes)
  Codex review:  $codex_resumen [$codex_metodo]
  Tests (INIT_SCRIPT): $init_resumen
  Presupuesto:   $budget_line
  CI GitHub:     $ci_estado
  Total bloqueantes: $total_bloqueantes
  → $recomendacion
EOF
)"
echo ""
echo "$summary"
echo ""

# ── Comentario en el PR ──────────────────────────────────────────────
if command -v gh &>/dev/null; then
  # Iconos según resultado
  init_icono="—"
  if [ "$init_ran" = true ]; then
    [ "$init_exit_code" -eq 0 ] && init_icono="✓ verde" || init_icono="✗ rojo"
  fi

  body="$(cat <<EOF
## Pipeline PR multi-agente — resumen de reviews

| Revisor | Veredicto | Bloqueantes |
|---------|-----------|-------------|
| Claude Opus (\`claude -p\`) | \`$claude_veredicto\` | $claude_bloqueantes |
| Codex (\`codex review\`) | $codex_metodo | $codex_bloqueantes |
| Tests (\`INIT_SCRIPT\`) | $init_icono | $init_exit_code |
| Presupuesto (\`claude -p\`) | $budget_line | $budget_exceeded |

- CI GitHub: **$ci_estado**
- Total bloqueantes: **$total_bloqueantes**
- Recomendación: **$recomendacion**

<sub>Generado por \`pr-loop.sh\`. Reviews completas en \`$CLAUDE_JSON\` y \`$CODEX_MD\`.</sub>
EOF
)"
  if gh pr comment "$PR_NUM" --body "$body" &>/dev/null; then
    echo "✓ Comentario publicado en PR #$PR_NUM"
  else
    echo "⚠ No se pudo comentar en el PR (¿gh sin permisos?). Resumen quedó en consola." >&2
  fi
fi

exit "$exit_code"
