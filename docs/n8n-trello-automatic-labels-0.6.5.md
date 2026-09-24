# Memoria Duilio 0.6.5 — Colores y etiquetas automáticos

## Integración activa
- n8n: `Memoria Duilio — Etiquetas y colores automáticos`
- Workflow ID: `MvhFWLKaErHCnifQ`
- URL: https://n8n.srv1251563.hstgr.cloud/workflow/MvhFWLKaErHCnifQ
- Intervalo: **cada cinco minutos**.
- Nodo Trello: usa la credencial existente `trelloApi`; nodo Supabase: `supabaseApi`; no hay claves en el JSON.
- Edge Function de bootstrap `memoria-n8n-trello-labels`: autenticación de token propio contra Vault mediante RPC service_role; no expone secretos.

## Proyectos dados de alta
- Viaje India — verde (etiqueta ya existente).
- WhatsApp pagos FIFO — lima (etiqueta nueva).
- Capacitación IA — Estaciones de Servicio — azul claro (etiqueta nueva).
- Capitán Rodolfo — naranja claro (etiqueta independiente; conserva DoingLio azul como padre).
- Ruben — violeta claro (etiqueta independiente; conserva DoingLio azul como padre).
- Proyecto Conexión — celeste.

## Trabajo del workflow
1. Lee el catálogo de proyectos/colores de Supabase.
2. Lee etiquetas del tablero; sólo crea las que no existen (idempotencia por nombre).
3. Registra sus identificadores de Trello en Supabase.
4. Recorre tarjetas de las listas mediante nodos nativos Trello.
5. Asigna etiquetas faltantes sin borrar etiquetas ajenas.
6. Corrige títulos únicamente si una tarjeta tiene una pertenencia inequívoca.
7. La idea compartida Supervisión / Reloj Feli conserva ambas etiquetas.
8. Todo proyecto registrado a futuro recibe un color estable por hash desde el trigger SQL.

## Evidencia
- Corrida n8n `10189`: `success` después de corregir una incompatibilidad del nodo HTTP genérico con la credencial Trello.
- 5 etiquetas nuevas comprobadas en el tablero, utilizadas por sus tarjetas.
- Los cinco identificadores se registraron en `memory_projects.metadata.trello`.
- 56 tarjetas: relectura/sincronización 56 actualizadas, 0 nuevas, 0 archivadas, auditoría `issue_count=0`, una idea compartida detectada separadamente.

## Seguridad
- n8n administra permisos usando credenciales ya instaladas; no se copian API keys a JSON.
- Edge bootstrap exige el token existente en Vault mediante hash; el endpoint rechaza llamadas sin credenciales.
- Funciones RPC y tabla de despliegues son sólo backend (service_role).
- No borrar ni modificar las Edge Functions antiguas; no abrir rutas sin control.

## Rollback
Restaurar código al commit previo `93acc4f53ae4a6cecbee6ea39849681c6bf5b1b3`; desactivar workflow en n8n si hay un problema. Las nuevas etiquetas se conservan para que los proyectos no pierdan color. La creación de proyectos en sistemas externos distintos de Trello está encolada en la arquitectura universal y no se declara realizada hasta que sus conectores la confirmen.
