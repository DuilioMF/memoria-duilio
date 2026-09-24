# Memoria Duilio 0.6.4 — Identidad consistente de proyectos en Trello

## Qué se corrigió
- Se unificaron títulos que omiten el nombre de proyecto: Memoria Duilio, CONTROL, Conexión TV, Reloj Feli y Capacitación IA.
- Se completaron etiquetas existentes: Reloj Feli (rojo), CONTROL (violeta), Capitán y Ruben (azul de proyecto padre DoingLio).
- Las 9 tarjetas de Supervisión conservan su etiqueta rosa (`Supervision` sin tilde es el nombre visible de etiqueta).
- La idea compartida `Supervisión / Reloj Feli — Suscriptores` tiene las dos etiquetas; **no se ejecuta como si fuera una tarea de un único proyecto**.
- Se registró un catálogo de reglas en `memory_projects.metadata.trello`: prefijo, etiqueta, color e herencia.
- La sincronización usa el identificador estable corto de Trello, no el slug cambiante del título.
- `memory_resolve_trello_project` ahora prioriza prefijos configurados sobre la etiqueta heredada.
- Si un proyecto está sin registrar o no se puede resolver, `memory_enqueue_trello_card` lo BLOQUEA con `trello_project_unresolved`; ya no lo envía por defecto a Memoria Duilio.
- `memory_trello_presentation_audit_v` y `memory_trello_presentation_issues()` identifican automáticamente problemas en cada sincronización.

## Pruebas
- 56/56 tarjetas actuales permanecieron sincronizadas al cambiar a shortlink.
- 56 identidades activas únicas, sin duplicados causados por renombrar.
- Capitán Rodolfo se resuelve como `capitan-rodolfo` y Ruben como `ruben`, aunque heredan el azul de DoingLio.
- Proyecto Conexión se resuelve como `conexion` aun sin etiqueta exclusiva.
- Un intento controlado de encolar Viaje India fue rechazado como `trello_project_unresolved`, sin generar un trabajo erróneo.
- La auditoría detectó 3 proyectos sin alta independiente en la memoria: Viaje India, WhatsApp pagos FIFO y Capacitación IA. Suscriptores es intencionalmente multiproyecto y figura por separado.

## Pendientes
- Las etiquetas exclusivas de Capitán, Ruben, Conexión, WhatsApp pagos FIFO y Capacitación no existen aún en este tablero. La integración Trello conectada permite asignar etiquetas existentes, pero no crear etiquetas nuevas: por eso Capitán/Ruben heredan temporalmente el azul DoingLio.
- No crear proyectos, repositorios ni otras entidades a partir de estas tarjetas sin reconciliar previamente el catálogo universal y las reglas de aprovisionamiento.
- La auditoría está conectada al proceso de sincronización de Supabase; no reemplaza una automatización que pueda CREAR nuevas etiquetas en Trello.

## Rollback
Restaurar el commit previo `c5b28374ec44b1b7ab266bd6d83526e4dd304d18` para el código SQL. La migración no borra Trello ni datos históricos; los títulos/etiquetas reales quedan en el historial de Trello.
