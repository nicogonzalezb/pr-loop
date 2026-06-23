#!/usr/bin/env bash
# Aislamiento por issue vía git worktree (obligatorio en pr-loop).
#
# Uso (desde pr-loop.sh o tests):
#   worktree.sh verify
#   worktree.sh ensure-dir
#   worktree.sh add-issue <issue_branch> <worktree_path> [base_branch]
#   worktree.sh add-pr <head_ref> <worktree_path>
set -euo pipefail

: "${REPO_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORKTREES_DIR="${WORKTREES_DIR:-$REPO_ROOT/.worktrees}"

worktree_verify() {
  if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "❌ pr-loop requiere un repositorio git." >&2
    echo "   Inicializa con: git init && git remote add origin <url>" >&2
    return 1
  fi
  if ! git -C "$REPO_ROOT" worktree list &>/dev/null; then
    echo "❌ git worktree no disponible (necesitas git ≥ 2.5)." >&2
    return 1
  fi
  return 0
}

worktree_ensure_dir() {
  mkdir -p "$WORKTREES_DIR"
}

worktree_add_issue() {
  local issue="$1" path="$2" base="${3:-main}"
  worktree_ensure_dir
  git -C "$REPO_ROOT" fetch origin "$base" 2>/dev/null || true
  if git -C "$REPO_ROOT" worktree add -b "$issue" "$path" "origin/$base" 2>/dev/null; then
    return 0
  fi
  git -C "$REPO_ROOT" worktree add "$path" "$issue"
}

worktree_add_pr() {
  local head_ref="$1" path="$2"
  worktree_ensure_dir
  git -C "$REPO_ROOT" fetch origin "$head_ref" 2>/dev/null || true
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$head_ref"; then
    git -C "$REPO_ROOT" worktree add "$path" "$head_ref"
  elif git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/$head_ref"; then
    git -C "$REPO_ROOT" worktree add -b "$head_ref" "$path" "origin/$head_ref" 2>/dev/null \
      || git -C "$REPO_ROOT" worktree add "$path" "origin/$head_ref"
  else
    echo "❌ Rama del PR no encontrada: $head_ref" >&2
    return 1
  fi
}

cmd="${1:-}"
case "$cmd" in
  verify)       worktree_verify ;;
  ensure-dir)   worktree_ensure_dir ;;
  add-issue)    worktree_add_issue "${2:?issue}" "${3:?path}" "${4:-main}" ;;
  add-pr)       worktree_add_pr "${2:?head_ref}" "${3:?path}" ;;
  *)
    echo "Uso: worktree.sh verify|ensure-dir|add-issue|add-pr" >&2
    exit 2
    ;;
esac
