# Changelog — issue #13

## Qué se implementó

Capa base de **dogfooding** para ejecutar pr-loop sobre los issues de este mismo repo:

| Artefacto | Rol |
|-----------|-----|
| `CLAUDE.md` | Convenciones para implementador y reviewer (stack, fases, zonas protegidas) |
| `init.sh` | Smoke tests: deps, sintaxis bash, dry-run, archivos clave del dogfooding |
| `.pr-loop.env` | Config sourced por `pr-loop.sh` (`INIT_SCRIPT`, modelos, rama base) |
| `issues/orden-de-trabajo.md` | Cola priorizada, infra #6–#12 y bloqueos |
| `scripts/install.sh` | Instalación idempotente: `.worktrees/`, `progress/`, `.gitignore`, scaffold `issues/` |
| `scripts/worktree.sh` | Aislamiento obligatorio por issue/PR vía `git worktree` |
| `pr-loop.sh` | Source de `.pr-loop.env`, inferencia de issue desde `--pr` (`Closes #N`), worktree sobre rama de PR existente |
| `README.md` | Sección dogfooding con tabla de artefactos y flujo de uso |

La implementación principal entró en `main` con el commit `513db9d`. Este PR cierra el tracking (#13): changelog, verificación de `.pr-loop.env` en `init.sh`, y `orden-de-trabajo` actualizado.

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `CLAUDE.md` | Nuevo — convenciones de agente (commit base) |
| `init.sh` | Nuevo + chequeo de `.pr-loop.env` |
| `.pr-loop.env` | Nuevo — config de dogfooding |
| `issues/orden-de-trabajo.md` | Nuevo + #13 marcado mergeado, tabla infra #6–#12 |
| `scripts/install.sh` | Nuevo — comando `pr-loop.sh install` |
| `scripts/worktree.sh` | Nuevo — único mecanismo de aislamiento |
| `pr-loop.sh` | Source `.pr-loop.env`, `--pr` + worktree PR |
| `README.md` | Sección dogfooding post-merge |
| `changelogs/issue-13.md` | Este archivo |

## Tests añadidos

Ninguno (suite bats es issue #8). Verificación manual:

- `bash pr-loop.sh install` — crea `.worktrees/` y valida git worktree.
- `./init.sh` — pasa (incluye `.pr-loop.env`).
- `bash pr-loop.sh issue-2 --dry-run` — preflight completo sin tokens.

## Decisiones relevantes

- **Worktree obligatorio:** no hay alternativa a `git worktree`; `WORKTREE_SCRIPT` eliminado.
- **`.pr-loop.env` versionado** en el canónico como overlay de dogfooding; `install` no lo pisa si existe.
- **Infra pendiente** (#6–#12): CLI headless, CI, bats, changelogs template, cleanup, history, prompts-local — fuera de scope de #13.
- **`init.sh` en worktree:** requiere `bash pr-loop.sh install` previo para `.worktrees/` local (mismo patrón que #14).

## Correcciones tras review

Review Claude (`20260623T202555-claude-review.json`): **veredicto approve**, **0 bloqueantes**.

No hubo review Codex para esta sesión (`20260623T202555-codex-review.md` ausente).

Sugerencias de bajo riesgo aplicadas:

- README: aclarado que `./init.sh` sin `install` previo falla en el chequeo de `.worktrees/`.
- Enlace a issue [#7](https://github.com/nicogonzalezb/pr-loop/issues/7) (CI) como validación automática de `init.sh` tras merge.

Verificación: `./init.sh` pasa en worktree `issue-13`.
