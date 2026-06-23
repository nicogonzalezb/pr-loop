#!/usr/bin/env bash
# Health check de pr-loop (dogfooding). Contrato: exit 0 = OK, exit 1 = bloqueante.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

FAILED=0
ok()   { echo "✓ $*"; }
fail() { echo "✗ $*" >&2; FAILED=1; }

echo "=== init.sh — pr-loop smoke tests ==="

# 1. Dependencias del pipeline
for cmd in bash git jq; do
  command -v "$cmd" &>/dev/null && ok "$cmd" || fail "$cmd no encontrado"
done

# 2. Sintaxis de scripts bash
while IFS= read -r -d '' f; do
  if bash -n "$f" 2>/dev/null; then
    ok "syntax: ${f#"$REPO_ROOT"/}"
  else
    fail "syntax error: $f"
  fi
done < <(find "$REPO_ROOT" -maxdepth 2 \( -name '*.sh' -o -name 'init.sh' \) -print0)

# 3. Shellcheck opcional
if command -v shellcheck &>/dev/null; then
  while IFS= read -r -d '' f; do
    if shellcheck -x "$f" &>/dev/null; then
      ok "shellcheck: ${f#"$REPO_ROOT"/}"
    else
      fail "shellcheck: $f"
    fi
  done < <(find "$REPO_ROOT/scripts" "$REPO_ROOT/pr-loop.sh" -type f -print0 2>/dev/null)
else
  echo "  (shellcheck no instalado — omitido)"
fi

# 4. Dry-run del orquestador (preflight sin agentes)
if bash "$REPO_ROOT/pr-loop.sh" issue-1 --dry-run &>/dev/null; then
  ok "pr-loop.sh --dry-run"
else
  fail "pr-loop.sh --dry-run"
fi

# 5. Archivos clave del dogfooding
for f in CLAUDE.md issues/CONTRATO.md issues/TEMPLATE.md issues/orden-de-trabajo.md; do
  [ -f "$REPO_ROOT/$f" ] && ok "$f existe" || fail "$f falta"
done

# 6. git worktree (obligatorio)
if bash "$REPO_ROOT/scripts/worktree.sh" verify &>/dev/null; then
  ok "git worktree"
else
  fail "git worktree — corre: bash pr-loop.sh install"
fi
if [ -d "$REPO_ROOT/.worktrees" ] && grep -qxF '.worktrees/' "$REPO_ROOT/.gitignore" 2>/dev/null; then
  ok ".worktrees/ en .gitignore"
else
  fail ".worktrees/ — corre: bash pr-loop.sh install"
fi

# 7. Audit trail (state_append_history)
if bash -c 'source "$1/scripts/state.sh"; declare -f state_append_history' _ "$REPO_ROOT" &>/dev/null; then
  ok "state_append_history definido"
  hist_tmp="$(mktemp)"
  if HISTORY_FILE="$hist_tmp" \
     HISTORY_SESSION="test-session" \
     HISTORY_ISSUE="issue-test" \
     HISTORY_ISSUE_NUM="99" \
     HISTORY_PR="42" \
     HISTORY_FROM="review-claude" \
     HISTORY_PHASES="review-claude,gate" \
     HISTORY_FIX_ATTEMPTS="1" \
     HISTORY_BLOQUEANTES="0" \
     HISTORY_FIX_STATUS="éxito" \
     HISTORY_GATE_VERDICT="MERGE OK" \
     HISTORY_GATE_RC="0" \
     bash -c 'source "$1/scripts/state.sh"; state_append_history' _ "$REPO_ROOT" \
     && grep -q 'test-session' "$hist_tmp" \
     && grep -q 'Reanudado desde' "$hist_tmp"; then
    ok "state_append_history escribe entrada"
  else
    fail "state_append_history no escribió entrada válida"
  fi
  rm -f "$hist_tmp"
else
  fail "state_append_history no definido en scripts/state.sh"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  ok "Entorno listo"
  exit 0
fi
fail "Smoke tests fallaron"
exit 1
