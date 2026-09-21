# Estado operativo — Memoria Duilio

Fecha de actualización: 20/09/2026 (Argentina)

## Estado verificado

- Constitución activa: **6.1.0**.
- Software recuperable: **0.1.0-recovery.1**.
- Estado de versión: **RECOVERY_VERSION_AVAILABLE_NOT_CANONICAL**.
- Repositorio: `DuilioMF/memoria-duilio`.
- Rama de snapshot: `release/0.1.0-recovery.1`.
- Supabase: `pddsehshgfynpmibjqhj`, ACTIVE_HEALTHY.
- Integridad: **CONSISTENTE**, 0 incidentes bloqueantes.
- Fase 7: 10% — en progreso.
- Fase 8: 0% — planificada.
- Fase 9: último registro 75% — parcial; la recuperación GitHub avanzó desde ese registro.

## Recuperación realizada

1. Repositorio privado localizado y habilitado como autoridad de software.
2. Cinco Edge Functions centrales recuperadas desde Supabase.
3. 53 migraciones de Memoria Duilio recuperadas desde `supabase_migrations.schema_migrations`.
4. UI Sites v4 reconstruida y versionada en `ui/` usando el comportamiento verificable registrado.
5. Archivo `VERSION` creado con `0.1.0-recovery.1`.
6. Rama `release/0.1.0-recovery.1` creada para congelar el snapshot.
7. Conector GitHub de Memoria Duilio corregido de `pending/repository_exists=false` a `connected/repository_exists=true`.
8. El gate de integridad devolvió `CONSISTENTE`.
9. La corrida `AUTO-20260920-2130` que había quedado en `running` sin heartbeat fue reconciliada y cerrada como `completed`; su propio resumen ya indicaba auditoría completada/documentada.
10. n8n inventariado sin inventar exports inexistentes.

## UI recuperada

La fuente original exacta de ChatGPT Sites no apareció en GitHub ni en la biblioteca disponible. Sí existían registros verificables de Sites v4:

- URL histórica: `https://memoria-duilio.revalsoftia.chatgpt.site`.
- entrada directa en **Hablar**;
- pestaña **Proyectos**;
- saludo breve: “Hola Duilio, acá estoy. ¿En qué seguimos?”;
- voz/lectura de respuesta;
- proyectos con ejecución, ejecutor, última acción y señal;
- Work cerrados plegados;
- actualización automática;
- backend privado conectado a Supabase.

La reconstrucción en `ui/` conserva ese contrato y consume `memoria-home`, pero todavía debe publicarse y validarse visualmente antes de considerarse canónica.

## Backend recuperado

- `supabase/functions/memoria-home/index.ts`
- `supabase/functions/memoria-orchestrator/index.ts`
- `supabase/functions/memoria-work-adapter/index.ts`
- `supabase/functions/memoria-duilio-daily/index.ts`
- `supabase/functions/memoria-duilio-semantic/index.ts`

## Base recuperada

- `supabase/migrations/recovered_memoria_duilio.sql`
- 53 migraciones.
- ~352 KB de SQL.
- Sin coincidencias detectadas de literales de credenciales en el escaneo previo al commit.

## n8n

Hay evidencia de conexión real de `Memoria Duilio n8n API` y de una ejecución 7577 que leyó `memory_projects`. No se encontró un workflow persistente específico de Memoria Duilio para exportar. Los Edge Functions temporales de inventario quedaron deshabilitados intencionalmente. No se fabrica un workflow para aparentar recuperación.

## Pendiente para versión canónica

1. Publicar la UI desde `ui/` en la misma página de Memoria Duilio.
2. Inyectar configuración de autenticación sin secretos.
3. Validar visualmente Hablar / Hoy / Proyectos / Ejecutándose / Espera de vos.
4. Validar acceso autenticado y rechazo no autorizado.
5. Ejecutar prueba punta a punta final y registrar evidencia.
6. Promover una versión canónica sin sufijo `recovery`.
