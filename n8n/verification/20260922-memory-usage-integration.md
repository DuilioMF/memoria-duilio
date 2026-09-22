# Verificación — Memoria Duilio ↔ n8n — 22/09/2026

## Producción

- Workflow: `Whatsapp escuchando a la Duilio`
- ID: `2QazWFxhUkURI15A`
- Estado: active
- Version activa: `882cd76a-2545-4352-8470-bf5e000a82a4`
- Backup previo: `n8n/backups/whatsapp-duilio-before-memory-20260922-1028.json`
- Commit del backup: `9e64da3a356bd8dc6d3742ef566b5f7ba0774b10`

Ruta integrada:

`Switch2 → Buscar Memoria Duilio → Preparar contexto Memoria Duilio → AI Agent Agenda → Extraer memorias usadas → Send message + Marcar memorias usadas`

Controles:
- búsqueda semántica por `memoria-duilio-semantic`;
- sólo se aceptan IDs presentes entre los candidatos recuperados;
- el agente emite el marcador técnico `USED_MEMORY_IDS`;
- el marcador se elimina antes de WhatsApp;
- el marcado corre en paralelo y no bloquea el envío.

## Subworkflow de uso real

- Workflow: `Memoria Duilio — Marcar memoria usada`
- ID: `r8EHoms5bF1zJSdL`
- Estado: active
- Version activa: `d82ac2e8-1a87-4bd7-85bd-82ee584e3755`
- Trigger: `inputSource=passthrough`
- RPC: `public.fn_mark_memory_used`

## Prueba neutra

Se ejecutó con `memory_item_ids=[]`.

- ejecución padre n8n: `9171` — success;
- ejecución hija n8n: `9172` — success;
- nodo `Mark used memory items`: success;
- eventos de prueba en `memory_retrieval_events`: 0.

La prueba verifica el circuito Execute Sub-workflow → Supabase RPC sin incrementar `use_count`.
