# pr-loop

Pipeline PR multi-agente, 100% terminal. Encadena tres CLIs nativos (Cursor, Claude Code, Codex) para llevar un issue desde la implementación hasta un PR listo para que un humano decida el merge.

```
agent -p (Composer 2.5)  → implement
gh pr create / push      → PR
claude -p (Opus)         → review profunda (read-only, JSON)
agent -p (Composer 2.5)  → fix según review (máx. 2 loops)
codex exec review        → segunda review (read-only, markdown)
gate                     → comentario en PR + recomendación merge
```

El pipeline **nunca** mergea solo. El merge lo hace un humano.

---

## Outer loop / planner (`plan-loop.sh`)

Descompone issues **épicos** en issues **atómicos** antes del inner loop. Human-gated: no crea nada sin tu OK.

```
claude -p (sonnet)  → propone sub-issues (JSON)
humano              → aprueba / rechaza / re-propone
gh issue create     → emite issues con formato issues/CONTRATO.md
```

```bash
bash plan-loop.sh 5 --dry-run              # preflight sin agente
bash plan-loop.sh 5                        # propuesta interactiva + creación
bash plan-loop.sh 5 --arch-doc CLAUDE.md   # doc de arquitectura explícito
bash plan-loop.sh 5 --proposal progress/…-plan-proposal.json  # reutilizar propuesta
```

Doc de arquitectura (en orden): `--arch-doc` → `PLAN_ARCH_DOC` → `ARCHITECTURE.md` → `CLAUDE.md`. Si falta, degrada con aviso.

Sad paths: issue ya atómico → no descompone; rechazo humano → no crea; épico ambiguo → supuestos en `assumptions`.

---

## Dogfooding (automejora en este repo)

Este repositorio puede ejecutar el pipeline sobre sus propios issues abiertos. La capa mínima ya está en la raíz:

| Archivo | Rol |
|---------|-----|
| `.pr-loop.env` | `INIT_SCRIPT`, modelos, rama base (sourced por `pr-loop.sh`) |
| `init.sh` | Smoke tests: sintaxis bash, dry-run, archivos clave |
| `CLAUDE.md` | Convenciones para implementador y reviewer |
| `issues/CONTRATO.md` | Spec del formato de issues |
| `issues/TEMPLATE.md` | Plantilla para `gh issue create` |
| `issues/orden-de-trabajo.md` | Orden recomendado y bloqueos (#3, #4) |

**Orden sugerido** (ver el doc para detalle):

1. `issue-2` — defensa prompt-injection
2. `issue-1` — presupuesto de tokens/$
3. `issue-5` — outer loop / planner (desbloquea distribución)

```bash
./init.sh
bash pr-loop.sh issue-2 --dry-run   # plan sin gastar tokens
bash pr-loop.sh issue-2             # ciclo completo → PR en GitHub
```

Cada corrida: rama `issue-N` → worktree `.worktrees/issue-N` → reviews en `progress/`.

---

## Uso

```bash
bash pr-loop.sh issue-35              # loop completo desde un issue
bash pr-loop.sh --pr 57              # sobre un PR existente
bash pr-loop.sh --pr 57 --from review-claude   # reanudar una fase
bash pr-loop.sh issue-35 --dry-run   # ver el plan sin gastar tokens
bash pr-loop.sh issue-50 --force     # ignorar warning de orden
bash pr-loop.sh issue-35 --max-fix 0 # solo reviews, sin fix
```

Fases (`--from`): `worktree | implement | pr | review-claude | fix | review-codex | gate`.

---

## Estructura

```
pr-loop/
├── plan-loop.sh        # outer loop / planner
├── pr-loop.sh          # orquestador inner loop
├── scripts/
│   ├── plan_propose.sh  # propuesta vía claude -p
│   ├── plan_validate.sh # valida JSON de propuesta
│   ├── plan_create.sh   # gh issue create (post-aprobación)
│   ├── state.sh         # estado en progress/current.json
│   ├── check_order.sh   # warning de orden de issues (opcional)
│   ├── render_prompt.sh # sustituye {{ISSUE}}/{{PR}}/{{SESSION}}/{{REVIEWS}}
│   ├── cursor_implement.sh
│   ├── claude_review.sh
│   ├── codex_review.sh
│   └── gate_merge.sh
├── prompts/
│   ├── decompose-epic.md
│   ├── implement-issue.md
│   ├── fix-from-reviews.md
│   ├── review-claude.md
│   └── review-codex.md
├── tests/plan/          # tests de validación del outer loop
└── progress/            # reviews y estado (gitignore recomendado)
    .worktrees/          # git worktree por issue (gitignore obligatorio)
```

`bash pr-loop.sh install` crea `.worktrees/` y `progress/` y los añade a `.gitignore`.

---

## Setup

### 0. Instalar en tu proyecto (primero)

pr-loop **requiere git worktree** para aislar cada issue en `.worktrees/issue-N`. Al adoptar el pipeline en un repo:

```bash
# Copia o trae pr-loop al proyecto, luego:
bash pr-loop.sh install
```

`install` verifica git + worktree, crea `.worktrees/` y `progress/`, actualiza `.gitignore` y genera `.pr-loop.env` si no existe. Es idempotente.

Requisitos de git: **≥ 2.5** (`git worktree` incluido). No hay alternativa a worktrees — es el único mecanismo de aislamiento.

### 1. CLIs del pipeline

```bash
# Cursor CLI
curl https://cursor.com/install -fsS | bash
agent login

# 2. Claude Code
claude --version   # login previo: claude

# 3. Codex CLI
curl -fsSL https://codex.openai.com/install.sh | sh
codex login

# 4. GitHub CLI
gh auth status

# 5. jq
brew install jq
```

Smoke test barato:

```bash
agent  -p "di hola" --model composer-2.5
claude -p "di hola" --model haiku --output-format json | jq -r '.result'
codex exec review --base main "smoke test" -o /tmp/codex-smoke.md
```

---

## Adaptar a tu proyecto

El pipeline es agnóstico: no asume stack, lenguaje ni estructura de tests. Para adaptarlo:

### 1. Prompts de implement y fix

Edita `prompts/implement-issue.md` y `prompts/fix-from-reviews.md` para añadir:
- Reglas de convenciones de tu proyecto
- Comandos específicos de test (`uv run pytest`, `npm test`, etc.)
- Zonas de código protegidas

### 2. Health check (opcional)

Si tu proyecto tiene un script de inicialización (p.ej. `init.sh`):

```bash
export INIT_SCRIPT=./init.sh
bash pr-loop.sh issue-35
```

### 3. Git worktree (obligatorio)

Cada corrida crea un **git worktree** en `.worktrees/issue-N` con rama `issue-N`. No se soportan scripts alternativos (`WORKTREE_SCRIPT` fue eliminado).

Tras mergear un PR, limpia el worktree huérfano:

```bash
git worktree remove .worktrees/issue-N
git worktree prune
```

(Ver issue #10 para un comando `cleanup` automatizado.)

### 4. Herramientas permitidas al reviewer Claude

Por defecto el reviewer solo puede leer. Si tus tests requieren comandos específicos:

```bash
export CLAUDE_ALLOWED_TOOLS="Read,Grep,Write,Bash(gh *),Bash(npm test),Bash(cat *),Bash(ls *)"
```

### 5. Review de Claude — criterios de dominio

Edita `prompts/review-claude.md` para añadir criterios específicos de tu proyecto (p.ej. patrones de seguridad, invariantes de negocio, contratos de API).

### 6. Orden de issues (opcional)

Si tienes un `issues/orden-de-trabajo.md` con la secuencia planificada, `check_order.sh` lo detecta automáticamente. Si no existe el archivo, el chequeo se omite sin error.

`bash pr-loop.sh install` copia `issues/CONTRATO.md` y `issues/TEMPLATE.md` al proyecto si faltan, y crea una plantilla de `orden-de-trabajo.md`.

### 7. Skill global de issues vs bootstrap por proyecto

| Skill | Ubicación | Cuándo |
|-------|-----------|--------|
| **issues-estructure** | `~/.cursor/skills/issues-estructure/` | Crear/editar issues, planificar, invocar pr-loop, descomponer épicos — **todos los proyectos** |
| **Bootstrap pr-loop (#4)** | Por proyecto (futuro) | Instalar el núcleo vendoreado en un repo nuevo — bloqueada por #3 |

La skill **issues-estructure** es personal y global: enseña el contrato en `issues/CONTRATO.md`, exige `issues/orden-de-trabajo.md` en proyectos con pr-loop, y avisa en épicos sin descomponer. El contrato y la plantilla viven en el repo canónico; cada proyecto los adopta vía `install` o copia manual.

Crear un issue siguiendo el contrato:

```bash
gh issue create --title "feat: …" --body-file issues/TEMPLATE.md
```

---

## Variables de entorno

| Variable | Efecto |
|----------|--------|
| `INIT_SCRIPT` | Script de health check a correr antes de cada agente (path absoluto o relativo al repo) |
| `PR_BASE_BRANCH` | Rama base del PR y diff Codex (default: `main`) |
| `CURSOR_MODEL` | Modelo de implement/fix (default: `composer-2.5`) |
| `CLAUDE_MODEL` | Modelo de review Claude (default: `opus`) |
| `CLAUDE_ALLOWED_TOOLS` | Herramientas permitidas al reviewer Claude |
| `PROMPTS_DIR` | Ruta a los prompts (default: `./prompts`) |
| `ORDER_FILE` | Documento de orden de issues (default: `./issues/orden-de-trabajo.md`) |
| `PR_LOOP_DRY_RUN` | Si es `"1"`, equivale a `--dry-run` |
| `SESSION_ID` | ID de sesión (default: timestamp UTC) |
| `PLAN_ARCH_DOC` | Doc de arquitectura para `plan-loop.sh` (default: `ARCHITECTURE.md` → `CLAUDE.md`) |
| `PLAN_MODEL` | Modelo del planner (default: `sonnet`) |
| `PLANNER_ALLOWED_TOOLS` | Herramientas permitidas al planner (default: `Read,Write,Bash(gh *)`) |

---

## Billing — leer antes de usar (cambio del 15 jun 2026)

Desde el **15 de junio de 2026**, `claude -p` consume un **crédito mensual Agent SDK** separado del uso interactivo, facturado a tarifas API.

| Plan Claude | Crédito Agent SDK / mes |
|-------------|-------------------------|
| Pro | $20 |
| Max 5x | $100 |
| Max 20x | $200 |

- **Requiere opt-in**: activarlo una vez en los ajustes de la cuenta de Claude. Sin opt-in, `claude -p` **falla**.
- **Sin rollover**: lo que no uses en el mes se pierde.
- **El interactivo no cambia**: `claude` (sin `-p`) sigue usando los límites normales.

Para estirar el crédito:
- Usar `--max-fix 0` para omitir la fase de fix.
- Bajar el modelo: `CLAUDE_MODEL=sonnet bash pr-loop.sh ...`
- Para reviews puntuales de alta calidad, lanzarlas interactivas (sin `-p`).
