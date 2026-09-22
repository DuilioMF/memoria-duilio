# n8n — Memoria Duilio

## Estado actual

La integración de uso real de memoria está conectada a un workflow productivo.

### Workflow productivo

- `Whatsapp escuchando a la Duilio`
- ID: `2QazWFxhUkURI15A`
- estado: **active**
- export: `n8n/whatsapp-duilio-memory-integrated.json`
- rollback: `n8n/backups/whatsapp-duilio-before-memory-20260922-1028.json`

Ruta:

`Switch2 → Buscar Memoria Duilio → Preparar contexto Memoria Duilio → AI Agent Agenda → Extraer memorias usadas → Send message + Marcar memorias usadas`

La búsqueda recupera candidatos desde `memoria-duilio-semantic`. El agente recibe cada fragmento con su `MEMORY_ID`, pero sólo los IDs que realmente influyeron en la respuesta se envían al circuito de feedback. Antes de WhatsApp, el marcador técnico se elimina.

### Subworkflow de marcado

- `Memoria Duilio — Marcar memoria usada`
- ID: `r8EHoms5bF1zJSdL`
- estado: **active**
- export: `n8n/memoria-duilio-mark-memory-used.json`
- trigger: passthrough
- destino: RPC `public.fn_mark_memory_used`

La función deduplica IDs, restringe por owner/proyecto y registra únicamente items efectivamente actualizados.

## Verificación

Prueba neutra con `memory_item_ids=[]`:

- ejecución padre `9171`: success;
- ejecución hija `9172`: success;
- nodo `Mark used memory items`: success;
- eventos de prueba creados: 0.

Evidencia detallada: `n8n/verification/20260922-memory-usage-integration.md`.

## Seguridad

Nunca versionar secretos, tokens, contraseñas, headers privados ni service role. Los exports conservan referencias de credenciales de n8n, no sus valores.
