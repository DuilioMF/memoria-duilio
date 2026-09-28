# MD-0800 — Notion firmado → Supabase (propuesta segura)

Esta revisión **NO cambia ni desactiva** el workflow activo de n8n `QcCWJakeSFWE1b2q`
ni el respaldo `Rby6KmhzAyWeX3zm`. Soluciona el hueco de validación
que hoy impide procesar eventos naturales: el normalizador vigente devuelve
`[]` para todos los eventos posteriores al handshake.

## Arquitectura y límites

`Notion subscription → n8n Webhook (Raw Body) → HTTP POST
memoria-notion-signed-ingest → signature HMAC → memory_ingest_events`.

- La verificación usa **exactamente** el cuerpo sin reserializar, con
  `X-Notion-Signature: sha256=<hex>` y HMAC-SHA256; usa WebCrypto.
- El secreto `NOTION_WEBHOOK_VERIFICATION_TOKEN` se instala **solamente**
  en los secretos de Supabase; nunca enviarlo al chat, Trello, GitHub o al
  JSON del workflow.
- `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` son secretos de servidor.
  El endpoint público usa `verify_jwt=false` exclusivamente porque valida
  HMAC antes de cualquier operación con service_role y, sin secreto, deniega.
- Se ingresa **metadata** del evento; Notion no manda el contenido completo
  de páginas. Un consumidor autorizado recuperará la página en otra etapa;
  no inventar títulos ni atribuir todo evento a Memoria Duilio.
- El índice único actual de `memory_ingest_events` deduplica por
  `(owner_key,source_type,external_id,event_type)`; se usa
  `resolution=ignore-duplicates` para reintentos auténticos.

## Activación controlada

1. Revisar y ejecutar el CI del PR. Desplegar la Edge Function **nueva**
   `memoria-notion-signed-ingest`, sin modificar las funciones actuales.
   Confirmar que antes de instalar el secreto responde `503 NOT_CONFIGURED`.
2. Extraer el `verification_token` **de la suscripción Notion vigente en
   un canal privado de administración**. Si no está recuperable, revalidar
   o recrear la suscripción preservando el webhook original y su respaldo;
   no usar el access token OAuth de Notion en su lugar. Configurar el secreto
   en Supabase Dashboard > Edge Functions > Secrets. Nunca imprimirlo en logs.
3. Exportar respaldo fresco de `QcCWJakeSFWE1b2q`. En n8n, mantener el
   Webhook con `options.rawBody=true` y el tratamiento de
   `verification_token` como handshake sin persistencia. Reemplazar solo
   la salida de eventos por un nodo Code que compruebe que
   `$json.body` es el **texto bruto** recibido; si llega un objeto ya
   parseado, **rechazar** (no reconstruirlo con JSON.stringify).
   Exigir `$json.headers['x-notion-signature']` como string. Entregar
   exclusivamente `{raw_body: cuerpoBruto, signature: firma}` al siguiente
   HTTP Request, sin el secreto.
4. HTTP Request POST JSON a:
   `https://pddsehshgfynpmibjqhj.supabase.co/functions/v1/memoria-notion-signed-ingest`.
   Para el handshake, no llamar a esta función: tratarlo localmente
   en el Webhook actual. Si la firma falta, el Edge responde `401`.
   Si no está configurado, responde `503` y **no escribe** memoria.
5. Probar tres eventos de una página Notion real (válido, alterado y
   reentrega del mismo evento). Registrar la ID del evento de Notion, la ID
   de ejecución n8n y `memory_ingest_events.id` de Supabase. Una escritura
   directa en Supabase NO equivale a esta prueba. No cerrar MD-0800 hasta
   otra corrida natural de las 08:00 sin errores.
6. Si falla, retirar solo el nodo HTTP / restaurar el export n8n previo.
   La función nueva se puede deshabilitar/retirar sin alterar el resto de MD.

**Pendientes externos reales:** obtener/configurar el secreto y comprobar
qué forma del cuerpo crudo produce el Webhook actual. Por diseño NO hay un
bypass para arrancar sin esos dos hechos.

Documentación oficial: https://developers.notion.com/reference/webhooks
