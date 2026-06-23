# Changelog — issue #9

## Qué se implementó

- **Plantilla** (`changelogs/TEMPLATE.md`): secciones estándar para implement y fix.
- **Convención documentada** en `CLAUDE.md` (sección "Changelogs por issue") y tabla de estructura.
- **Referencias en prompts:** `implement-issue.md` y `fix-from-reviews.md` enlazan la plantilla y `CLAUDE.md`.
- **`init.sh`:** valida que exista `changelogs/TEMPLATE.md`.
- **`README.md`:** tabla de dogfooding actualizada.

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `changelogs/TEMPLATE.md` | Nuevo — plantilla versionada |
| `CLAUDE.md` | Sección changelogs + entrada en tabla de estructura |
| `README.md` | Entrada en tabla de dogfooding |
| `prompts/implement-issue.md` | Referencia a `changelogs/TEMPLATE.md` |
| `prompts/fix-from-reviews.md` | Referencia a sección de correcciones en template |
| `init.sh` | Chequeo de `changelogs/TEMPLATE.md` |

## Tests añadidos

Ninguno (suite bats es issue #8). Verificación manual:

- `./init.sh` — pasa chequeo de `changelogs/TEMPLATE.md` (requiere `bash pr-loop.sh install` en worktrees sin `.worktrees/` local).
- `bash pr-loop.sh issue-9 --dry-run` — preflight OK.

## Decisiones relevantes

- **Sin scaffold en `install.sh`:** el issue limita el alcance a template + documentación; no se copia automáticamente a proyectos adoptores (paralelo futuro con `issues/` si hace falta).
- **Sin `.gitkeep`:** el directorio queda versionado vía `TEMPLATE.md` y changelogs por issue (p. ej. `issue-14.md`).
- **Formato alineado con `issue-14.md`:** primera corrida real que definió el formato de facto; ahora queda como plantilla explícita.

## Correcciones tras review

**Review Claude** (`progress/20260623T202557-claude-review.json`): veredicto `approve`, `bloqueantes: []`. Sin review Codex en esta sesión.

### Bloqueantes atendidos

Ninguno — la review no reportó puntos bloqueantes ni críticos.

### Sugerencias (no implementadas)

| Sugerencia | Motivo |
|------------|--------|
| Confirmar `./init.sh` y dry-run localmente | Verificado en fase fix: ambos pasan. |
| Tests automatizados nuevos | Fuera de scope; suite bats es issue #8. |
| Ejemplo mínimo rellenado en `TEMPLATE.md` | Opcional; `issue-9.md` e `issue-14.md` sirven de referencia. |

### Verificaciones

- `./init.sh` — OK
- `bash pr-loop.sh issue-9 --dry-run` — OK
