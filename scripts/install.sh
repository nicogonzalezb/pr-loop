#!/usr/bin/env bash
# Instala pr-loop en un proyecto: git worktree, directorios, .gitignore y scaffold issues/.
#
# Uso:
#   bash pr-loop.sh install
#   bash scripts/install.sh
#
# Idempotente: se puede correr varias veces sin romper nada.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ok()   { echo "✓ $*"; }
note() { echo "  → $*"; }

echo "=== pr-loop install ==="
echo "  Repo: $REPO_ROOT"
echo ""

# 1. Git + git worktree (obligatorio)
if ! bash "$SCRIPT_DIR/worktree.sh" verify; then
  exit 1
fi
ok "repositorio git con soporte worktree"

# 2. Directorios de runtime
mkdir -p "$REPO_ROOT/.worktrees" "$REPO_ROOT/progress"
ok "directorios .worktrees/ y progress/"

# 3. .gitignore
GITIGNORE="$REPO_ROOT/.gitignore"
touch "$GITIGNORE"
for entry in progress/ .worktrees/ '*.raw.json' .pr-loop-claude-review.json; do
  if grep -qxF "$entry" "$GITIGNORE" 2>/dev/null; then
    ok ".gitignore ya tiene: $entry"
  else
    echo "$entry" >> "$GITIGNORE"
    ok ".gitignore actualizado: $entry"
  fi
done

# 4. .pr-loop.env de ejemplo (no pisa si existe)
ENV_FILE="$REPO_ROOT/.pr-loop.env"
if [ -f "$ENV_FILE" ]; then
  ok ".pr-loop.env ya existe (no se modifica)"
else
  cat > "$ENV_FILE" <<'EOF'
# Config de pr-loop — sourced por pr-loop.sh
INIT_SCRIPT=./init.sh
PR_BASE_BRANCH=main
CURSOR_MODEL=composer-2.5
CLAUDE_MODEL=opus
EOF
  ok ".pr-loop.env creado (ajusta INIT_SCRIPT y modelos)"
fi

# 5. issues/ scaffold (contrato + template + orden)
mkdir -p "$REPO_ROOT/issues"
for f in CONTRATO.md TEMPLATE.md; do
  if [ -f "$REPO_ROOT/issues/$f" ]; then
    ok "issues/$f ya existe"
  elif [ -f "$SCRIPT_DIR/../issues/$f" ]; then
    cp "$SCRIPT_DIR/../issues/$f" "$REPO_ROOT/issues/$f"
    ok "issues/$f copiado"
  else
    note "advertencia: no se encontró issues/$f (ni en proyecto ni en pr-loop core); init.sh fallará si falta"
  fi
done
if [ ! -f "$REPO_ROOT/issues/orden-de-trabajo.md" ]; then
  cat > "$REPO_ROOT/issues/orden-de-trabajo.md" <<'EOF'
# Orden de trabajo

Cola priorizada para `pr-loop.sh`. `scripts/check_order.sh` avisa si un issue no está listado o está bloqueado.

## Listos para implementar

| Orden | Issue | Título | Notas |
|-------|-------|--------|-------|

## Bloqueados

| Issue | Título | Motivo |
|-------|--------|--------|
EOF
  ok "issues/orden-de-trabajo.md creado (plantilla vacía)"
else
  ok "issues/orden-de-trabajo.md ya existe"
fi

echo ""
echo "Instalación lista. Siguiente:"
echo "  1. Ajusta .pr-loop.env y crea init.sh con los tests de tu stack"
echo "  2. bash pr-loop.sh issue-N --dry-run"
echo "  3. bash pr-loop.sh issue-N"
echo ""
echo "Aislamiento: cada issue usa git worktree en .worktrees/issue-N (obligatorio)."
