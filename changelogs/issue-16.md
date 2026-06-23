# Issue #16 — check_order: falso positivo «bloqueado por #N»

## Qué se implementó

`scripts/check_order.sh` ahora evalúa el estado de bloqueo solo en filas de tabla donde `#N` es el issue principal (columna Issue), ignorando menciones de `#N` como dependencia en la columna de notas/motivo.

Se añadió `_is_primary_issue_row` (detecta `#N` en la primera o segunda celda de datos de una fila `| ... |`) y `_primary_issue_lines` (filtra las líneas relevantes antes del chequeo de `bloquead|⛔|blocked`).

## Archivos modificados

- `scripts/check_order.sh` — lógica de detección de fila principal y filtrado de contexto.
- `issues/orden-de-trabajo.md` — entrada para #16 en la tabla de infraestructura dogfooding.

## Tests añadidos

Ninguno (no hay harness bats aún, issue #8). Verificación manual:

- `bash scripts/check_order.sh 14` → exit 0
- `bash scripts/check_order.sh 3` → exit 1 (sigue bloqueado en su fila)
- `bash pr-loop.sh issue-14 --dry-run` → fase 0b sin error de bloqueo
- `./init.sh` → verde

## Decisiones relevantes

- Sin parser completo de markdown: heurística mínima sobre las dos primeras columnas de datos, que cubre las tablas de 3 y 4 columnas usadas en `orden-de-trabajo.md`.
- El chequeo de «aparece en el documento» sigue buscando `#N` en cualquier línea; solo el estado de bloqueo usa filas principales.
- `bash pr-loop.sh install` ejecutado en el worktree para crear `.worktrees/` y satisfacer `init.sh` (requisito ambiental, no cambio de código).
