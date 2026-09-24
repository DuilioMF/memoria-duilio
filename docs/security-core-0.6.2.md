# Memoria Duilio 0.6.2 — Security + Core

## Cierre del núcleo seguro

Verificación con Supabase advisors después de aplicar los cambios:

- RLS sin policy en las 13 tablas operativas: **0**.
- views `SECURITY DEFINER` críticas: **0**.
- funciones con `search_path` mutable de este bloque: **0**.
- RPC internas `SECURITY DEFINER` ejecutables por anon/authenticated: **0**.
- FK sin índice del núcleo: **0**.

## Cambios

- Policies explícitas backend-only para las tablas operativas.
- `memory_connector_topology_v` y `memory_duplicate_candidates_v` pasan a `security_invoker`.
- `search_path` fijado en cinco funciones.
- RPC privilegiadas limitadas a `service_role`.
- Cinco índices de FK agregados.

## Pendientes de infraestructura

No forman parte del núcleo funcional y se mantienen en la tarjeta de mantenimiento:
- upgrade de PostgreSQL 15.8.1.100 por parches de seguridad;
- mover `vector`, `pg_net` y `pg_trgm` fuera de `public` con prueba/rollback;
- revisar tabla heredada `n8n_chat_histories_cavallero` sin PK;
- inventariar y retirar Edge Functions históricas `*-once` sólo después de comprobar dependencias.

No se ejecutan cambios disruptivos de plataforma sin ventana y rollback.
