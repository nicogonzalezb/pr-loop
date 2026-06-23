# Contrato de issues — pr-loop

Fuente de verdad del formato de issues para el inner loop (`pr-loop.sh`) y el outer loop (#5). La skill global `issues-estructure` (`~/.cursor/skills/issues-estructure/`) enseña y aplica este contrato en cualquier proyecto.

**Principio:** el issue **es** la especificación. Ningún trabajo grande entra al inner loop sin pasar por esta estructura.

---

## Título

Verbo + objeto concreto (atómico). Un issue = una unidad implementable en un solo `bash pr-loop.sh issue-N`.

Ejemplos: `feat: presupuesto de tokens por corrida`, `fix: validar JSON de review Claude`.

---

## Secciones obligatorias del body

### Contexto

Por qué importa (2–4 oraciones). Problema actual y consecuencia si no se resuelve.

### Qué falta / alcance

Delimitar explícitamente:

- **Entra:** lista concreta de cambios incluidos.
- **No entra:** exclusiones para evitar scope creep.

### Criterios de aceptación

Checkboxes **verificables** (no vagos). Cada ítem debe poder comprobarse con tests, `init.sh`, o inspección objetiva.

```markdown
- [ ] Criterio verificable 1
- [ ] Criterio verificable 2
```

### Bloqueos (opcional)

Si el issue no debe implementarse aún:

```markdown
⛔ bloqueado por #N
```

Debe reflejarse también en `issues/orden-de-trabajo.md`.

### Relaciones (opcional)

```markdown
- Depende de #N
- Bloquea #M
```

---

## Artefactos a nivel repo

| Artefacto | Rol |
|-----------|-----|
| `issues/CONTRATO.md` | Este documento — spec del formato |
| `issues/TEMPLATE.md` | Plantilla para `gh issue create --body-file` |
| `issues/orden-de-trabajo.md` | Cola priorizada + bloqueos (consumido por `scripts/check_order.sh`) |

---

## Convenciones de ejecución

| Convención | Regla |
|------------|-------|
| Rama | `issue-N` (ej. `issue-14`) |
| PR | Body con `Closes #N` |
| Worktree | `.worktrees/issue-N` (obligatorio tras `bash pr-loop.sh install`) |
| Labels | `priority`, `blocked` (o equivalente documentado en README) |

---

## Atomicidad

Un issue es **atómico** si:

1. Tiene criterios de aceptación verificables.
2. Define **Entra** / **No entra** sin ambigüedad.
3. Cabe en un ciclo inner loop sin descomposición adicional.

Si abarca varias unidades de trabajo → **épico**. No marcar listo para inner loop; descomponer en issues hijos u outer loop (#5).

---

## Sad paths

| Situación | Acción esperada |
|-----------|-----------------|
| Issue épico sin descomponer | Avisar; proponer outer loop (#5), no `pr-loop.sh` directo |
| Proyecto sin `issues/` | Scaffold mínimo: `orden-de-trabajo.md` + copia de `CONTRATO.md` y `TEMPLATE.md` |
| Sin criterios de aceptación | Completarlos antes de inner loop |
| Issue ⛔ en `orden-de-trabajo.md` | No implementar salvo `--force` con OK humano |

---

## Integración con el pipeline

- **`check_order.sh`:** lee `issues/orden-de-trabajo.md` y avisa si el issue no está listado o parece bloqueado.
- **`implement-issue.md`:** el agente lee el issue vía `gh issue view N`; el formato de este contrato maximiza señal para implementación y review.
- **Cross-repo:** mismo contrato en Node, Python, bash, etc.; solo cambia el overlay de tests/stack (`.pr-loop.env`), no el formato del issue.
