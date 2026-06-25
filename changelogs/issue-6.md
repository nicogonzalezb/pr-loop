# Issue #6 — `.cursor/cli.json` para agent headless

## Qué se implementó

- Archivo `.cursor/cli.json` en la raíz con permisos mínimos para las fases **implement** y **fix** del inner loop:
  - Shell: `bash`, `git`, `gh`, `cat`, `chmod`, `find`, `mkdir`, `shellcheck`
  - Lectura y escritura del proyecto (`Read(**)`, `Write(**)`)
  - Denegaciones explícitas: `rm`, `sudo`, `dd`, `curl`, `wget`, y archivos sensibles (`.env*`, `*.key`, `*.pem`)
- Documentación en README (sección dogfooding): propósito del archivo y prerequisito para corridas no interactivas.

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `.cursor/cli.json` | Nuevo — allowlist/denylist de permisos CLI |
| `README.md` | Tabla dogfooding + párrafo headless |

## Tests añadidos

Ninguno. Verificación manual:

- `jq empty .cursor/cli.json` — JSON válido
- `./init.sh` — smoke tests del repo

## Decisiones relevantes

- Solo se configuran `permissions` en el archivo de proyecto (lo demás queda en `~/.cursor/cli-config.json` global).
- `Write(**)` cubre el worktree completo; los `deny` protegen secretos sin bloquear el flujo normal de implementación.
- Permisos por proyecto en repos consumidores quedan fuera de scope (issue #4).
- Se corrió `bash pr-loop.sh install` para crear `.worktrees/` y que `init.sh` pase en este worktree (prerequisito de entorno, no parte del diff funcional).

## Correcciones tras review

**Review Claude** (`20260623T202556-claude-review.json`): veredicto `approve`, **0 bloqueantes**. Review Codex: no generada en esta sesión.

| Punto | Acción |
|-------|--------|
| Bloqueantes | Ninguno — PR cumple los 3 criterios de aceptación del issue #6. |
| `Write(**)` amplio (sugerencia) | Fuera de scope: los `deny` de secretos mitigan el riesgo; acotar el glob queda para un issue futuro si hace falta. |
| `deny` de `curl`/`wget` (sugerencia) | Sin cambio: descargas vetadas a propósito; el README ya documenta el propósito headless. |
| `./init.sh` no corrido en entorno del revisor | Ejecutado localmente en el worktree: pasa (deps, sintaxis, dry-run, archivos clave). |
