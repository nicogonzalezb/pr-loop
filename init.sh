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

# 7. Overlay prompts-local (local pisa base; fallback si no hay local)
_overlay_tmp="$(mktemp -d)"
_overlay_base="$_overlay_tmp/prompts"
_overlay_local="$_overlay_tmp/prompts-local"
mkdir -p "$_overlay_base" "$_overlay_local"
echo "BASE_MARKER" > "$_overlay_base/overlay-test.md"
echo "LOCAL_MARKER" > "$_overlay_local/overlay-test.md"
if _overlay_out="$(
  REPO_ROOT="$_overlay_tmp" \
  PROMPTS_DIR="$_overlay_base" \
  PROMPTS_LOCAL_DIR="$_overlay_local" \
  bash "$REPO_ROOT/scripts/render_prompt.sh" overlay-test.md 2>/dev/null
)" && [ "$_overlay_out" = "LOCAL_MARKER" ]; then
  ok "render_prompt overlay (local pisa base)"
else
  fail "render_prompt overlay — esperaba LOCAL_MARKER"
fi
rm -rf "$_overlay_tmp"
if _fallback_out="$(
  PROMPTS_LOCAL_DIR="/nonexistent/prompts-local" \
  bash "$REPO_ROOT/scripts/render_prompt.sh" implement-issue.md 2>/dev/null | head -c 20
)" && [ -n "$_fallback_out" ]; then
  ok "render_prompt fallback (sin prompts-local)"
else
  fail "render_prompt fallback — no resolvió prompt base"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
  ok "Entorno listo"
  exit 0
fi
fail "Smoke tests fallaron"
exit 1
