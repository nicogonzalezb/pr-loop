#!/usr/bin/env bash
# self_heal.sh — Auto-mejora del prompt fix-from-reviews.md cuando el loop de fix
# se agota con bloqueantes pendientes.
#
# Uso:
#   bash self_heal.sh <claude_json> <issue> <session_id>
#
# Variables de entorno:
#   PR_LOOP_DRY_RUN=1  → solo imprime el prompt sin llamar a claude
#   CLAUDE_MODEL        → modelo a usar (default: opus)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPTS_DIR="${PROMPTS_DIR:-$REPO_ROOT/prompts}"
PROGRESS_DIR="$REPO_ROOT/progress"

# ── Argumentos ───────────────────────────────────────────────────────
CLAUDE_JSON="${1:?self_heal.sh requiere <claude_json> como primer argumento}"
ISSUE="${2:?self_heal.sh requiere <issue> como segundo argumento}"
SESSION_ID="${3:?self_heal.sh requiere <session_id> como tercer argumento}"

MODEL="${CLAUDE_MODEL:-opus}"
FIX_PROMPT="$PROMPTS_DIR/fix-from-reviews.md"
HEALED_OUTPUT="$PROGRESS_DIR/${SESSION_ID}-fix-prompt-healed.md"

echo "=== Self-Healing: mejora automática de prompts ==="
echo "  JSON review:    $CLAUDE_JSON"
echo "  Issue:          $ISSUE"
echo "  Session:        $SESSION_ID"
echo "  Modelo:         $MODEL"
echo "  Prompt origen:  $FIX_PROMPT"
echo "  Output healed:  $HEALED_OUTPUT"
echo ""

# ── Validar archivos necesarios ──────────────────────────────────────
if [ ! -f "$CLAUDE_JSON" ]; then
  echo "⚠  self_heal: $CLAUDE_JSON no existe — no hay datos de review para analizar." >&2
  exit 0
fi

if [ ! -f "$FIX_PROMPT" ]; then
  echo "⚠  self_heal: $FIX_PROMPT no existe — no hay prompt base que mejorar." >&2
  exit 0
fi

# ── Extraer bloqueantes del JSON ─────────────────────────────────────
BLOQUEANTES_JSON="$(jq '.bloqueantes // []' "$CLAUDE_JSON" 2>/dev/null || echo '[]')"
BLOQUEANTES_COUNT="$(echo "$BLOQUEANTES_JSON" | jq 'length' 2>/dev/null || echo 0)"

if [ "$BLOQUEANTES_COUNT" -eq 0 ]; then
  echo "  ℹ  No hay bloqueantes en $CLAUDE_JSON — self-heal innecesario."
  exit 0
fi

echo "  Bloqueantes sin resolver: $BLOQUEANTES_COUNT"
echo ""

# ── Leer el prompt actual ────────────────────────────────────────────
FIX_PROMPT_CONTENT="$(cat "$FIX_PROMPT")"

# ── Construir el prompt para Claude ─────────────────────────────────
HEAL_PROMPT="$(cat <<PROMPT
# Tarea: Mejorar el prompt de fix para que sea más efectivo

Un pipeline multi-agente ejecutó un loop de corrección de código (fix loop) basado en el siguiente prompt:

---PROMPT ACTUAL (fix-from-reviews.md)---
${FIX_PROMPT_CONTENT}
---FIN PROMPT---

A pesar de ${BLOQUEANTES_COUNT} loops de fix, los siguientes bloqueantes NO fueron resueltos:

---BLOQUEANTES PENDIENTES (JSON)---
${BLOQUEANTES_JSON}
---FIN BLOQUEANTES---

## Tu tarea

Analiza por qué el agente implementador pudo haber fallado en resolver estos bloqueantes y reescribe el prompt \`fix-from-reviews.md\` para que sea más preciso y efectivo.

Considera:
1. ¿El prompt es lo suficientemente específico sobre cómo leer e interpretar los bloqueantes del JSON?
2. ¿Da instrucciones claras sobre cómo validar que un bloqueante fue realmente resuelto?
3. ¿Indica cómo manejar bloqueantes ambiguos o de alta complejidad?
4. ¿Hay pasos de verificación que faltan (tests, linting, revisión del diff)?
5. ¿El orden de los pasos es el más efectivo?

## Formato de respuesta

Devuelve ÚNICAMENTE el contenido del nuevo \`fix-from-reviews.md\` mejorado, sin explicaciones adicionales, sin bloques de código markdown, sin prefijos. Solo el contenido del archivo tal como debe quedar.

El archivo debe mantener los placeholders \`{{ISSUE}}\`, \`{{REVIEWS}}\` y \`{{SESSION}}\` que usa el sistema de templates.
PROMPT
)"

# ── Dry-run: solo mostrar el prompt ─────────────────────────────────
if [ "${PR_LOOP_DRY_RUN:-0}" = "1" ]; then
  echo "  [dry-run] Prompt que se enviaría a claude -p:"
  echo "---"
  echo "$HEAL_PROMPT"
  echo "---"
  echo "  [dry-run] Output se guardaría en: $HEALED_OUTPUT"
  exit 0
fi

# ── Llamar a Claude para generar el prompt mejorado ──────────────────
echo "  Llamando a claude -p ($MODEL) para analizar fallos y mejorar prompt..."
mkdir -p "$PROGRESS_DIR"

if ! echo "$HEAL_PROMPT" | claude -p --model "$MODEL" > "$HEALED_OUTPUT" 2>&1; then
  echo "⚠  self_heal: claude -p falló — se conserva el prompt original." >&2
  rm -f "$HEALED_OUTPUT"
  exit 0
fi

if [ ! -s "$HEALED_OUTPUT" ]; then
  echo "⚠  self_heal: claude -p devolvió respuesta vacía — se conserva el prompt original." >&2
  rm -f "$HEALED_OUTPUT"
  exit 0
fi

echo "  ✅ Prompt mejorado guardado en: $HEALED_OUTPUT"
echo ""

# ── Mostrar diff entre el prompt original y el healed ────────────────
echo "  Diferencias propuestas (original vs healed):"
echo "---"
diff "$FIX_PROMPT" "$HEALED_OUTPUT" || true
echo "---"
echo ""

# ── Preguntar al usuario si quiere aplicar el cambio ─────────────────
echo "  ¿Aplicar el prompt mejorado sobre prompts/fix-from-reviews.md?"
echo "  (Responde 's' o 'y' para aplicar. Tienes 30 segundos. Sin respuesta = NO aplicar)"
echo -n "  > "

RESPUESTA=""
if read -r -t 30 RESPUESTA 2>/dev/null; then
  : # se leyó respuesta
else
  echo ""
  echo "  ⏱  Timeout: no se aplicaron cambios. El prompt healed queda en:"
  echo "     $HEALED_OUTPUT"
  exit 0
fi

# ── Aplicar si el usuario confirmó ──────────────────────────────────
if [[ "$RESPUESTA" =~ ^[sySY]$ ]]; then
  cp "$HEALED_OUTPUT" "$FIX_PROMPT"
  echo "  ✅ Prompt aplicado: $FIX_PROMPT"

  # Commit si el directorio tiene git
  if git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null 2>&1; then
    git -C "$REPO_ROOT" add "$FIX_PROMPT"
    # Solo commitear si hay cambios staged
    if git -C "$REPO_ROOT" diff --cached --quiet; then
      echo "  ℹ  Sin cambios staged para commitear (el archivo era idéntico)."
    else
      git -C "$REPO_ROOT" commit -m "self-heal: update fix-from-reviews.md [session $SESSION_ID]"
      echo "  ✅ Commit creado en el repositorio principal."
    fi
  else
    echo "  ℹ  $REPO_ROOT no es un repositorio git — se omite el commit."
  fi

  echo ""
  echo "  Resumen de cambios aplicados:"
  echo "    - prompts/fix-from-reviews.md actualizado con mejoras propuestas por Claude"
  echo "    - Sesión: $SESSION_ID"
  echo "    - Bloqueantes que gatillaron el self-heal: $BLOQUEANTES_COUNT"
  echo "    - Copia del healed guardada en: $HEALED_OUTPUT"
else
  echo "  ℹ  No se aplicaron cambios. El prompt healed queda disponible para revisión en:"
  echo "     $HEALED_OUTPUT"
fi

echo ""
echo "=== Self-Healing completado ==="
