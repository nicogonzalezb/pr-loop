# Changelog — issue #5

## Qué se implementó

- **Outer loop / planner** (`plan-loop.sh`): entrypoint separado del inner loop que descompone issues épicos en sub-issues atómicos.
- **Flujo human-gated:** propuesta → aprobación explícita (`s`/`n`/`r`) → `gh issue create` solo tras OK.
- **Anclaje en doc de arquitectura:** resolución `PLAN_ARCH_DOC` → `ARCHITECTURE.md` → `CLAUDE.md`; degrada con aviso si falta.
- **Contrato compatible:** validación de propuestas contra secciones de `issues/CONTRATO.md` (Contexto, Entra, Criterios).
- **Sad paths:** issue atómico (`atomic: true`), rechazo humano, re-proponer, supuestos explícitos en JSON.
- **Scripts compartidos:** `plan_propose.sh`, `plan_validate.sh`, `plan_create.sh`, `plan_render.sh`.
- **Prompt:** `prompts/decompose-epic.md` (planner anclado en doc, sin exploración masiva del código).

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `plan-loop.sh` | Nuevo — orquestador outer loop |
| `scripts/plan_propose.sh` | Nuevo — propuesta vía claude -p |
| `scripts/plan_validate.sh` | Nuevo — validación JSON/contrato |
| `scripts/plan_create.sh` | Nuevo — creación de issues post-aprobación |
| `scripts/plan_render.sh` | Nuevo — render de prompt decompose |
| `prompts/decompose-epic.md` | Nuevo — prompt del planner |
| `tests/plan/test_plan.sh` | Nuevo — tests de validación y dry-run |
| `tests/plan/fixtures/*.json` | Nuevo — fixtures válido/atómico/inválido |
| `init.sh` | Dry-run plan-loop + tests/plan |
| `.pr-loop.env` | `PLAN_ARCH_DOC`, `PLAN_MODEL` |
| `CLAUDE.md` | Documentación dos loops + estructura |
| `README.md` | Uso, estructura y variables del outer loop |

## Tests añadidos

- `tests/plan/test_plan.sh`: validación JSON, plan_create dry-run, plan-loop dry-run.
- Integrado en `./init.sh`.

Verificación:

```bash
./init.sh
bash tests/plan/test_plan.sh
bash plan-loop.sh 5 --dry-run
```

## Decisiones relevantes

- **Entrypoint propio** (`plan-loop.sh`), no mezclado en `pr-loop.sh` — separación planificar ≠ ejecutar.
- **Planner vía `claude -p`** (modelo `sonnet` por defecto) con herramientas limitadas a Read/Write/gh — no relee todo el código.
- **Rutas self-contained** en scripts plan-*: `REPO_ROOT` derivado de `SCRIPT_DIR` para evitar `PROMPTS_DIR` heredado del entorno.
- **Human-gate obligatorio:** no hay flag `--yes`; dry-run omite creación y aprobación.
- **Issues emitidos** siguen `issues/CONTRATO.md` + supuestos opcionales en sección extra al crear.
