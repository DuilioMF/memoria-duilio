# Estado operativo — Memoria Duilio

Fecha de actualización: 23/09/2026 (Argentina)

## Modelo operativo vigente

Versión de software: **0.5.0**  
Modelo: **Lean 2.0**

Memoria Duilio se simplificó sin borrar historial ni capacidades avanzadas. El camino normal tiene cuatro funciones:

1. **Estado** — saber en qué está cada proyecto.
2. **Pendientes** — Trello muestra qué falta, qué está en prueba y qué espera a Duilio.
3. **Ejecución** — n8n ejecuta automatizaciones; Supabase guarda ejecución y evidencia.
4. **Aprendizaje** — experiencias verificadas se convierten en conocimiento reutilizable.

## Fuente de verdad por función

- **Supabase:** proyectos, memoria, ejecución, evidencia y auditoría.
- **Trello:** pendientes y estado operativo de tareas.
- **GitHub:** código y versiones.
- **n8n:** automatización.
- **Notion:** documentación e historial narrativo.
- **WhatsApp:** notificaciones.
- **Memoria Duilio:** contexto y orquestación.

No se duplican responsabilidades entre herramientas.

## Qué cambió en Lean 2.0

- La pantalla principal dejó de consultar el Centro de control avanzado en cada refresco.
- El payload principal incluye estado, pendientes, ejecuciones y aprendizaje en una sola llamada.
- El refresco automático pasó de 60 segundos a 5 minutos; el botón **Actualizar** sigue siendo inmediato.
- La UI quedó reducida a **Hablar / Ahora / Proyectos / Aprendizaje**.
- Grafos, controles de integridad avanzados, políticas shadow y tablas históricas se conservan para diagnóstico, pero ya no forman parte del camino normal.
- Notion y WhatsApp quedan como soporte; no gobiernan el estado del sistema.

## Seguridad y continuidad

No se borraron tablas, migraciones, ejecuciones, aprendizajes ni historial. El rollback se mantiene mediante GitHub y las migraciones versionadas.

Hay una deuda de seguridad separada: existen tablas nuevas con RLS deshabilitado. No se habilitó RLS automáticamente porque hacerlo sin políticas correctas puede bloquear consumidores existentes. Debe resolverse tabla por tabla.

## Verificación requerida para publicación

- Validar la UI 0.5.0 publicada.
- Confirmar login autenticado.
- Confirmar que **Ahora** refleja Trello y ejecuciones reales.
- Confirmar que **Aprendizaje** refleja memory_knowledge y memory_experiences.
