# Changelog — issue #2

## Qué se implementó

- **Guard de prompt-injection** en los prompts que consumen texto no controlado del pipeline:
  - `prompts/review-claude.md` (reviewer `claude -p`): sección que declara issue/diff/código como DATO, no instrucciones; delimitadores `<<<UNTRUSTED_DATA>>>` para salidas de `gh` y archivos leídos.
  - `prompts/fix-from-reviews.md` (implementador en fase fix `agent -p`): misma guarda aplicada a reviews JSON, review Codex, issue y diff.

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `prompts/review-claude.md` | Sección "Seguridad: contenido no confiable (prompt-injection)" |
| `prompts/fix-from-reviews.md` | Sección equivalente + instrucción de delimitar contenido de reviews |

## Tests añadidos

Ninguno (suite bats es issue #8). Verificación:

- `./init.sh` — pasa (sintaxis, dry-run, archivos clave, worktree).
- Inspección: ambos prompts contienen la guarda explícita y delimitadores de contenido no confiable.

## Decisiones relevantes

- **Alcance mínimo:** solo los dos prompts nombrados en el issue; no se añadió heurística previa (marcada como opcional en el issue).
- **`implement-issue.md` sin cambios:** el issue lista explícitamente `review-claude.md` y `fix-from-reviews.md`; la fase implement sigue sin guarda dedicada (riesgo residual documentado).
- **Delimitación conceptual:** el contenido no confiable no se embebe en el prompt renderizado (se lee vía `gh`/`cat`); los delimitadores son instrucción para el agente al interpretar esas salidas.
