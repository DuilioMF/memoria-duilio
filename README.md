# Memoria Duilio

Centro de control conversacional y orquestador de proyectos de Duilio.

## Estado verificable

- Constitución activa: **6.1.0** (Supabase).
- Estado de software: **SIN_VERSION_CANONICA** hasta consolidar y probar una versión recuperable.
- Proyecto Supabase: `pddsehshgfynpmibjqhj`.
- Tablero operativo: https://trello.com/b/4sGARptV/memoria-duilio-proyectos-y-ejecuci%C3%B3n
- Documentación: https://app.notion.com/p/3d0277d8646b818f92cac1b62319cbd3
- Tarjeta de consolidación: https://trello.com/c/LMkOwvC3
- Fase 9: https://trello.com/c/isqUeQLf

## Fuentes de verdad

| Área | Fuente |
|---|---|
| Tareas y próxima acción | Trello |
| Código y versiones | GitHub |
| Estado, ejecución, grafo y auditoría | Supabase |
| Automatización e integraciones | n8n |
| Documentación | Notion |
| Coordinación conversacional | Memoria Duilio |

## Componentes comprobados

Edge Functions activas relevantes:

- `memoria-duilio-semantic`
- `memoria-duilio-daily`
- `memoria-work-adapter`
- `memoria-orchestrator`
- `memoria-home`

Backend de inicio: Capa 0 + reglas + gate de integridad.
Rutina principal: 08:00 Argentina.
Watchdog: 08:05 Argentina.
Control de integridad: horario y con refresco de fuentes vivas.

## Estructura objetivo

- `supabase/migrations/`: migraciones verificadas.
- `supabase/functions/`: Edge Functions recuperadas.
- `n8n/`: exports de workflows sin credenciales.
- `docs/`: arquitectura, inventario, restauración y pruebas.
- `ui/`: fuente de la interfaz vigente cuando sea recuperada.

## Seguridad

Este repositorio es privado. No guardar secretos, tokens, contraseñas, datos personales ni exports con credenciales.

## Criterio de cierre

Memoria Duilio tendrá versión canónica únicamente cuando las fuentes vigentes estén recuperadas, el sistema sea reproducible y la prueba punta a punta quede registrada.
