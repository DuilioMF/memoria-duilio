# MD · Integración de Notion, ejecución de código y Control — 28/09/2026

Documento de implementación y entrega parcial. NO acreditar las tres rutas como completadas antes de las verificaciones E2E.

## 1. Notion firmado

- Preexistente: Edge Function `memoria-notion-signed-ingest` v1 ACTIVE, con verificación HMAC sobre cuerpo original; deniega peticiones si falta el token.
- Activado con éxito: n8n `systJoudk1ZUY0hz` (subworkflow, sin webhook público) y `l7nvEEDtF2a16a6G` (workflow v2 con Raw Body y exclusión del handshake). Ambos se leyeron de vuelta con `active=true` el 28/09.
- Nuevo endpoint, distinto del heredado: `https://n8n.srv1251563.hstgr.cloud/webhook/memoria-sync-notion-signed-v2`.
- La antigua ruta v1 y su respaldo permanecen intactos. Los nuevos workflows fueron publicados para recibir el handshake, NO para omitir la autenticación.
- Falta la acción privada: desde la configuración de la integración de Notion, crear la suscripción con el endpoint v2. Guardar su `verification_token` en Supabase Edge Functions > Secrets como `NOTION_WEBHOOK_VERIFICATION_TOKEN`. Nunca guardarlo en GitHub, n8n JSON, tarjetas ni chat.
- Prueba indispensable: evento natural firmado `page.content_updated`; correlacionar evento Notion, ejecución n8n e ingreso real `memory_ingest_events`. Repetir el mismo evento y verificar deduplicación; comprobar también rechazo de firma incorrecta. La activación de un workflow no acredita estas pruebas.

## 2. Fase 10 — ejecutor de propuestas

- Ya existente en `main`: `.github/workflows/md-proposal-worker.yml` y `scripts/md_proposal_worker.py`. Solo pueden proponer PR en archivos autorizados `ui/` o `docs/`. Nunca despliegan, fusionan ni cierran Trello automáticamente.
- Creado en n8n: `mOoGmiZmjOLOoJsc`, "Fase 10 — Despacho a GitHub Actions", INACTIVO hasta credenciales y piloto. Su fuente exportable está en `n8n/memoria-fase10-github-dispatch-v1.json` de esta rama.
- Recibe solo un claim `memory_queue_claim_v2` autenticado de `github-actions-md`, con `execution_run_id`, `queue_id`, `card_url`, `run_key` y tarea acotada. Despacha `repository_dispatch` al repo canónico y exige HTTP 204. **Un 204 es recepción, no ejecución satisfactoria**.
- Registrado en Supabase `memory_executor_registry` el ejecutor `github-actions-md` como `pending_connection`, `enabled=false`, `automatic=false`; ninguna tarjeta puede atribuirle ejecución ficticia.
- Faltan acciones privadas: asignar en el nodo n8n "GitHub repository_dispatch" una credencial Header Auth con GitHub PAT de mínimos permisos; configurar `OPENAI_API_KEY` en GitHub Actions repository secrets y validar permisos para crear PR.
- Falta integrar el claim específico/heartbeat en el proceso n8n y obtener prueba de punta a punta desde una tarjeta REAL con un solo `queue_id`: claim, dispatch, Actions run, commit/PR, CI, reversión y registro en Supabase/Trello. **No** habilitar el ejecutor ni mover tarjeta a cerrado antes de esos hechos y el gate CE-1.

## 3. Centro de control autenticado

- El proyecto Supabase MD tenía `auth.users=0` al comprobarse el 28/09.
- Se desplegó `memoria-home-auth-v1` v1 ACTIVE con `verify_jwt=true`. Fuente exacta: `supabase/functions/memoria-home/index.ts` de `main`, blob `dff6dbe7e806e3422c751a2c6dbbc84e8d27ba9d`.
- Este despliegue es paralelo, no reemplaza la Edge legacy `memoria-home` ni actualiza el front-end publicado. Niega el acceso sin `MD_OWNER_USER_ID` o sesión válida.
- Pendiente: crear y verificar un usuario propio en **este proyecto Supabase MD**, configurar solo en Secrets `MD_OWNER_USER_ID` con su UID real y `MD_ALLOWED_ORIGINS` con el origen exacto del frontend autorizado.
- Prueba de aceptación: 401 sin token y con otra identidad; 403 desde origen no autorizado; sesión válida del dueño; pestaña Control con totales reales de `memory_control_center_summary()`; publicación visual autenticada y rollback documentado.
- Atención: `ui/config.js` de main apunta a la Edge legacy y no contiene una clave pública real configurada; el frontend no se considera listo para publicar solo por haber desplegado la nueva Edge.

## Reglas de continuidad

No imprimir credenciales, no inventar identidades ni usar una firma HMAC falsa. Conservar fuentes previas, versiones y backups; actualizar tarjetas con pruebas, estado, ejecutor y siguiente paso. MD-0800 deberá pasar una corrida NATURAL limpia antes de su cierre; ningún cambio anterior equivale a esa prueba.
