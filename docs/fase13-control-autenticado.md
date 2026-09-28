# Fase 13 — Centro de control autenticado (PR piloto, NO desplegado)

Se agregó en `ui/` la pestaña **Control**, cuyo estado se obtiene bajo demanda mediante
`POST /functions/v1/memoria-home` con `{"action":"control_center"}`.
La pestaña oculta el contenido ante una sesión ausente, muestra el estado real devuelto
por Supabase y limpia los datos ante un fallo de consulta. No hay datos simulados.

## Revisión de seguridad previa al despliegue

El backend `memoria-home` desplegado anteriormente emplea `service_role` para
consultar RPCs. El gate de JWT del entorno por sí solo **no establece que el usuario
sea Duilio**. Esta rama incorpora una comprobación de sesión usando
`supabase.auth.getUser(token)` y compara `user.id` con el identificador
explícitamente aprobado del dueño. Se aplica a GET, home, control_center y plan.

Antes de publicar, el operador debe configurar secretos de entorno de la Edge Function:

- `MD_OWNER_USER_ID`: UUID real de la cuenta autenticada del dueño, comprobado
  directamente en Supabase Auth, **nunca** un UID inventado ni correo en el código.
- `MD_ALLOWED_ORIGINS`: orígenes HTTPS exactos autorizados, separados por coma;
  incluir exclusivamente el origen de hosting comprobado.
- `SUPABASE_SERVICE_ROLE_KEY` sigue privado en entorno Supabase; no incluirlo en UI,
  repositorio, n8n de navegador ni tarjetas Trello.

Si el UID no está configurado, la nueva función deniega con 503; si la sesión no
corresponde al dueño, 401; un Origin ajeno, 403. `OPTIONS` sólo permite un origen
explícito configurado. No se publica sin configuración y prueba autenticada.

## Casos funcionales obligatorios

1. Sin bearer o con bearer ajeno: 401, cero datos de memoria.
2. Owner UID ausente: 503 y sin consultas privilegiadas.
3. Origin distinto: 403; preflight correcto para el origen real.
4. Login real del dueño: Hablar, Ahora, Proyectos, Aprendizaje y Control muestran
   datos vigentes; un 401 borra la pestaña y muestra login.
5. Comparar el total del Centro de control con `memory_control_center_summary()`;
   probar estado bloqueado y ausencia de ejecuciones sin hardcode.
6. Publicar en hosting sólo después de los pasos anteriores; registrar URL, SHA,
   screenshot funcional autenticado y rollback a función/UI anteriores.

**Esta rama no se despliega directamente**: necesita UID autenticado real,
origin verificado y prueba de regresión. No dar por cerrada Fase 13 ni Fase 9
por el CI del PR.
