# Estado operativo — Memoria Duilio

Fecha de corte: 20/09/2026 21:58 (Argentina)

## Estado verificado

- Constitución activa: 6.1.0.
- Software: SIN_VERSION_CANONICA hasta recuperar y probar una versión reproducible.
- Supabase: proyecto `pddsehshgfynpmibjqhj`, estado ACTIVE_HEALTHY.
- Fase 7: 10% — en progreso.
- Fase 8: 0% — planificada.
- Fase 9: 75% — parcial.

## Fase 9 — próximo cierre

Pendientes verificados:

1. Conectar la UI vigente de Memoria Duilio a `memory_home_payload_v1` / Edge Function `memoria-home` y validar visualmente Hoy / Proyectos / Ejecutándose / Espera de vos.
2. Recuperar y versionar en GitHub la fuente real de la interfaz.
3. Exportar y versionar workflows n8n sin credenciales.
4. Resolver o documentar como limitación aceptada la ausencia de hook nativo de ChatGPT Work.
5. Completar prueba punta a punta final.

## Funciones recuperadas a GitHub

- `supabase/functions/memoria-home/index.ts`
- `supabase/functions/memoria-orchestrator/index.ts`
- `supabase/functions/memoria-work-adapter/index.ts`
- `supabase/functions/memoria-duilio-daily/index.ts`
- `supabase/functions/memoria-duilio-semantic/index.ts`

Estas copias provienen de las funciones activas en Supabase. No contienen secretos embebidos; usan variables de entorno.

## Datos existentes en Supabase

- 127 memorias activas/registradas en `memory_items`.
- 11 proyectos en `memory_projects`.
- 42 conectores de proyecto.
- 31 experiencias.
- 5 piezas de conocimiento.
- 15 snapshots de continuidad.
- 14 consolidaciones diarias.
- 13 reglas de aprendizaje.
- 9 ejecuciones registradas.
- 24 eventos de ejecución.
- 6 sesiones Work.
- 4 ejecutores registrados.
- 1 elemento en cola de ejecución.
- 5 incidentes de integridad registrados.
- 2 corridas programadas registradas.
- 32 eventos de despacho de programación.

## Ejecutores

- ChatGPT: ready, manual.
- ChatGPT Work: ready, manual.
- Claude Code: pending_connection.
- n8n: ready, automático.

## Programación

Existe una corrida con `schedule_key = memoria-duilio-0800` y `run_key = AUTO-20260920-2130` marcada como `running`, iniciada a las 21:30 Argentina, con resumen de auditoría no destructiva de PostgreSQL/extensiones. Debe verificarse si terminó correctamente antes de cerrar el estado.

## Integridad

Los incidentes recientes visibles están resueltos, incluyendo:
- drift de versión en Supervisión;
- captura automática sin conector;
- conectores automáticos no conectados.

## Próxima acción segura

Continuar la consolidación del repositorio: recuperar interfaz vigente y workflows n8n sin credenciales, luego ejecutar una prueba punta a punta y recién ahí definir una versión canónica.
