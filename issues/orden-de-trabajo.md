# Orden de trabajo — automejora de pr-loop

Documento vivo para el inner loop (`pr-loop.sh`). El chequeo en `scripts/check_order.sh` avisa si un issue no está listado o está bloqueado.

## P0 — prioridad principal

| Issue | Título | Notas |
|-------|--------|-------|
| **#14** | Skill interna global + estructura estándar de issues | Aplica en **todos** los proyectos (`~/.cursor/skills/`). Contrato en `issues/CONTRATO.md` + template. Prerequisito cultural antes de escalar pr-loop. |

Sin #14, cada repo improvisa issues y el inner loop pierde atomicidad y reproducibilidad.

## Infraestructura dogfooding (antes o en paralelo a features)

Piezas que faltaban para usar este repo como target del inner loop. Ver issue #13 para la capa base ya escrita localmente.

| Orden | Issue | Título | Notas |
|-------|-------|--------|-------|
| 0 | #16 | `check_order`: falso positivo «bloqueado por #N» | Surgió de #14; evita `--force` cuando el issue solo se menciona en otra fila |
| 0 | #13 | Formalizar capa base (CLAUDE.md, init.sh, …) | Merge del PR pendiente |
| — | #6 | `.cursor/cli.json` headless | Prerequisito para corridas reales sin prompts |
| — | #7 | CI GitHub Actions (`init.sh`) | Verde en PRs de dogfooding |
| — | #8 | Suite bats | Tests de scripts |
| — | #9 | Template `changelogs/` | Convención para implement/fix |
| — | #10 | `pr-loop cleanup` | Worktrees y progress |
| — | #11 | `progress/history.md` | Audit trail por corrida |
| — | #12 | Overlay `prompts-local/` | Slice previo a #3 |

## Listos para implementar (inner loop — features)

Orden recomendado para dogfooding — de menor riesgo / dependencia a mayor:

| Orden | Issue | Título | Notas |
|-------|-------|--------|-------|
| 1 | #2 | Defensa contra prompt-injection | Independiente; mejora seguridad de todas las corridas futuras |
| 2 | #1 | Presupuesto de tokens/$ por corrida | Independiente; protege crédito Agent SDK |
| 3 | #5 | Outer loop / planner | Desbloquea #3 y #4 |

```bash
bash pr-loop.sh issue-2    # primero recomendado
bash pr-loop.sh issue-1
bash pr-loop.sh issue-5
```

## Bloqueados

| Issue | Título | Motivo |
|-------|--------|--------|
| #3 | Distribución: núcleo vendoreado + lock + fetch | ⛔ bloqueado por #5 y #14 (contrato de issues) |
| #4 | Skill de bootstrap pr-loop | ⛔ bloqueado por #3 |

No correr `pr-loop.sh issue-3` ni `issue-4` hasta completar #5 y #3 respectivamente (usa `--force` solo si el humano desbloquea explícitamente).

## Cómo correr el ciclo

```bash
./init.sh                          # smoke local
bash pr-loop.sh issue-2 --dry-run  # plan sin tokens
bash pr-loop.sh issue-2            # ciclo completo
bash pr-loop.sh --pr N --from review-claude   # re-review de PR existente
```

Cada corrida crea rama `issue-N`, worktree en `.worktrees/issue-N`, y artefactos en `progress/`.
