# MD Fase 10 — Entrega de propuestas de código vía GitHub Actions

**Estado:** adaptador propuesto; no habilita ni acredita el Execution Loop integral.

## Qué se implementa

El evento `repository_dispatch` con `event_type=md_propose` o una ejecución manual de `MD - Propuesta acotada por tarjeta` inicia un runner real en GitHub Actions. La acción lee **solo 1–3 archivos existentes y permitidos** dentro de `ui/` o `docs/`, llama a un modelo OpenAI configurado con un secreto de GitHub, verifica que la respuesta no cambie otros archivos, ejecuta `git diff --check` y `node --check` cuando corresponda, crea una rama independiente y propone un **pull request para revisión**.

No modifica `main`, no fusiona PR, no despliega, no escribe en Trello ni Supabase y no marca ninguna tarjeta como terminada. No permite propuestas en `supabase/`, credenciales, workflows, scripts ni políticas CE-1. Una tarea que requiera esos ámbitos **queda bloqueada** hasta que tenga un ejecutor especializado con otros permisos.

## Preparación necesaria (ningún secreto en repos ni en Trello)

1. Registrar `OPENAI_API_KEY` como **Actions repository secret** en `DuilioMF/memoria-duilio`. El agente por API es independiente de la sesión personal de ChatGPT Work.
2. Autorizar en n8n una credencial GitHub **de alcance mínimo** que pueda enviar `repository_dispatch` únicamente a este repositorio. Nunca colocar el token en el JSON, en nodos Code o en documentación. No se afirma que esta credencial exista actualmente.
3. Probar manualmente una tarjeta piloto no crítica con archivos explícitos. Comprobar la ejecución y el PR. Sin respuesta efectiva de GitHub o sin clave OpenAI el flujo queda bloqueado, no aprobado.
4. Completar, como trabajo separado, un dispatcher n8n que consulte el router canónico de Supabase, haga un **claim específico al mismo queue_id**, mantenga un heartbeat/lease, envíe la tarea, verifique el PR y registre `card_url`, `queue_id`, `run_id`, `run_key`, pruebas y rollback. Este worker **no suplanta** dicho circuito de cola.
5. Antes de mover una tarjeta a «Verificado y cerrado», comprobar en ESA ejecución `memory_card_closure_gate(card_url).allowed === true` con aprobación auténtica de Duilio desde el evento real de Trello. Un PR por sí solo es insuficiente.

### Ejemplo de payload (sin secretos)

```json
{
  "event_type": "md_propose",
  "client_payload": {
    "card_url": "https://trello.com/c/E7ZOVRGE",
    "queue_id": "11111111-2222-3333-4444-555555555555",
    "run_key": "AUTO-20260927-0800",
    "title": "Tarea piloto",
    "problem": "Cambio pequeño y acotado en la página",
    "allowed_files": ["ui/app.js"],
    "acceptance_criteria": ["node --check ui/app.js"]
  }
}
```

Los IDs del ejemplo son ilustrativos; el dispatcher debe obtener los reales y no reutilizarlos. La tarjeta debe ser elegible en Trello y la decisión del router debe ser real, no una tarea de ejemplo codificada.

## Pruebas y observabilidad

`python -m unittest discover -s tests -p test_md_proposal_worker.py -v` verifica rutas, ID, límites y salidas peligrosas sin gastar API. CI ejecuta estas pruebas en pull requests. El primer `repository_dispatch` real exige credenciales configuradas y un caso piloto que genere cambios y un PR. Registrar su URL y SHA; no presentar las pruebas unitarias como prueba end-to-end.

El ciclo solicitado a las 08:00 sigue pendiente de integrar y verificar; este adaptador aporta únicamente la fase «ejecutar/proponer cambio real en rama revisable» de forma segura.

## Piloto autónomo acotado — registro de evidencia

Esta sección documenta la evidencia verificable para la primera prueba autónoma mediante GitHub Actions en este repositorio.

**Importante:** Este piloto es únicamente GitHub-only y NO demuestra el circuito natural a las 08:00: Trello → n8n → cola de MD real. Tampoco usa una cola MD real ni autoriza el cierre automático de tarjetas en Trello, merge o deploy.

---

### Plantilla de auditoría de evidencia

- **Issue URL:** (URL a la tarjeta/issue original en Trello o sistema equivalente)
- **Piloto UUID correlation-only:** (UUID único asociado a este piloto para correlación, sin impacto operativo)
- **run_key PILOT:** PIlot run_key asociado (ejemplo: "PILOT-20260928-1820")
- **GitHub Actions run URL:** (Enlace directo a la ejecución de GitHub Actions que ejecutó el piloto)
- **Hash commit:** (SHA commit generado por la propuesta en rama para revisión)
- **Pull Request generado:** (URL del PR creado para revisión manual)
- **Pruebas realizadas:** (Listado breve de pruebas ejecutadas, p.ej., `git diff --check`, `node --check`)
- **Resultado humano:** (Descripción del análisis humano tras revisar PR y evidencia; no se afirma éxito antes de esta evaluación)
- **Criterio CE-1 aplicado:** (Confirmación de cumplimiento o bloqueo respecto a política CE-1)
- **Rollback:** (Estrategia o acción tomada para revertir cambios si la propuesta no es aceptada o detecta fallas)

---

Esta plantilla debe completarse con enlaces y hashes reales tras la ejecución y revisión práctica de la prueba piloto.
