# Changelog — issue #14

## Qué se implementó

- **Contrato de issues** (`issues/CONTRATO.md`): spec del formato atómico para inner/outer loop.
- **Plantilla** (`issues/TEMPLATE.md`): body reutilizable con `gh issue create --body-file`.
- **Skill global** `issues-estructure` en `~/.cursor/skills/issues-estructure/SKILL.md`: triggers, sad paths, referencia al contrato y scaffold vía `install`.
- **Integración pipeline:**
  - `init.sh` valida `CONTRATO.md` y `TEMPLATE.md`.
  - `install.sh` copia contrato/template y crea plantilla de `orden-de-trabajo.md` si faltan.
  - `prompts/implement-issue.md` exige formato del contrato.
  - `CLAUDE.md` y `README.md` documentan artefactos y skill global vs bootstrap (#4).

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `issues/CONTRATO.md` | Nuevo — fuente de verdad del formato |
| `issues/TEMPLATE.md` | Nuevo — plantilla de issues |
| `init.sh` | Chequeo de CONTRATO + TEMPLATE |
| `scripts/install.sh` | Scaffold de `issues/` |
| `prompts/implement-issue.md` | Referencia al contrato |
| `CLAUDE.md` | Tabla de estructura + convención de issues |
| `README.md` | Skill global vs bootstrap, uso de template |
| `~/.cursor/skills/issues-estructure/SKILL.md` | Skill personal actualizada (fuera del repo) |

## Tests añadidos

Ninguno (suite bats es issue #8). Verificación manual:

- `./init.sh` — pasa con nuevos archivos clave.
- `bash scripts/check_order.sh 14` — issue listado en orden-de-trabajo (P0).

## Decisiones relevantes

- **Nombre de skill:** `issues-estructure` (ya existía en `~/.cursor/skills/`) en lugar de `pr-loop-issues`; el issue permite nombre acordado.
- **Skill fuera del repo:** vive en `~/.cursor/skills/` como skill personal global; el contrato versionado está en el canónico.
- **`orden-de-trabajo.md`:** ya listaba #14 como P0; sin cambios adicionales.
- **init.sh en worktree:** requiere `bash pr-loop.sh install` previo para crear `.worktrees/` local.
