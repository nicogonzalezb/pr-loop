# Changelog — issue #10

## Qué se implementó

- **`scripts/cleanup.sh`**: comando para listar y eliminar worktrees en `.worktrees/` del repo principal (aunque se invoque desde un worktree enlazado).
- **Entrypoint `bash pr-loop.sh cleanup`**: delega en `cleanup.sh` con los mismos argumentos.
- **Flags:**
  - `list` — tabla de worktrees con estado limpio/sucio y rama.
  - `issue-N` / `N` / nombre de carpeta — elimina un worktree concreto.
  - `--all` — todos los worktrees bajo `.worktrees/`.
  - `--yes` — sin confirmación interactiva.
  - `--force` — `git worktree remove --force` si hay cambios sin commitear.
  - `--progress` — borra logs `pipeline-issue-N-*.log`, artefactos de la sesión activa en `current.json` (por issue), o todo `progress/` con `--all`.
- **Seguridad:** rechaza worktrees sucios sin `--force`; no permite eliminar el worktree desde el que se ejecuta; ejecuta `git worktree prune` al final.
- **README** y **CLAUDE.md**: flujo post-merge documentado.

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `scripts/cleanup.sh` | Nuevo — lógica de listado y limpieza |
| `pr-loop.sh` | Subcomando `cleanup` |
| `README.md` | Uso, flags y flujo tras merge humano |
| `CLAUDE.md` | Tabla de scripts actualizada |

## Tests añadidos

Ninguno (suite bats es issue #8). Verificación manual:

- `bash -n scripts/cleanup.sh`
- `bash pr-loop.sh cleanup list` desde worktree `issue-10` (resuelve repo principal)
- Rechazo al eliminar worktree actual (`issue-10`)
- Rechazo de worktree sucio sin `--force`
- Eliminación con `--force` de worktree temporal de prueba
- `./init.sh` — pasa tras `bash pr-loop.sh install`

## Decisiones relevantes

- **Repo principal vía `git rev-parse --git-common-dir`:** permite correr cleanup desde cualquier worktree sin confundir `.worktrees/` local del worktree con el del canónico.
- **No borra ramas locales ni remotas:** fuera de scope del issue; solo `worktree remove` + `prune`.
- **Progress por issue:** limpia sesión activa en `current.json` si `pr_loop.issue` coincide; logs por patrón `pipeline-issue-N-*.log`. Sesiones históricas sin metadata solo se borran con `--all --progress`.
- **init.sh en worktree:** requiere `bash pr-loop.sh install` previo para crear `.worktrees/` local (limitación preexistente, ver issue-14).
