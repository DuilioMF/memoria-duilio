# UI — Memoria Duilio

Reconstrucción versionada de la interfaz publicada históricamente como Sites v4.

## Estado

Versión: **0.1.0-recovery.1**

No se declara canónica. La fuente original de ChatGPT Sites no estaba en GitHub y el ZIP histórico no apareció en la biblioteca disponible. Esta reconstrucción conserva el comportamiento verificable registrado:

- entrada directa en **Hablar**;
- pestañas **Hablar**, **Proyectos** y **Hoy**;
- saludo simple: “Hola Duilio, acá estoy. ¿En qué seguimos?”;
- voz en español y lectura de respuesta cuando el navegador lo soporta;
- proyectos, ejecutor, versión, última acción y última señal;
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

## Criterio para pasar a versión canónica

1. Publicar desde esta fuente o recuperar la fuente original.
2. Validar autenticación.
3. Validar Hablar.
4. Validar Hoy / Proyectos / Ejecutándose / Espera de vos contra Supabase/Trello reales.
5. Verificar despliegue público/privado y registrar evidencia.
6. Recién entonces quitar el sufijo `recovery`.
