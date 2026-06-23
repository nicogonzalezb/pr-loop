# prompts-local — overlay de dogfooding

Archivos aquí **reemplazan** el homólogo en `prompts/` cuando `render_prompt.sh` los resuelve.

- Prioridad: `prompts-local/<archivo>.md` → `prompts/<archivo>.md`
- Configurable vía `PROMPTS_LOCAL_DIR` en `.pr-loop.env`
- Proyectos sin este directorio siguen usando solo `prompts/` (sin cambios)

En el repo canónico, `review-claude.md` incluye criterios extra para bash y el meta-repo.

**Dogfooding sobre sí mismo:** al correr `pr-loop.sh` desde este repo (rama con `prompts-local/` versionado), la fase `review-claude` usa automáticamente ese override — el revisor Claude aplica los criterios extra sin editar `prompts/`. No requiere configuración adicional si `PROMPTS_LOCAL_DIR` apunta al default (`$REPO_ROOT/prompts-local`).
