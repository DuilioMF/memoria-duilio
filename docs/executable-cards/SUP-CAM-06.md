# SUP-CAM-06 — Supervisión: vídeo → carro → siguiente producto

**Contrato piloto CE-1, 24/09/2026.** Proyecto `supervision`. Tarjeta https://trello.com/c/Gk6jvAIY. Estado actual: En prueba, **producción NO autorizada**.

**Objetivo indivisible:** verificar el ciclo continuo de cámara que reconoce y permite agregar una sola vez cada producto mostrado; rearmar únicamente tras retirar/cambiar producto. Si aparecen fallos de enseñanza v1.21 u otras mejoras, emitir subtarea separada, no agrandar este gate de v1.20.

## Autoridad de versión y código
- Repositorio: https://github.com/DuilioMF/Supervision
- En el instante de esta especificación: `main` = `c0a9dc8d50c65d8e4cb242f9434047478471433f`, `src/version.js` declara **v0.1.6**.
- Candidato **no fusionado**: [PR #20](https://github.com/DuilioMF/Supervision/pull/20), rama `supervision-video-flow-v1-20`, SHA `b450db406ae69be6a0e876862c7ebd96183fe23f`; `src/version.js` de esa rama declara **v1.20**.
- Preview descrita en tarjeta: https://supervision-video-flow-v1-20-supervision.duiliofracchia.workers.dev. No se certificó en este piloto que el despliegue corresponda hoy a ese SHA: recuperarlo mediante registro de Cloudflare/CI.
- `v1.21` aparece en checklist de fotos, **no** en la rama candidata verificada. No convertir checklist en release ni marcarlo aprobado.

## Handoff inequívoco
`executor_key` mediante `memory_select_executor_v2` para una tarea de código de Supervisión; `chatgpt-work` está registrado como ready (el despacho efectivo debe comprobarse). `claude-code` está `pending_connection`, excluido; `n8n` coordina y almacena evidencia, pero no acredita prueba física.
Revisar **en la rama candidata** `src/components/Camera.jsx`, `src/supervision/catalog.js`, `src/supervision/store.js`; contrastar `tests/camera.spec.js` de la misma rama; no modificar producción para probar.

## Entradas / procedimiento
Usuario de TEST con permiso de cámara, teléfono móvil, navegador escritorio, catálogo ERP de prueba y dos productos conocidos (A y B) más uno desconocido X; confirmar IDs ERP reales de TEST antes de implementar.
1. A visible y reconocido → agregar al carro.
2. Seleccionar “Siguiente producto” sin retirar A.
3. Retirar A y presentar B; repetir detección/carro.
4. Presentar X, capturar, seleccionar ID ERP y guardar; simular falla de guardado en TEST.
5. Simular permisos denegados y fallo de conexión; observar reintento y estado visible.
No usar datos de otros usuarios ni resetear catálogo productivo.

## Aceptación con evidencia por caso
- **S01:** A detectado → **exactamente una unidad de A** agregada, cámara continúa.
- **S02:** sin retirar A, “Siguiente producto” exige retirarlo y **NO** duplica A aunque persista en cuadro.
- **S03:** retirar A y presentar B: rearme automático sin reiniciar cámara, **una unidad de B**.
- **S04:** X desconocido → permitir foto, asignación a ID ERP de TEST y persistencia para próxima detección; si guardar falla, no informar éxito ni crear asociación parcial.
- **S05:** permiso denegado o red caída: error recuperable visible, carrito conserva integridad sin duplicados.

Para cada caso: `resultado=pass|fail`, timestamp, dispositivo/navegador, SHA del binario desplegado y enlace a captura/video/log anonimizado; no escribir sólo “probado”.
CI identificable en GitHub Actions con commit exacto. Prueba funcional **real** por Duilio/dispositivo real; aprobación explícita antes de producción. El release debe conservar URL + SHA + smoke post-deploy. Registrar el último release funcional como rollback; el PR abierto no es rollback.

## Fuera de alcance / incidentes
Nuevo algoritmo de embedding, cambios de catálogo global, edición de secretos, rediseño de estilos y v1.21 deben gestionarse independientemente. Patrón opcional ante fallos: INCIDENTE → causa reproducida → corrección → regresión → regla.
