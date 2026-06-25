# Issue #7 — CI en GitHub Actions (init.sh en cada PR)

## Qué se implementó

- Workflow `.github/workflows/ci.yml` que corre en cada push y PR hacia `main`.
- Pasos: checkout → instalar `shellcheck` en el runner → `bash pr-loop.sh install` (crea `.worktrees/` requerido por `init.sh`) → `./init.sh`.
- El check aparece en PRs como **CI / smoke**; `gate_merge.sh` ya consulta `gh pr checks` y reporta CI rojo si algún check falla.

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `.github/workflows/ci.yml` | Nuevo workflow de smoke tests |
| `changelogs/issue-7.md` | Este changelog |

## Tests añadidos

Ninguno (la suite bats es issue #8). Verificación local:

```bash
bash pr-loop.sh install && ./init.sh
```

## Decisiones relevantes

- **`install` antes de `init.sh` en CI:** en un checkout limpio no existe `.worktrees/`; `init.sh` lo exige (check #6). `pr-loop.sh install` es idempotente y ya documentado en `changelogs/issue-14.md` para worktrees locales.
- **Linux único:** acorde al scope del issue (sin matrix multi-OS).
- **`shellcheck` en el runner:** opcional según el issue; al instalarlo, `init.sh` lo ejecuta automáticamente en el paso de smoke.
- **Sin cambios en `gate_merge.sh`:** ya detecta CI rojo vía `gh pr checks` cuando el workflow falla.

## Correcciones tras review

Review Claude (`20260623T202553`): veredicto **approve**, sin bloqueantes. No hubo review Codex.

| Punto | Acción |
|-------|--------|
| Bloqueantes | Ninguno — no requirió cambios obligatorios |
| `permissions: contents: read` | Aplicado (least-privilege recomendado por GitHub) |
| `jq` redundante en apt-get | Eliminado — ya viene preinstalado en `ubuntu-latest` |
| Cache apt / fijar acciones por SHA | Fuera de scope mínimo — diferido |
