# Issue #12 — overlay `prompts-local/` en `render_prompt.sh`

## Qué se implementó

- Resolución de prompts con prioridad: `prompts-local/<archivo>.md` → `prompts/<archivo>.md`.
- Variable `PROMPTS_LOCAL_DIR` (default `$REPO_ROOT/prompts-local`), exportada por `pr-loop.sh` y configurable en `.pr-loop.env`.
- Proyectos sin `prompts-local/` siguen funcionando igual (fallback transparente).
- Overrides de dogfooding: `prompts-local/review-claude.md` con criterios extra para bash/meta-repo.
- Verificación automática en `init.sh`: local pisa base y fallback sin directorio local.

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `scripts/render_prompt.sh` | `resolve_prompt_path()` + `PROMPTS_LOCAL_DIR` |
| `pr-loop.sh` | Export de `PROMPTS_LOCAL_DIR` |
| `init.sh` | Tests de overlay y fallback |
| `scripts/install.sh` | Ejemplo comentado en plantilla `.pr-loop.env` |
| `.pr-loop.env` | Ejemplo comentado de `PROMPTS_LOCAL_DIR` |
| `README.md` | Estructura, adaptación y tabla de variables |
| `prompts-local/review-claude.md` | Override con criterios extra meta-repo |
| `prompts-local/README.md` | Documentación del overlay |

## Tests añadidos

- `init.sh` sección 7: overlay temporal (local pisa base) y fallback sin `prompts-local/`.
- Verificación manual: `bash scripts/render_prompt.sh review-claude.md | grep "Criterios extra"`.

## Decisiones relevantes

- Solo `render_prompt.sh` implementa overlay; `codex_review.sh` y `self_heal.sh` leen `PROMPTS_DIR` directamente (fuera de scope; issue #3 puede extender).
- El overlay es **reemplazo por archivo**, no merge — alineado con el principio de #3.
- `prompts-local/` se versiona en el repo canónico para dogfooding; en proyectos consumidores puede vivir solo en local.

## Correcciones tras review

**Review Claude** (`progress/20260623T202558-claude-review.json`): veredicto `approve`, **0 bloqueantes**.

**Review Codex** (`progress/20260623T202558-codex-review.md`): no generada en esta sesión.

### Verificaciones ejecutadas

- `./init.sh` pasa en verde (secciones 1–7, incl. overlay y fallback).
- `bash pr-loop.sh issue-12 --dry-run` completa sin errores.
- Override manual: `env -u REPO_ROOT bash scripts/render_prompt.sh review-claude.md | grep "Criterios extra"` confirma que el overlay local se usa cuando `REPO_ROOT` apunta al worktree (pr-loop exporta `REPO_ROOT` correctamente en corridas normales).

### Bloqueantes

Ninguno — no se requirieron cambios de código.

### Sugerencias de la review

| Sugerencia | Acción |
|------------|--------|
| Confirmar `./init.sh` en verde antes del merge | Verificado localmente |
| Documentar activación de `prompts-local/` en dogfooding del canónico | Nota añadida en `prompts-local/README.md` |
| Unificar overlay en `codex_review.sh` / `self_heal.sh` | Fuera de scope (#3); sin cambio |
