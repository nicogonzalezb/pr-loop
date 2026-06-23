# prompts-local — overlay de dogfooding

Archivos aquí **reemplazan** el homólogo en `prompts/` cuando `render_prompt.sh` los resuelve.

- Prioridad: `prompts-local/<archivo>.md` → `prompts/<archivo>.md`
- Configurable vía `PROMPTS_LOCAL_DIR` en `.pr-loop.env`
- Proyectos sin este directorio siguen usando solo `prompts/` (sin cambios)

En el repo canónico, `review-claude.md` incluye criterios extra para bash y el meta-repo.
