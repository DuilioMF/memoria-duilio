# CONTRATO EJECUTABLE CE-1

**Uso:** una tarjeta representa **un entregable verificable**. Nunca se convierte una conversación, historia de versiones o una idea en prueba aprobada.

## Identificación y autoridad
- Título Trello: `Proyecto — entregable`; etiquetas del proyecto asignadas automáticamente.
- Card ID / URL estable; project_key de Supabase; ejecución asociada a GitHub issue/PR.
- Rama, archivo de versión, SHA de referencia, candidato vs producción. El archivo Git es autoridad del código; la tarjeta solo refleja Git.
- `executor_key` debe venir de `memory_executor_registry` mediante `memory_select_executor_v2`. No elegir Claude Code/Chat si siguen `pending_connection`. Registrar el ejecutor que efectivamente realizó la acción, no uno proyectado.

## Objetivo, insumos y cambios
- **Un resultado observable**, situación inicial y fuente verificable.
- Entradas/salidas y contrato técnico: archivos, rutas, API y SQL **confirmados en código**, no deducidos.
- Alcance positivo, fuera de alcance, dependencias y restricciones de seguridad.
- Si falta fuente o información para implementar, marcar `needs_clarification` y NO ejecutar ni inventar.

## Criterios y pruebas
- Escenarios enumerados y deterministas `S01...`: condiciones previas, acción, resultado esperado, escenario de error y evidencia.
- Separar CI automático, TEST autenticado, dispositivos reales y pruebas físicas; `CI success` por sí solo NO habilita ni cierra.
- Una subtarea nueva por cada defecto adicional o nueva funcionalidad para mantener el entregable acotado.

## Habilitación y cierre seguro
- La función `memory_card_closure_gate(card_short_url)` es **denegación por defecto**.
- Requiere contrato en `ready`, ejecutor real registrado/ready, **todos** los casos con resultado `pass` y enlace de evidencia.
- Si aplica, exige CI (run+commit), publicación y smoke test (URL+commit), rollback verificado (punto de restauración).
- Las tres tarjetas piloto exigen **aprobación humana explícita**, vinculada a evidencia; ni n8n, ni CI, ni un checklist vacío reemplazan la aprobación.
- **No instalar un automatismo que llame a Trello /cards/{id} para mover a Verificado y cerrado sin consultar primero este gate y comprobar `allowed=true` en esa misma ejecución.**
- Al cerrar: comentario con alcance, evidencias, versión, ejecutor, aprobación, restauración y hora real. Si falla: permanecer En prueba o Espera de vos.

## Incidentes opcionales
`INCIDENTE → CAUSA EVIDENCIADA → CORRECCIÓN → PRUEBA DE REGRESIÓN → REGLA PREVENTIVA`. Conservar evidencia histórica y enlaces, no mezclar cronología vieja con la especificación vigente.

## Migración de tarjetas existentes
Piloto con 3 de las 28 abiertas iniciales (la tarjeta de capacitación está cerrada administrativamente pero pendiente de prueba). No reformatear las 28 ni marcar checks de forma masiva. Historia original **sin borrar**: resumen arriba en Trello, contrato íntegro con commit inmutable en Git, checklist de gates separado de checklists históricos.
