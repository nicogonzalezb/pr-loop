#!/usr/bin/env bash
# Limpia worktrees huérfanos en .worktrees/ y opcionalmente artefactos en progress/.
#
# Uso:
#   cleanup.sh list
#   cleanup.sh issue-N [--yes] [--force] [--progress]
#   cleanup.sh --all [--yes] [--force] [--progress]
#
# Flags:
#   --yes      Sin confirmación interactiva
#   --force    Elimina worktrees con cambios sin commitear (git worktree remove --force)
#   --progress También borra artefactos de progress/ asociados al issue o sesiones viejas
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Resolver repo principal (si se invoca desde un worktree enlazado).
resolve_main_repo() {
  local git_common
  git_common="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -z "$git_common" ]; then
    echo "$REPO_ROOT"
    return 0
  fi
  dirname "$git_common"
}

MAIN_REPO="$(resolve_main_repo)"
WORKTREES_DIR="${WORKTREES_DIR:-$MAIN_REPO/.worktrees}"
PROGRESS_DIR="${PROGRESS_DIR:-$MAIN_REPO/progress}"

YES=0
FORCE=0
WITH_PROGRESS=0
TARGET_ALL=0
TARGETS=()

usage() {
  sed -n '2,20p' "$0"
  echo ""
  echo "Ejemplos:"
  echo "  bash pr-loop.sh cleanup list"
  echo "  bash pr-loop.sh cleanup issue-10 --yes"
  echo "  bash pr-loop.sh cleanup --all --yes --progress"
}

die() {
  echo "❌ $*" >&2
  exit 1
}

worktree_path_for() {
  local name="$1"
  echo "$WORKTREES_DIR/$name"
}

normalize_target() {
  local raw="$1"
  if [[ "$raw" =~ ^issue-[0-9]+$ ]]; then
    echo "$raw"
  elif [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "issue-$raw"
  else
    echo "$raw"
  fi
}

worktree_is_registered() {
  local path="$1"
  git -C "$MAIN_REPO" worktree list --porcelain 2>/dev/null \
    | awk -v p="$path" '$1 == "worktree" && $2 == p { found=1 } END { exit !found }'
}

worktree_is_dirty() {
  local path="$1"
  [ -d "$path" ] || return 1
  [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]
}

current_worktree_path() {
  git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null || pwd -P
}

cleanup_list() {
  if [ ! -d "$WORKTREES_DIR" ]; then
    echo "No hay directorio $WORKTREES_DIR"
    return 0
  fi

  local found=0
  echo "Worktrees en $WORKTREES_DIR:"
  echo ""
  printf "  %-20s %-10s %s\n" "NOMBRE" "ESTADO" "RAMA"
  printf "  %-20s %-10s %s\n" "------" "------" "----"

  local entry name path branch state
  for entry in "$WORKTREES_DIR"/*; do
    [ -e "$entry" ] || continue
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    path="$entry"
    found=1

    if worktree_is_dirty "$path"; then
      state="sucio"
    else
      state="limpio"
    fi

    branch="$(git -C "$path" branch --show-current 2>/dev/null || echo "?")"
    printf "  %-20s %-10s %s\n" "$name" "$state" "$branch"
  done

  if [ "$found" = "0" ]; then
    echo "  (vacío)"
  fi

  echo ""
  echo "Registro git worktree:"
  git -C "$MAIN_REPO" worktree list 2>/dev/null || true
}

confirm() {
  local prompt="$1"
  if [ "$YES" = "1" ]; then
    return 0
  fi
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

remove_worktree() {
  local name="$1"
  local path
  path="$(worktree_path_for "$name")"

  if [ ! -d "$path" ]; then
    echo "  ⊘ $name — no existe en $WORKTREES_DIR"
    return 0
  fi

  local cwd
  cwd="$(current_worktree_path)"
  if [ "$(cd "$path" && pwd -P)" = "$(cd "$cwd" && pwd -P)" ]; then
    echo "  ✗ $name — no se puede eliminar el worktree actual ($path)" >&2
    return 1
  fi

  if worktree_is_dirty "$path" && [ "$FORCE" != "1" ]; then
    echo "  ✗ $name — cambios sin commitear; usa --force para forzar" >&2
    return 1
  fi

  if worktree_is_registered "$path"; then
    if [ "$FORCE" = "1" ]; then
      git -C "$MAIN_REPO" worktree remove --force "$path"
    else
      git -C "$MAIN_REPO" worktree remove "$path"
    fi
  else
    echo "  ⚠ $name — no registrado en git worktree; elimino directorio"
    if [ "$FORCE" = "1" ]; then
      rm -rf "$path"
    elif worktree_is_dirty "$path"; then
      echo "  ✗ $name — directorio huérfano con cambios; usa --force" >&2
      return 1
    else
      rm -rf "$path"
    fi
  fi

  echo "  ✓ $name — worktree eliminado"
}

cleanup_progress_for_issue() {
  local issue="$1"
  local issue_num="${issue#issue-}"
  local removed=0

  if [ ! -d "$PROGRESS_DIR" ]; then
    return 0
  fi

  local f
  for f in "$PROGRESS_DIR"/pipeline-"$issue"-*.log; do
    [ -e "$f" ] || continue
    rm -f "$f"
    echo "  ✓ progress: eliminado $(basename "$f")"
    removed=1
  done

  if [ -f "$PROGRESS_DIR/current.json" ] && command -v jq &>/dev/null; then
    local current_issue session_id
    current_issue="$(jq -r '.pr_loop.issue // empty' "$PROGRESS_DIR/current.json" 2>/dev/null || true)"
    session_id="$(jq -r '.pr_loop.session_id // empty' "$PROGRESS_DIR/current.json" 2>/dev/null || true)"
    if [ "$current_issue" = "$issue" ] && [ -n "$session_id" ]; then
      local artifact
      for artifact in "$PROGRESS_DIR"/"$session_id"-*; do
        [ -e "$artifact" ] || continue
        rm -f "$artifact"
        echo "  ✓ progress: eliminado $(basename "$artifact")"
        removed=1
      done
      local tmp
      tmp="$(mktemp)"
      jq 'del(.pr_loop) | .estado = "idle"' "$PROGRESS_DIR/current.json" > "$tmp" \
        && mv "$tmp" "$PROGRESS_DIR/current.json"
      echo "  ✓ progress: limpiado pr_loop en current.json"
      removed=1
    fi
  fi

  if [ "$removed" = "0" ]; then
    echo "  ⊘ progress: sin artefactos para $issue"
  fi
}

cleanup_progress_all() {
  if [ ! -d "$PROGRESS_DIR" ]; then
    return 0
  fi

  local f base removed=0
  for f in "$PROGRESS_DIR"/*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "current.json" ] && continue
    rm -f "$f"
    echo "  ✓ progress: eliminado $base"
    removed=1
  done

  if [ -f "$PROGRESS_DIR/current.json" ] && command -v jq &>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    jq 'del(.pr_loop) | .estado = "idle"' "$PROGRESS_DIR/current.json" > "$tmp" \
      && mv "$tmp" "$PROGRESS_DIR/current.json"
    echo "  ✓ progress: limpiado pr_loop en current.json"
    removed=1
  fi

  if [ "$removed" = "0" ]; then
    echo "  ⊘ progress: sin artefactos que borrar"
  fi
}

prune_worktrees() {
  git -C "$MAIN_REPO" worktree prune
  echo "  ✓ git worktree prune"
}

collect_targets() {
  if [ ! -d "$WORKTREES_DIR" ]; then
    return 0
  fi
  local entry name
  for entry in "$WORKTREES_DIR"/*; do
    [ -d "$entry" ] || continue
    name="$(basename "$entry")"
    TARGETS+=("$name")
  done
}

run_cleanup() {
  local mode="${1:-}"
  if ! git -C "$MAIN_REPO" rev-parse --is-inside-work-tree &>/dev/null; then
    die "no es un repositorio git"
  fi
  if ! git -C "$MAIN_REPO" worktree list &>/dev/null; then
    die "git worktree no disponible"
  fi

  if [ "$mode" = "list" ]; then
    cleanup_list
    return 0
  fi

  if [ "${#TARGETS[@]}" -eq 0 ]; then
    if [ "$TARGET_ALL" = "1" ]; then
      collect_targets
    else
      die "indica issue-N, --all o list"
    fi
  fi

  if [ "${#TARGETS[@]}" -eq 0 ]; then
    echo "No hay worktrees que limpiar."
    if [ "$WITH_PROGRESS" = "1" ] && [ "$TARGET_ALL" = "1" ]; then
      echo ""
      echo "=== Limpieza de progress/ ==="
      cleanup_progress_all
    fi
    prune_worktrees
    return 0
  fi

  echo "Repo:      $MAIN_REPO"
  echo "Worktrees: ${TARGETS[*]}"
  echo "Force:     $([ "$FORCE" = "1" ] && echo sí || echo no)"
  echo "Progress:  $([ "$WITH_PROGRESS" = "1" ] && echo sí || echo no)"
  echo ""

  if ! confirm "¿Eliminar ${#TARGETS[@]} worktree(s)?"; then
    echo "Cancelado."
    exit 0
  fi

  echo ""
  echo "=== Eliminando worktrees ==="
  local failed=0 name
  for name in "${TARGETS[@]}"; do
    remove_worktree "$name" || failed=1
  done

  prune_worktrees

  if [ "$WITH_PROGRESS" = "1" ]; then
    echo ""
    echo "=== Limpieza de progress/ ==="
    if [ "$TARGET_ALL" = "1" ]; then
      cleanup_progress_all
    else
      for name in "${TARGETS[@]}"; do
        cleanup_progress_for_issue "$name"
      done
    fi
  fi

  echo ""
  if [ "$failed" = "1" ]; then
    die "algunos worktrees no se pudieron eliminar"
  fi
  echo "✅ Cleanup completado."
}

# ── Parseo ────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    list)           run_cleanup list; exit 0 ;;
    --all)          TARGET_ALL=1; shift ;;
    --yes|-y)       YES=1; shift ;;
    --force|-f)     FORCE=1; shift ;;
    --progress)     WITH_PROGRESS=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    -*)
      die "argumento no reconocido: $1 (usa --help)"
      ;;
    *)
      TARGETS+=("$(normalize_target "$1")")
      shift
      ;;
  esac
done

run_cleanup
