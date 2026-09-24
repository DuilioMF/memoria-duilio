# 0.6.3 — Memoria Duilio: routing por dominio

La clasificación de experiencias usa prioridad por contexto: orquestación n8n, negocio Revalsoft/YPF, SQL, e integración genérica. Así, un workflow de n8n que contiene un nodo Postgres sigue siendo n8n; una regla de Revalsoft que consulta SQL sigue siendo una regla de negocio.

## Pruebas en Supabase (23/09/2026 Argentina)
- texto "n8n" solo => n8n_limitation (regresión específica corregida)
- n8n workflow Postgres => n8n_limitation
- SQL Server stored procedure => sql_pattern
- Revalsoft YPF SQL => business_rule_ypf
- Supabase API GitHub => integration_gotcha

## Seguridad ya verificada en 0.6.2
Linter posterior: cero RPC privilegiadas expuestas, vistas SECURITY DEFINER, funciones con search_path mutable y FK sin índice. Prueba adicional backend memory_resume_project => VIGENTE + protocolo presente; anon/authenticated sin permiso a RPC interna, service_role permitido. Pendientes de plataforma (upgrade PostgreSQL, extensiones y auditoría de tests) continúan exclusivamente en Mantenimiento.
