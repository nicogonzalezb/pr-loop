# Issue #8 — Suite bats para scripts del pipeline

## Qué se implementó

- Suite de tests [bats](https://github.com/bats-core/bats-core) bajo `tests/` con 4 archivos de test y 12 casos.
- Fixtures locales (prompts, orden-de-trabajo, mock de `gh`) sin tokens ni CLIs de agentes.
- `init.sh` ejecuta `bats tests/` cuando `bats` está instalado (opcional, no bloquea si falta).
- README: sección de instalación y ejecución de tests.
- Guard en `pr-loop.sh` (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]`) para poder sourcear `resolve_targets` en tests sin ejecutar `main`.

## Archivos modificados / añadidos

| Archivo | Cambio |
|---------|--------|
| `tests/test_helper.bash` | Helpers compartidos (`common_setup`, `state_test_setup`, `gh_mock_setup`, `load_resolve_targets`) |
| `tests/render_prompt.bats` | Placeholders y error si falta el prompt |
| `tests/state.bats` | `state_init`, `state_set_fase`, `state_inc_fix`, dry-run |
| `tests/check_order.bats` | Issue en plan (#8), bloqueado (#3), no listado |
| `tests/resolve_targets.bats` | `headRefName`, `Closes #N`, fallback `pr-N` |
| `tests/fixtures/` | Prompt de prueba, orden-de-trabajo, mock `gh` |
| `pr-loop.sh` | Guard para no ejecutar `main` al sourcear |
| `init.sh` | Paso 7: bats opcional |
| `README.md` | Documentación de `brew install bats-core` y `bats tests/` |

## Tests añadidos

12 casos en 4 archivos `.bats` (criterio del issue: mínimo 4 archivos).

```bash
brew install bats-core   # macOS
bats tests/
```

## Decisiones relevantes

- **Mock de `gh`**: script en `tests/fixtures/bin/gh` controlado por variables `MOCK_GH_HEAD_REF`, `MOCK_GH_BODY`, `MOCK_GH_TITLE` — sin red ni token.
- **Estado aislado**: cada test de `state.sh` usa `STATE_FILE` en `$BATS_TMPDIR`.
- **Sourcing de `pr-loop.sh`**: guard estándar de bash en lugar de extraer `resolve_targets` a otro script (cambio mínimo).
- **bats opcional en `init.sh`**: coherente con `shellcheck` opcional; CI (#7) puede instalar `bats-core` en el job.
