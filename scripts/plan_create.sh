#!/usr/bin/env bash
# Crea issues en GitHub a partir de una propuesta aprobada del outer loop.
#
# Uso:
#   plan_create.sh <proposal.json> <created.json>
# Variables:
#   PR_LOOP_DRY_RUN=1 -> no crea issues, solo imprime plan
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROPOSAL="${1:?proposal.json requerido}"
CREATED="${2:?created.json requerido}"

if ! command -v gh &>/dev/null; then
  echo "❌ gh no está instalado." >&2
  exit 1
fi

bash "$SCRIPT_DIR/plan_validate.sh" "$PROPOSAL"

atomic="$(jq -r '.atomic' "$PROPOSAL")"
if [ "$atomic" = "true" ]; then
  echo "ℹ Issue épico ya es atómico — no se crean sub-issues."
  jq -n \
    --argjson epic "$(jq '.epic' "$PROPOSAL")" \
    --arg reason "$(jq -r '.atomic_reason' "$PROPOSAL")" \
    '{epic: $epic, atomic: true, created: [], reason: $reason}' > "$CREATED"
  exit 0
fi

count="$(jq '.sub_issues | length' "$PROPOSAL")"
echo "→ Creando $count sub-issue(s)..."

if [ "${PR_LOOP_DRY_RUN:-0}" = "1" ]; then
  jq -c '.sub_issues[] | {title, body: (.body | split("\n")[0] + "…")}' "$PROPOSAL" \
    | while read -r item; do
        echo "  [dry-run] gh issue create --title $(echo "$item" | jq -r .title)"
      done
  jq -n \
    --argjson epic "$(jq '.epic' "$PROPOSAL")" \
    '{epic: $epic, atomic: false, created: [], dry_run: true}' > "$CREATED"
  exit 0
fi

mkdir -p "$(dirname "$CREATED")"
tmp_created="$(mktemp)"
trap 'rm -f "$tmp_created"' EXIT
echo '[]' > "$tmp_created"

idx=0
while [ "$idx" -lt "$count" ]; do
  title="$(jq -r ".sub_issues[$idx].title" "$PROPOSAL")"
  body="$(jq -r ".sub_issues[$idx].body" "$PROPOSAL")"
  assumptions="$(jq -c ".sub_issues[$idx].assumptions // []" "$PROPOSAL")"

  body_file="$(mktemp)"
  {
    printf '%s\n' "$body"
    if [ "$assumptions" != "[]" ] && [ "$assumptions" != "null" ]; then
      echo ""
      echo "## Supuestos del planner"
      jq -r '.[] | "- \(.)"' <<< "$assumptions"
    fi
  } > "$body_file"

  echo "  → gh issue create: $title"
  num="$(gh issue create --title "$title" --body-file "$body_file" --json number -q .number 2>/dev/null || true)"
  if [ -z "$num" ] || [ "$num" = "null" ]; then
    url="$(gh issue create --title "$title" --body-file "$body_file" 2>/dev/null || true)"
    num="$(printf '%s' "$url" | grep -oE '[0-9]+$' || true)"
  fi
  rm -f "$body_file"

  if [ -z "$num" ]; then
    echo "❌ No se pudo obtener número del issue creado para: $title" >&2
    exit 1
  fi

  jq --argjson n "$num" --arg t "$title" \
    '. += [{number: $n, title: $t}]' "$tmp_created" > "${tmp_created}.new"
  mv "${tmp_created}.new" "$tmp_created"

  idx=$(( idx + 1 ))
done

jq -n \
  --argjson epic "$(jq '.epic' "$PROPOSAL")" \
  --argjson created "$(cat "$tmp_created")" \
  '{epic: $epic, atomic: false, created: $created}' > "$CREATED"

echo "✓ Issues creados:"
jq -r '.created[] | "  #\(.number) — \(.title)"' "$CREATED"
