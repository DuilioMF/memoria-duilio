# n8n — Memoria Duilio

## Estado recuperado

No se encontró un export persistente de un workflow n8n específico de Memoria Duilio en las fuentes recuperables.

Sí está verificado:

- conector `Memoria Duilio n8n API`: **connected**;
- modo: automático;
- alcance registrado: `phase9_execution_status`;
- evidencia registrada: ejecución n8n **7577** pudo leer `memory_projects`;
- los antiguos Edge Functions de inventario/configuración de Fase 9 están deshabilitados intencionalmente (HTTP 410);
- la sincronización semántica histórica se programó con Supabase `pg_cron` / `pg_net`, no debe fingirse como workflow n8n;
- la rutina operativa 08:00 tiene ledger propio en Supabase.

## Regla de recuperación

No crear un workflow ficticio para “llenar” esta carpeta. Cuando exista un export real desde n8n, guardarlo aquí sin credenciales y registrar:

1. workflow id;
2. nombre;
3. estado active/inactive;
4. nodos y conexiones;
5. versión/fecha;
6. evidencia de ejecución;
7. secretos reemplazados por referencias de credenciales.

## Seguridad

Nunca versionar credenciales, tokens, contraseñas, headers privados ni service role.
