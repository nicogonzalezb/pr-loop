# Issue #11 — Audit trail `progress/history.md`

## Qué se implementó

- Helper `state_append_history` en `scripts/state.sh` que escribe entradas markdown append-only en `progress/history.md`.
- Al finalizar `pr-loop.sh` (éxito o fallo parcial), se registra metadata de la corrida vía `append_run_history`.
- Cada entrada incluye: `SESSION_ID`, issue, PR, fase de reanudación (`--from`), fases completadas, intentos de fix, estado del fix loop, bloqueantes finales (Claude) y veredicto del gate.
- Re-runs con `--from` dejan constancia de la fase de reanudación en la tabla.
- `--dry-run` no escribe historial (consistente con otros helpers `state_*`).
- Campo opcional `HISTORY_GASTO` reservado para cuando exista el presupuesto (#1); no se exporta aún.

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `scripts/state.sh` | `state_append_history` + cabecera del log |
| `pr-loop.sh` | `record_phase`, `append_run_history`, invocación al final de `main` |
| `README.md` | Sección y estructura de `progress/history.md` |
| `init.sh` | Smoke test de definición y escritura de entrada |

## Tests añadidos

- `init.sh`: verifica que `state_append_history` existe y escribe una entrada con campos esperados (incl. `Reanudado desde`).
- Verificación manual: `bash pr-loop.sh issue-N --dry-run` no crea `progress/history.md`.

## Decisiones relevantes

- **`history.md` gitignored** indirectamente vía `progress/` en `.gitignore` (sin cambio adicional).
- **Formato**: sección `## SESSION — issue-N` + tabla markdown por corrida (legible en terminal y en editores).
- **Fases**: solo las del array `PHASES` que efectivamente corrieron; `phase_order` no se cuenta como fase de pipeline.
- **Gate no ejecutado**: si `--from` omite la fase gate, el veredicto queda como `(gate no ejecutado)`.
