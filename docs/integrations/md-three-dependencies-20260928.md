# MD · Integración de Notion, ejecución de código y Control — 28/09/2026

Documento de implementación y entrega parcial. NO acreditar las tres rutas como completadas antes de las verificaciones E2E.

## 1. Notion firmado

- Preexistente: Edge Function `memoria-notion-signed-ingest` v3 ACTIVE (verificado en Supabase 28/09); todavía sin evento natural con firma registrada, con verificación HMAC sobre cuerpo original; deniega peticiones si falta el token.
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
- Verificado: `OPENAI_API_KEY` de GitHub Actions funcionó en el piloto [run 36485443278](https://github.com/DuilioMF/memoria-duilio/actions/runs/36485443278), que generó commit `861da01`; posteriormente se abrió [PR #12](https://github.com/DuilioMF/memoria-duilio/pull/12) mediante una conexión separada. **La creación automática del PR falló** por permisos de GitHub Actions. Acciones privadas restantes: credencial GitHub PAT de mínimo alcance para el nodo n8n y habilitar/validar el permiso de Actions para crear PR; no volver a solicitar una clave OpenAI que ya demostró funcionar en ese piloto.
- Falta integrar el claim específico/heartbeat en el proceso n8n y obtener prueba de punta a punta desde una tarjeta REAL con un solo `queue_id`: claim, dispatch, Actions run, commit/PR, CI, reversión y registro en Supabase/Trello. **No** habilitar el ejecutor ni mover tarjeta a cerrado antes de esos hechos y el gate CE-1.

## 3. Centro de control autenticado — comprobación viva 28/09 (22:01 ART)

- **Origen canónico confirmado por Duilio:** `https://memoria-duilio.revalsoftia.chatgpt.site` (sin barra final). Este es el valor esperado de `MD_ALLOWED_ORIGINS` para el sitio principal.
- **Supabase MD:** existe **un** usuario en `auth.users`, y su correo está confirmado; no divulgar su UID. La Edge `memoria-home-auth-v1` **v5 ACTIVE** con `verify_jwt=true` fue verificada por conector. No modifica la Edge heredada `memoria-home`.
- **Prueba HTTP real desde GitHub Actions:** [run 36505871395](https://github.com/DuilioMF/memoria-duilio/actions/runs/36505871395), con clave pública `anon` (NO un token de sesión ni una clave de servicio): origen ajeno `403 ORIGIN_NOT_ALLOWED` **PASS** y preflight desde el origen autorizado `204` con cabecera CORS correcta **PASS**. Por tanto, **no hay que modificar nuevamente `MD_ALLOWED_ORIGINS`** para este origen.
- **Bloqueo específico comprobado:** POST desde origen autorizado con token `anon` recibió **503 OWNER_NOT_CONFIGURED** en vez de 401. La Edge devuelve 503 tanto cuando falta `MD_OWNER_USER_ID` como cuando su valor no tiene formato UUID válido. La sola declaración de haber guardado el secreto no demuestra que llegó con el valor correcto; no crear otro usuario.
- **Acción privada exacta:** ir a Supabase MD → Authentication → Users y copiar el **User UID** del usuario ya confirmado; en Edge Function Secrets **editar o crear** exactamente `MD_OWNER_USER_ID` con ese UID (UUID de 36 caracteres, sin comillas ni espacios) y guardar. No colocar UID, contraseña ni credenciales en GitHub, Trello o chats.
- **Sitio publicado:** la consulta automatizada a la URL proporcionada devolvió **403 desde el runner de GitHub**; puede deberse al acceso del sitio o a un filtro de clientes automatizados y **no prueba que la página falle para Duilio**. No se pudo inspeccionar `/config.js` del sitio. La rama de [PR #9](https://github.com/DuilioMF/memoria-duilio/pull/9) prepara `ui/config.js` con `memoria-home-auth-v1` y clave pública `anon`, pero la fuente publicada no está acreditada.
- **Datos reales de Control:** `public.memory_control_center_summary()` respondió correctamente mediante lectura conectada de Supabase. Esa lectura **no** acredita respuesta autenticada de la Edge ni la visualización publicada.
- **Regresión versionada:** `tests/test_md_f13_live.py` y `.github/workflows/md-three-integrations-check.yml` prueban el backend en vivo y el acceso externo al sitio, sin acceder a secretos. Fallos actuales se conservan expresamente para no presentar CI verde como F13 cerrada.
- **Faltan para completar F13:** después de corregir `MD_OWNER_USER_ID`, repetir la prueba hasta ver **401 UNAUTHORIZED** para clave pública desde origen autorizado, manteniendo **403** para origen no autorizado y **204** en preflight. Comprobar con la **sesión real de Duilio** el login, POST `control_center`, datos coherentes y la pestaña Control visible en `https://memoria-duilio.revalsoftia.chatgpt.site`. No guardar ni solicitar tokens de usuario en una tarjeta ni en chat. Mantener tarjeta bloqueada hasta entonces y no cerrar por pruebas negativas aisladas.

## Reglas de continuidad

No imprimir credenciales, no inventar identidades ni usar una firma HMAC falsa. Conservar fuentes previas, versiones y backups; actualizar tarjetas con pruebas, estado, ejecutor y siguiente paso. MD-0800 deberá pasar una corrida NATURAL limpia antes de su cierre; ningún cambio anterior equivale a esa prueba.
