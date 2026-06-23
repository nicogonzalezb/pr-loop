# Prompt: corregir según reviews

Eres el agente implementador. El PR del issue #{{ISSUE}} recibió reviews automáticas. Tu trabajo es resolver SOLO los puntos bloqueantes y de alta prioridad, sin introducir cambios fuera de scope.

## Contexto de las reviews

La review de Claude (JSON estructurado) está en:

    {{REVIEWS}}

Léela con: `cat {{REVIEWS}}` y extrae el array `bloqueantes` y, si hay tiempo, `sugerencias` de bajo riesgo.

También puede existir una review de Codex en `progress/{{SESSION}}-codex-review.md`. Léela con `cat` y atiende cualquier punto marcado como blocker / crítico / must fix.

## Pasos

1. Si existe un script de health check en el proyecto, córrelo para confirmar línea base verde.
2. Lee `gh issue view {{ISSUE}}` para no perder el objetivo original.
3. Resuelve cada bloqueante. Si un bloqueante es inválido o fuera de scope, déjalo documentado en el changelog en vez de implementarlo.
4. Mantén las convenciones del proyecto tal como se describe en `CLAUDE.md` u otra documentación.

## Al terminar

1. Corre los tests y verificaciones del área tocada.
2. Actualiza `changelogs/issue-{{ISSUE}}.md` con la sección "Correcciones tras review" (formato en `changelogs/TEMPLATE.md`; ver `CLAUDE.md` → Changelogs por issue).
3. Commits con conventional commits. Un commit por corrección lógica.

NO mergees. NO abras PR nuevo — el cambio va sobre la rama actual.
