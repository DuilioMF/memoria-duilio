# MD — Cerebro híbrido v1

## Diseño aditivo, sin reemplazar producción
- Conserva memory_brain_router, memory_graph_context, memory_search_semantic y memory_select_executor_v2.
- memory_brain_hybrid_v1 reúne texto filtrado por proyecto, grafo temporal, fragmentos vectoriales y conocimiento/experiencias con verificaciones reales.
- memory_graph_context_at_v1 consulta relaciones con sus fechas de validez. No reconstruye nombres históricos de entidades.
- memory_transition_relation_v1 exige un recuerdo ya verificado antes de reemplazar una relación. No permite reescribir el pasado silenciosamente.
- memory_executor_specialty_evidence conserva pruebas reales por especialidad. memory_specialist_candidates_v1 exige verificación success, status ready, capacidad automática y heartbeat vigente. Solo informa; no ejecuta ni suplanta el router autoritativo.

## Dimensiones: no mezclar modelos
- memory_items.embedding es vector(768), actualmente vacío, destinado a otra representación. NO introducir allí embeddings gte-small.
- memory_chunks.embedding ya contiene 793 fragmentos de 384 dimensiones con gte-small y es la fuente semántica utilizada en hybrid-v1.
- memory_experiences y memory_knowledge ya usan gte-small 384. El índice HNSW preexistente se conserva.
- En el diagnóstico inicial había 895 recuerdos generales, 121 entidades, 359 relaciones, 767 experiencias vectorizadas y 16 verificaciones. Volver a medir antes de informar cifras actuales.

## Edge privada
- memoria-duilio-semantic añade hybrid_context (solo service_role backend), hybrid_selftest (capacidad sync, sin datos privados), y backfill_chunks (capacidad sync, lotes 1 a 12, llama a embedChunks existente). backfill_items es solo alias de compatibilidad.
- Mantiene verify_jwt=false del endpoint anterior porque ya usa autorización de capacidades propia. No exponer el service_role ni tokens de sync en el navegador.
- Ejemplo de cuerpo sin credenciales: {"action":"hybrid_context","query":"medios de pago","project_key":"memoria-duilio","specialty":"sql-server","limit":8}.
- Sin proyecto conocido, no entrega contenido de otros proyectos. Las candidaturas nunca autorizan un despacho autónomo.

## Implementación y validación
- GitHub: rama feature/hybrid-brain-v1-20260927, PR #8 en borrador.
- SQL aplicado: hybrid_brain_v1, hybrid_brain_operator_fix_v1, hybrid_brain_project_scope_fix_v1, hybrid_brain_chunks_v1 y hybrid_brain_readonly_fix_v1.
- Prueba SQL transaccional con ROLLBACK: PASS. Prueba SQL en transacción READ ONLY: PASS con 3 fragmentos semánticos recuperados.
- Control automático en GitHub: tests/test_md_hybrid_brain.py, workflow md-hybrid-brain-check.yml. Revisar el último run del PR antes de fusionar.
- Edge versión 26 publicada ACTIVE conservando los métodos anteriores.
- HTTP sin autorización para hybrid_context: 403. HTTP protegido para backfill_chunks: 200 con chunks_embedded=0, coherente con el índice de fragmentos ya vectorizado.
- El selftest HTTP descubrió un UPDATE indirecto desde el router heredado en un RPC STABLE, corregido mediante lectura exacta de proyecto. La prueba SQL READ ONLY pasó; aún falta certificar nuevamente esa misma ruta HTTP.

## Lo que no se debe confundir con completitud
- No está conectado al flujo diario de las 08:00 ni a un ejecutor de código real. MD-0800 y Fase 10 mantienen sus propios criterios de cierre.
- No existen todavía tres especialistas con verificaciones y heartbeats aptos; registrar solo resultados de ejecuciones reales.
- Antes de cerrar automáticamente una tarjeta se mantiene obligatorio CE-1: memory_card_closure_gate(card_url).allowed=true y aprobación humana auténtica.

## Reversión
- No invocar los endpoints nuevos y seguir utilizando el router anterior. Se conservaron las firmas y los datos históricos.
- Si falla la nueva Edge, restaurar la versión previa conocida desde el historial de despliegues y el commit anterior del archivo index.ts, conservando su política de autorización.
- No eliminar la nueva tabla de evidencia ni borrar relaciones históricas si alguna vez registran pruebas reales.
