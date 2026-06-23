# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# pr-loop — convenciones para agentes

Este repositorio es el **núcleo canónico** del pipeline PR multi-agente. Los agentes que implementan o revisan aquí están mejorando la herramienta que se ejecuta sobre sí misma (dogfooding).

## Stack

- Bash (`set -euo pipefail` en todos los scripts)
- `jq` para JSON de estado y reviews
- CLIs externas: `agent` (Cursor), `claude`, `codex`, `gh`

## Arquitectura (big picture)

Sistema de **dos loops**:

| Loop | Entrypoint | Rol |
|------|------------|-----|
| **Outer** | `plan-loop.sh` | Épico → propuesta de sub-issues → (OK humano) → `gh issue create` |
| **Inner** | `pr-loop.sh` | Issue atómico → implement → PR → reviews → gate |

`plan-loop.sh` es el **outer loop / planner**. Ancla en un doc de arquitectura (`PLAN_ARCH_DOC`, `ARCHITECTURE.md` o `CLAUDE.md`), propone issues atómicos según `issues/CONTRATO.md`, y **nunca crea issues sin aprobación explícita** del humano.

`pr-loop.sh` es el **inner loop** — orquestador secuencial de fases. Entender el flujo requiere leer el orquestador junto con `scripts/state.sh` y los wrappers de fase.

**Cadena de fases** (array `PHASES` en `pr-loop.sh`):

```
worktree → implement → pr → review-claude → fix → review-codex → gate
```

- Cada fase es una función `phase_*` en `pr-loop.sh` que **delega** en un wrapper de `scripts/`. El orquestador decide el qué; los wrappers ejecutan el cómo (renderizan prompt + invocan una CLI).
- `--from FASE` reanuda desde una fase concreta: `should_run` recorre `PHASES` y solo ejecuta de `FROM` en adelante.
- `--dry-run` (o `PR_LOOP_DRY_RUN=1`) corta todo efecto secundario (no agentes, no `gh`, no escritura de estado). Toda fase respeta este flag.

**Estado** (`scripts/state.sh`): se persiste el sub-objeto `pr_loop` dentro de `progress/current.json` (fase actual, `pr`, `intentos_fix`, paths de `reviews.{claude,codex}`). Todas las escrituras pasan por helpers `state_*` que hacen no-op en dry-run. Los artefactos de cada corrida se nombran `progress/${SESSION_ID}-*` (`SESSION_ID` = timestamp UTC por defecto).

**Resolución de target** (`resolve_targets`): con `--pr N`, se deriva la rama/issue vía `gh` y, si falta, se parsea `Closes #N` del body del PR. El worktree vive en `.worktrees/<rama>`.

**Aislamiento (obligatorio)**: cada issue usa **`git worktree`** en `.worktrees/issue-N`. No hay alternativa (`WORKTREE_SCRIPT` eliminado). Instalación: `bash pr-loop.sh install` → `scripts/install.sh` + `scripts/worktree.sh`.

**Loop de fix + self-heal** (la lógica más densa, `phase_fix`):

1. Corre `cursor_implement.sh` con `fix-from-reviews.md`, hace push, y **re-review** con Claude (nuevo JSON por intento).
2. Cuenta `.bloqueantes` en el JSON de la review de Claude. `0` bloqueantes → éxito; se repite hasta `MAX_FIX` (default 2, `0` omite la fase).
3. Si se agotan los intentos con bloqueantes, `FIX_EXITOSO=1` dispara `self_heal.sh`, que mejora el prompt `fix-from-reviews.md` para futuras corridas.

**Contrato de reviews**: la review de Claude es **JSON** con un array `.bloqueantes` (el loop de fix depende de este campo); la de Codex es **markdown**. `gate_merge.sh` consolida ambas, comenta en el PR y emite recomendación de merge — pero **nunca mergea**.

## Zonas protegidas

- **No mergear automáticamente** — el pipeline nunca llama a `gh pr merge`.
- **No editar `progress/` ni `.worktrees/`** en reviews (contexto limpio); el orquestador escribe ahí.
- **Cambios mínimos** — un issue = un cambio acotado. Sin refactors cosméticos.
- **Compatibilidad** — los flags y variables de entorno documentados en README deben seguir funcionando.

## Estructura

| Ruta | Rol |
|------|-----|
| `plan-loop.sh` | Outer loop / planner (descomponer épicos) |
| `pr-loop.sh` | Orquestador inner loop; punto de entrada y máquina de fases |
| `scripts/plan_{propose,validate,create,render}.sh` | Wrappers del outer loop |
| `scripts/state.sh` | Estado en `progress/current.json` (sub-objeto `pr_loop`) |
| `scripts/render_prompt.sh` | Sustituye placeholders `{{ISSUE}}`/`{{PR}}`/`{{SESSION}}`/`{{REVIEWS}}` |
| `scripts/check_order.sh` | Warning de orden de issues (opcional, sourced) |
| `scripts/{cursor_implement,claude_review,codex_review,gate_merge,self_heal,worktree,install}.sh` | Wrappers de fase + git worktree + install |
| `prompts/decompose-epic.md` | Prompt del planner (outer loop) |
| `prompts/` | Prompts versionados con placeholders |
| `init.sh` | Health check del proyecto (sourced vía `INIT_SCRIPT`) |
| `.pr-loop.env` | Config del proyecto sourced por `pr-loop.sh` (modelos, rama base, `INIT_SCRIPT`) |
| `issues/CONTRATO.md` | Spec del formato de issues (fuente de verdad) |
| `issues/TEMPLATE.md` | Plantilla para `gh issue create` |
| `issues/orden-de-trabajo.md` | Orden y bloqueos de issues para automejora |
| `progress/`, `.worktrees/` | Estado/artefactos y worktrees por issue (no versionar) |

## Convenciones de código

- Scripts bash con shebang `#!/usr/bin/env bash` y `set -euo pipefail`.
- Mensajes de usuario en español; comentarios en español o inglés según el archivo existente.
- Conventional commits: `feat:`, `fix:`, `docs:`, `chore:`.
- Nuevos scripts ejecutables: `chmod +x` y ubicación en `scripts/` salvo entrypoints en raíz.
- Los wrappers de `scripts/` no llevan lógica de negocio pesada: renderizan prompt + invocan una CLI.

## Verificación antes de terminar

```bash
bash pr-loop.sh install              # primera vez en un proyecto
./init.sh                            # smoke tests: deps, bash -n, shellcheck, dry-run, archivos clave
bash pr-loop.sh issue-1 --dry-run   # debe pasar preflight
```

`init.sh` ya corre `bash -n` y `shellcheck -x` (si está instalado) sobre los scripts; si tocas un script, basta con que `./init.sh` pase.

## Issues y ramas

- Formato: `issues/CONTRATO.md` + `issues/TEMPLATE.md`. Skill global `issues-estructure` en `~/.cursor/skills/`.
- Rama de trabajo: `issue-N` (ej. `issue-2`).
- El PR debe incluir `Closes #N` en el body.
- Respeta `issues/orden-de-trabajo.md`: issues marcados ⛔ bloqueados no se implementan hasta desbloquearse.

## Dependencias entre issues abiertos

1. **#2** (prompt-injection) y **#1** (presupuesto) — independientes, listos para el inner loop.
2. **#5** (outer loop / planner) — antes de distribución.
3. **#3** (distribución lock+fetch) — ⛔ bloqueado por #5.
4. **#4** (skill bootstrap) — ⛔ bloqueado por #3.
