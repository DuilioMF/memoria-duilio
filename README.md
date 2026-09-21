# Memoria Duilio

[![Abrir Memoria Duilio](https://img.shields.io/badge/▶%20ABRIR-Memoria%20Duilio-ff6b35?style=for-the-badge)](https://memoria-duilio.revalsoftia.chatgpt.site)

Centro de control conversacional y orquestador de proyectos de Duilio.

## Estado verificable

- Constitución activa: **6.1.0** (Supabase).
- Versión de software recuperable en GitHub: **0.1.0-recovery.1**.
- Estado: **RECOVERY_VERSION_AVAILABLE_NOT_CANONICAL**.
- Proyecto Supabase: `pddsehshgfynpmibjqhj`.
- Repositorio: `DuilioMF/memoria-duilio`.
- Rama congelada: `release/0.1.0-recovery.1`.
- Tablero operativo: https://trello.com/b/4sGARptV/memoria-duilio-proyectos-y-ejecuci%C3%B3n
- Documentación: https://app.notion.com/p/3d0277d8646b818f92cac1b62319cbd3
- Tarjeta de consolidación: https://trello.com/c/LMkOwvC3
- Fase 9: https://trello.com/c/isqUeQLf

La versión `0.1.0-recovery.1` **no es todavía la versión canónica**: falta publicar/probar la UI desde esta fuente y completar la prueba punta a punta.

## Fuentes de verdad

| Área | Fuente |
|---|---|
| Tareas y próxima acción | Trello |
| Código y versiones | GitHub |
| Estado, ejecución, grafo y auditoría | Supabase |
| Automatización e integraciones | n8n / Supabase scheduler según el caso |
| Documentación | Notion |
| Coordinación conversacional | Memoria Duilio |

## Recuperado en GitHub

### Edge Functions

- `supabase/functions/memoria-duilio-semantic/index.ts`
- `supabase/functions/memoria-duilio-daily/index.ts`
- `supabase/functions/memoria-work-adapter/index.ts`
- `supabase/functions/memoria-orchestrator/index.ts`
- `supabase/functions/memoria-home/index.ts`

### Base de datos

- `supabase/migrations/recovered_memoria_duilio.sql`
- 53 migraciones recuperadas desde el historial aplicado de Supabase.
- Snapshot SQL revisado para no versionar literales de credenciales.

### Interfaz

- `ui/`: reconstrucción versionada de la UI Sites v4.
- Lee `memoria-home` para Hoy / Proyectos / Ejecutándose / Espera de vos.
- Conserva Hablar, voz, saludo breve y actualización cada 60 s.
- No incluye secretos ni service role.

### n8n

- `n8n/README.md`: inventario verificable.
- Existe conector n8n API verificado, pero no se encontró un export persistente de workflow específico de Memoria Duilio; no se creó uno ficticio.

## Backend comprobado

Backend de inicio: Capa 0 + reglas + gate de integridad.
Rutina principal: 08:00 Argentina.
Watchdog: 08:05 Argentina.
Control de integridad: activo con refresco de fuentes vivas.

Última verificación de integridad durante la recuperación: **CONSISTENTE**, sin incidentes bloqueantes.

## Seguridad

Este repositorio es privado. No guardar secretos, tokens, contraseñas, datos personales ni exports con credenciales.

La UI solo admite claves públicas/publishable y tokens de sesión de corta duración. Nunca usar `service_role` en el navegador.

## Criterio de versión canónica

1. Publicar la UI desde la fuente versionada en GitHub o recuperar la fuente original exacta.
2. Verificar autenticación.
3. Verificar Hablar/voz.
4. Verificar Hoy / Proyectos / Ejecutándose / Espera de vos contra Supabase/Trello reales.
5. Completar prueba punta a punta con evidencia.
6. Recién entonces promover una versión sin sufijo `recovery`.
