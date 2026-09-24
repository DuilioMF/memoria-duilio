# Memoria Duilio 0.6.7 — Gate humano de entrega

El piloto CE-1 tiene tres contratos y **ninguno ha sido aprobado por pruebas funcionales reales**. No confundir "especificación escrita" ni "CI PASS" con "entrega habilitada".

## Dato de autorización confiable
Para que `memory_card_closure_gate()` autorice un cierre automático:
1. Contrato en estado `ready` (revisado respecto del código/fuente vigente).
2. Ejecutor real registrado mediante `memory_executor_registry`, no solo planeado.
3. Cada `required_case_id` tiene `case_evidence` con `result=pass` y `evidence_ref` comprobado.
4. Según tipo: CI con SHA y URL, despliegue y smoke, rollback realmente verificado.
5. **Aprobación humana explícita**, con `human_approval.result=approved`, `actor=required_approver`, `source=trello_member_verified`, `member_id=trello_approver_member_id`, evidencia enlazada a tarjeta y `verified_at`. El proceso que llena el registro DEBE consultar el evento real de Trello y comprobar que lo publicó el miembro autorizado. El SQL comprueba la estructura/identidad declarada; no puede consultar Trello por sí solo.

La función es denegación por defecto: una tarjeta nueva sin contrato o con cualquier caso sin verificar recibe `allowed=false`. Solo `service_role` puede llamarla; `anon` y `authenticated` no.

## Regla para n8n
- Antes de cualquier actualización de lista a **Verificado y cerrado**, una automatización debe solicitar el resultado del gate y comprobar `allowed===true` en ESA ejecución.
- Si no puede acceder al gate, un caso falla, falta test real o no existe consentimiento verificable de Duilio: **NO mover** la tarjeta y registrar bloqueo/owner de siguiente acción.
- Los flujos de sincronización de versiones y colores pueden cambiar títulos/etiquetas, **nunca** deben deducir automáticamente cierre de un build.
- Aún no se modificaron automatismos ajenos para interceptar cualquier vía de cierre: este release proporciona el gate de backend, no sustituye un control de permisos de Trello.
- En la auditoría de flujos con nombre "Memoria Duilio" no se detectó ningún nodo Trello que moviera tarjetas a cerradas: los escritores encontrados modifican nombre, etiqueta o comentarios.

## Piloto registrado
- [Supervisión](https://trello.com/c/Gk6jvAIY): S01–S05 + CI + publicación + rollback + aprobación.
- [Capitán Rodolfo](https://trello.com/c/Ju1hmWW9): C01–C06 + release/local + rollback + aprobación física.
- [Capacitación IA](https://trello.com/c/T2xmrKV5): E01–E05 + aprobación. Es trabajo documental; CI/rollback de software no aplican.
Los checklists se crean sin marcar casillas; el historial preexistente se conserva debajo del resumen operativo en la misma tarjeta.

**Regresión de SQL a verificar:** contrato sin casos → denegado; falta de pruebas reales → denegado; aprobación de autor no autorizado → denegado; aprobación del miembro autorizado con evidencias reales → autorizado si se satisfacen todos los demás gates.
