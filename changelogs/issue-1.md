# Changelog — issue #1

## Qué se implementó

- **Presupuesto por corrida** (`scripts/budget.sh`): acumula `total_cost_usd` y tokens (`input_tokens` + `output_tokens`) de cada invocación `claude -p`.
- **Topes opcionales** vía `PR_LOOP_MAX_USD` y/o `PR_LOOP_MAX_TOKENS`: si se superan, el pipeline aborta con exit 2, fase `budget-exceeded` y estado persistido en `progress/current.json`.
- **Integración en fases** que usan `claude -p`: `claude_review.sh`, `self_heal.sh` (ahora con `--output-format json` para extraer uso).
- **Gate** (`gate_merge.sh`): reporta gasto acumulado en consola y comentario del PR.
- **Estado** (`state.sh`): sub-objeto `pr_loop.budget` con totales, topes, entradas por fase y flag `exceeded`.

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `scripts/budget.sh` | Nuevo — registro, guardas y abort limpio |
| `scripts/test_budget.sh` | Nuevo — tests mínimos sin bats |
| `scripts/state.sh` | Inicializa `pr_loop.budget` en `state_init` |
| `scripts/claude_review.sh` | `budget_guard` / `budget_record_from_raw` tras cada review |
| `scripts/self_heal.sh` | JSON output + registro de presupuesto |
| `scripts/gate_merge.sh` | Línea de presupuesto en resumen y PR |
| `pr-loop.sh` | Source budget, guards por fase, exit 2, banner de topes |
| `init.sh` | Ejecuta `test_budget.sh` |
| `README.md` | Documenta `PR_LOOP_MAX_USD` / `PR_LOOP_MAX_TOKENS` |
| `CLAUDE.md` | Menciona `budget` en estado y scripts |

## Tests añadidos

- `scripts/test_budget.sh` — verifica acumulación y disparo de tope por tokens.
- Integrado en `./init.sh`.

## Decisiones relevantes

- **Solo `claude -p`**: agent (Cursor) y codex no reportan uso estructurado; el issue apunta explícitamente al output JSON de Claude.
- **Tokens**: suma `input_tokens + output_tokens` del campo `.usage` (sin cache tokens).
- **Exit 2** para presupuesto agotado, distinto de fallo de review (1) o gate con bloqueantes (1).
- **Tracking sin topes**: aunque no haya `PR_LOOP_MAX_*`, el gasto se acumula para el reporte en gate.
- **self_heal**: pasa a `--output-format json`; el contenido healed se extrae de `.result`.

## Verificación

```bash
bash pr-loop.sh install   # si falta .worktrees/
./init.sh                 # incluye test_budget.sh
bash scripts/test_budget.sh
PR_LOOP_MAX_USD=0.01 bash pr-loop.sh issue-1 --from review-claude  # aborta tras primera review real
```
