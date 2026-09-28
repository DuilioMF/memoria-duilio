# MD — Cerebro híbrido v1 (implementación aditiva)

## Alcance implementado
- No se sustituyen `memory_brain_router`, `memory_graph_context`, `memory_search_semantic` ni `memory_select_executor_v2`.
- `memory_brain_hybrid_v1` combina contexto textual vigente, grafo temporal por proyecto,
  memorias semánticas (`gte-small`), conocimiento ACTIVO con pruebas reales y
  experiencias cuya verificación más reciente conocida es `success`.
- `memory_graph_context_at_v1` navega relaciones válidas a una fecha determinada,
  conservando `memory_item_id` como evidencia de la relación.
- `memory_transition_relation_v1` permite cerrar una relación y abrir su sucesora
  atómicamente, SOLO con un recuerdo previamente verificado y mismo dueño.
- `memory_executor_specialty_evidence` conserva especialidades demostradas mediante
  `memory_verifications` reales. `memory_specialist_candidates_v1` descarta ejecutores
  no automáticos, sin prueba, desconectados o sin heartbeat reciente. **Nunca despacha**:
  el selector autoritativo sigue siendo `memory_select_executor_v2`.
- La Edge Function semántica añade `hybrid_context` **solo para service_role**, y `backfill_items` para service_role o la capacidad protegida `sync` del backend.
  El backfill se invoca explícitamente, acotado a 1–12 recuerdos por llamada, no durante
  una búsqueda. Reutiliza el modelo `gte-small` y no crea experiencias ni verificaciones.

## Datos de partida verificados (auditoría del 27/09/2026)
121 entidades, 359 relaciones vigentes, 895 recuerdos (0 vectores iniciales),
767 experiencias vectorizadas inicialmente, 21 conocimientos con vector y 16 verificaciones.
Es una referencia histórica: volver a medir antes de dar cantidades actuales.

## Entrada privada
`POST memoria-duilio-semantic`, con credencial backend de servicio, ejemplo de cuerpo
sin credenciales:
```json
{"action":"hybrid_context","query":"error medios de pago","project_key":"memoria-duilio","specialty":"sql-server","limit":8}
```
Opcional `as_of` ISO 8601. Sin proyecto válido: no retorna conocimiento de otros proyectos.
NUNCA poner service_role en navegador ni en la tarjeta de Trello. Un proxy autenticado
y autorizado puede exponerse a la UI en otro cambio, con respuesta minimizada.

Backfill controlado: `{"action":"backfill_items","limit":5}` en el mismo endpoint; mantener `x-memory-sync-token` exclusivamente en el backend.
comprobar métricas antes/después y no procesar toda la base en un único disparo.
Las memorias sin vector siguen recuperándose mediante la ruta textual existente.

## Pruebas
- `tests/hybrid_brain_smoke.sql`: transacción con ROLLBACK; verifica
  aislamiento de proyectos, lectura histórica, fallback textual, búsqueda vectorial
  con embedding REAL ya registrado, negativa de transición inválida y permisos.
- `tests/test_md_hybrid_brain.py`: contratos aditivos y de seguridad (CI).
- Nunca crear una verificación artificial para mejorar contadores.
- El cambio de backend y la Edge Function tienen que probarse por separado;
  pruebas SQL satisfactorias no acreditan que el endpoint esté publicado.

## Seguridad y límites
- API SQL `v1` y tabla de especialidades: RLS y permisos solo service_role.
- Conocimiento candidato se devuelve por legado/texto SOLO como contexto;
  las soluciones propuestas aquí salen exclusivamente de evidencia exitosa.
- La foto histórica refleja **relaciones y fechas**, pero no conserva nombres
  anteriores de entidades ni el estado histórico completo de `memory_knowledge`.
  Esas capacidades requerirían auditoría temporal de entidades/knowledge.
- No se conecta automáticamente a las tarjetas de las 08:00 hasta que MD-0800
  registre una corrida natural limpia y Fase 10 posea un ejecutor real y CE-1 activo.

## Criterios para completar el despliegue
1. SQL v1 aplicado y smoke SQL PASS.
2. Verificar diff entre la Edge Function publicada y la fuente del repositorio;
   si difieren, reconciliar cambios antes del deploy.
3. Desplegar Edge `verify_jwt=true`; invocar `hybrid_context` con credencial de backend;
   verificar acceso denegado sin credencial y casos de proyecto desconocido.
4. Ejecutar un lote pequeño de `backfill_items`; verificar vectores y aislamiento.
5. Instrumentar el router de n8n/MD mediante feature flag y registrar correlación
   de resultados antes de habilitarlo en el circuito de las 08:00.
6. Registrar especialidades desde pruebas reales, sin declarar conectados los
   ejecutores cuyo heartbeat/capacidad no fue comprobado.
7. No mover tarjetas a Cerrado sin `memory_card_closure_gate(...).allowed=true`
   y aprobación humana auténtica, según CE-1.

## Reversión
- No llamar los endpoints nuevos y conservar `memory_brain_router`: el camino
  anterior no fue modificado. Desplegar la versión previa de la Edge si se habilita
  el nuevo endpoint y produce problemas. No borrar datos o pruebas históricas.
- Archivo de migración base: `20260928015000_hybrid_brain_v1.sql`.
  El forward fix `20260928021000_hybrid_brain_operator_fix_v1.sql`
  repara la resolución del operador `OPERATOR(public.<=>)` cuando la función usa
  `search_path=''`.

## Registro de despliegue inicial
- SQL instalado: `hybrid_brain_v1`, `hybrid_brain_operator_fix_v1` y `hybrid_brain_project_scope_fix_v1`.
- La corrección de proyecto impide que el nuevo endpoint entregue resultados de búsqueda textual de otros proyectos.
- Edge `memoria-duilio-semantic` v22 se publicó inicialmente; la nueva variante con `sync` para lotes requiere publicación y reprueba.
- Los endpoints nuevos no sustituyen el router autoritativo ni activan el proceso de las 08:00.