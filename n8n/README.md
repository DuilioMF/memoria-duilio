# n8n — Memoria Duilio

## Estado actual

Existe un workflow n8n real y persistido para registrar el uso efectivo de memorias:

- workflow: `Memoria Duilio — Marcar memoria usada`;
- workflow id: `r8EHoms5bF1zJSdL`;
- estado al exportar: **inactive**;
- archivo: `n8n/memoria-duilio-mark-memory-used.json`;
- entrada esperada: `memory_item_ids` como array UUID, con `actor`, `usage_action` y `project_id` opcionales;
- destino: RPC `public.fn_mark_memory_used`;
- autenticación: referencia a credencial Supabase existente en n8n, sin secretos versionados.

El workflow usa `Execute Sub-workflow Trigger`. Un workflow que recupere Memoria Duilio debe llamarlo después de saber cuáles `memory_item_ids` se usaron realmente para construir la respuesta.

## Inventario vivo — 22/09/2026

Se inspeccionaron los workflows reales de n8n por API. En ese momento:

- no había workflows que llamaran directamente a `memory_resume_project`;
- no había workflows que consultaran `memory_items`, `memory_knowledge` o `memory_experiences` de Memoria Duilio;
- sí había nodos `Postgres Chat Memory`, pero pertenecen a la memoria conversacional propia de n8n y no deben contabilizarse como uso de `memory_items`.

Por esta razón no se modificó ningún workflow productivo ajeno: hacerlo habría generado métricas falsas.

## Integración correcta

Cuando un workflow empiece a consumir Memoria Duilio:

1. recuperar candidatos mediante el API semántico o las tablas de Memoria Duilio;
2. identificar los `memory_item_id` realmente usados;
3. pasar sólo esos IDs al subworkflow `Memoria Duilio — Marcar memoria usada`;
4. verificar la respuesta del RPC;
5. no marcar todos los candidatos de búsqueda como usados.

El API semántico también dispone de la acción `mark_used` para integraciones que trabajen a través de la Edge Function.

## Seguridad

Nunca versionar credenciales, tokens, contraseñas, headers privados ni service role. El export conserva únicamente referencias de credenciales de n8n.
