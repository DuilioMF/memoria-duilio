# Grafo automático de Memoria Duilio — v0.6.0

Fecha: 23/09/2026

## Arquitectura canónica

Memoria Duilio mantiene un solo grafo:

- `memory_entities`: nodos.
- `memory_relations`: relaciones.
- `memory_item_entities`: trazabilidad entre recuerdos y entidades.
- `memory_graph_context()`: lectura contextual.
- `memory_sync_project_graph()`: catálogo de proyectos/sistemas.

No se crean tablas paralelas `memory_nodes/memory_edges`.

## GRAFOS 4 — extracción automática

La migración `graph_auto_extraction_v1` agrega:

- `memory_graph_dictionary`: vocabulario extensible de tecnologías/motores.
- `memory_extract_graph_from_item(uuid)`: detecta proyecto, tecnologías y statement semántico.
- `memory_link_entities_evidenced(...)`: conserva confianza y evidencia/origen.
- trigger `trg_memory_items_auto_extract_graph`: ejecuta extracción en INSERT/UPDATE relevantes de `memory_items`.
- errores del extractor no rompen la ingesta; quedan en `memory_events`.

Prueba controlada:
- texto de decisión de prueba sobre Memoria Duilio + n8n.
- resultado: 1 proyecto, 1 tecnología, 1 decisión y 2 relaciones.
- confianza: 0.98/0.99.
- error events: 0.
- datos de prueba limpiados después de verificar.

## GRAFOS 5 — fuentes externas

Conectores activos verificados:
- GitHub
- n8n
- Notion
- Supabase
- Trello

Prueba real Trello → Supabase → grafo:
- se modificó la tarjeta GRAFOS 5 con marcador `GRAFOS5-E2E-20260923`.
- snapshot real: 56 tarjetas.
- `memory_sync_trello_cards`: 52 actualizadas, 4 insertadas, 3 históricas archivadas.
- la tarjeta GRAFOS 5 generó automáticamente:
  - proyecto Memoria Duilio;
  - tecnologías Trello, n8n, Notion, Supabase, PostgreSQL y GitHub;
  - entidad de tarea;
  - relaciones con origen y confianza.

## Reglas de calidad

1. No duplicar grafo.
2. Toda relación automática debe tener fuente y confianza.
3. Confianza < 0.80 => `review_required=true`.
4. No declarar una fase cerrada sin prueba real.
5. La sincronización externa debe ser idempotente.

## Rollback

El commit de v0.6.0 permite recuperar el estado exacto. Para desactivar sólo la extracción automática:
1. quitar el trigger `trg_memory_items_auto_extract_graph`;
2. conservar entidades/relaciones existentes;
3. si es necesario, restaurar el commit anterior v0.5.0: `3567ee97a4de54e94d1810b8bb250a19a0719ed9`.

## Próxima validación

GRAFOS 7 debe comprobar el circuito completo: entrada → extracción → persistencia → consulta → dependencias → deduplicación → trazabilidad.
