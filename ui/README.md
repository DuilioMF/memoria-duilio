# UI — Memoria Duilio

Reconstrucción versionada de la interfaz publicada históricamente como Sites v4.

## Estado

Versión: **0.4.0**

Fuente UI versionada en GitHub. El backend operativo del Centro de control está desplegado; la publicación visual de esta revisión todavía requiere validación del hosting. Esta versión conserva el comportamiento anterior y agrega:

- entrada directa en **Hablar**;
- pestañas **Hablar**, **Proyectos** y **Hoy**;
- saludo simple: “Hola Duilio, acá estoy. ¿En qué seguimos?”;
- voz en español y lectura de respuesta cuando el navegador lo soporta;
- proyectos, ejecutor, versión, última acción y última señal;
- pestaña **Control** con autoridad/versiones, salud de fuentes, queue, ejecutor, heartbeat, memorias y aprendizaje;
- resumen de la rutina diaria de las 08:00;
- **Hoy / Proyectos / Ejecutándose / Espera de vos** desde `memoria-home`;
- actualización automática cada 60 segundos;
- trabajos cerrados plegables si el backend expone `closed_runs`;
- sin secretos embebidos.

## API

- Home: `https://pddsehshgfynpmibjqhj.supabase.co/functions/v1/memoria-home`
- Semántica: `https://pddsehshgfynpmibjqhj.supabase.co/functions/v1/memoria-duilio-semantic`

Ambas funciones conservan sus controles de autorización. Nunca usar `service_role` en el navegador.

## Configuración

`config.js` contiene solo URLs públicas y placeholders seguros. El hosting puede inyectar:

- `anonKey` / publishable key;
- un `accessToken` de sesión de corta duración.

No commitear tokens ni contraseñas.

## Validación pendiente

1. Publicar la revisión UI 0.4.0 desde esta fuente.
2. Validar autenticación.
3. Validar Hablar / Proyectos / Hoy sin regresiones.
4. Validar la nueva pestaña Control contra `memory_control_center_summary()`.
5. Registrar URL y evidencia visual del despliegue.
