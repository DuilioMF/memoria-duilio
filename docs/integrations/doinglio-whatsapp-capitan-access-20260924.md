# DoingLio WhatsApp — acceso a Capitán Rodolfo (24/09/2026)

**Estado:** backend instalado y probado; integración con workflow activo pendiente de aplicación y prueba real de WhatsApp. No declarar el circuito terminado hasta tener evidencia de recepción y envío.

## Inventario comprobado

- n8n: `WhatsApp escuchando DoingLio Chatgpt` (`8ntdTH4noil3rQbE`), activo y con 30 nodos en la última comprobación. La variante antigua `m2BCQdIghvOrbuDI` estaba inactiva.
- Supabase proyecto `n8n`: `pddsehshgfynpmibjqhj`.
- Checkpoint previo del workflow en `doinglio_private.n8n_workflow_backup`. Restaurar desde él si la nueva ruta falla. **No publicar el JSON completo: puede contener referencias de credenciales y datos internos.**
- 9 nodos aparentemente huérfanos identificados; eliminar solo después de revisar expresiones/referencias y guardar otro checkpoint. No borrar ramas de otros usuarios.
- El historial anterior `n8n_chat_histories` tenía 178 entradas y 178 respuestas en 5 sesiones al comprobarlo. No confundir generación de respuesta con entrega por Meta.

## Backend desplegado

- Tabla `doinglio_phone_access`: permiso por número y especialista, `enabled`, `payment_exempt`, `paid_until`, rol y auditoría de cambios futura.
- Función `doinglio_check_phone_access`: no registrado, deshabilitado, pago vencido o autorizado. Deniega por defecto.
- Tabla `doinglio_wa_message_audit`: eventos de entrada, permiso, intento de envío; el estado *delivered/read* exige Webhook de estado Meta adicional.
- Tabla `doinglio_sql_question_queue`: solicitudes autorizadas al conector SQL local (todavía no consume el conector).
- `doinglio-wa-gateway` v2: Edge Function protegida con clave privada compartida en Vault, valida y registra, responde con texto diferente según rechazo. Ya probadas las cuatro condiciones por HTTP sin enviar WhatsApps.
- `doinglio-wa-operator` v2: adaptador administrativo protegido, acciones `inspect` e `install` para guardar checkpoint, crear credencial de encabezado privada en n8n, insertar rama condicional de Capitán, enviar respuesta y registrar resultado. **La instalación no se ejecutó** por restricción de acceso de herramientas; no presuponer que el workflow ya cambió.
- El número administrador termina en 2112; no publicar el número completo en repositorios públicos.

## Contrato funcional de conexión

1. Recibir WhatsApp (texto/audio) y normalizar como ya hace el workflow principal.
2. Antes de dirigir mensajes de Capitán a consultas SQL, llamar a `doinglio-wa-gateway` con el número real de Meta, el ID de mensaje, tipo y texto normalizado. **Nunca confiar en un número escrito dentro del texto del usuario.**
3. Si `handled=false`, continuar las ramas existentes sin modificación.
4. Si `handled=true`, responder `response_text` por el mismo WhatsApp Business y no continuar hacia ramas generales. Registrar el resultado de la API Meta, con el ID de respuesta y el ID de pregunta. Fallas de registro y envío deben producir alertas; no anunciar entrega solo por tener código HTTP 200.
5. Solo un permiso activo no vencido puede crear una solicitud para el conector local. La conexión a SiSRL debe ser de solo lectura, ejecutar consultas permitidas y responder de forma asíncrona; hasta conectarla, el bot informa expresamente que no tiene datos reales.
6. Suspensión: «Tu acceso a Capitán Rodolfo está suspendido. Contactá al administrador de DoingLio para solicitar la reactivación.»
7. No registrado: «Tu número no está dado de alta para hablar con Capitán Rodolfo. Solicitá tu habilitación al administrador de DoingLio.»
8. Vencido: «Tu suscripción a Capitán Rodolfo está vencida. Regularizá el pago con el administrador de DoingLio para continuar.»

## Gates de verificación obligatorios

- Verificar checkpoint y conservación de ramas de todos los usuarios y de `n8n_chat_histories`.
- Aplicar versión del workflow en n8n usando el adaptador protegido desde un entorno autorizado; ejecutar `inspect` de nuevo para confirmar inserción de nodos.
- Probar los cuatro estados de suscripción con números de prueba que consientan recibir mensajes; registrar IDs de ejecución y resultado de Meta. No enviar mensajes de prueba a números no consentidos.
- Probar pregunta de tanques con SiSRL solo cuando el conector local haya consumido y respondido una solicitud real.
- Registrar evidencia y versión en la tarjeta Trello **DoingLio WhatsApp — accesos por teléfono, mensajes y conector Capitán**. Mantener EN PRUEBA hasta verificaciones completas.

**Seguridad:** las claves del gateway y del operador viven únicamente en Vault/credenciales de n8n. Nunca copiarlas a Git, Trello, Notion, registros o mensajes de WhatsApp.

## Prueba segura en n8n — archivos preparados el 24/09/2026

Se prepararon dos JSON importables y una guía paso a paso; **no** se reemplazó ni se activó automáticamente el workflow de producción. Los archivos están guardados en la Biblioteca privada de ChatGPT del usuario, carpeta `/DoingLio/WhatsApp/`, y en la conversación para descarga:

- `DoingLio_PRUEBA_Permisos_Manual_n8n.json`: flujo independiente con Manual Trigger que comprueba el rechazo de un teléfono ficticio no registrado. No envía WhatsApp ni consulta SQL; devuelve `TEST=OK` y `reason=not_registered` si funciona.
- `DoingLio_WhatsApp_Capitan_ACL_IMPORTAR_INACTIVO.json`: exportación sanitizada con 28 nodos (30 del original - 9 prototipos desconectados + 7 nodos nuevos). Mantiene el enrutamiento original salvo la intercepción explícita para Capitán; inicialmente está inactiva y sin ID de producción.
- `LEEME_DoingLio_WhatsApp_PRUEBA.txt`: configuración y verificación.

**Preparación requerida, exclusivamente dentro de n8n:** crear una credencial privada de tipo HTTP Header Auth denominada `DoingLio Supabase Gateway`, con nombre de header `x-doinglio-gateway-key` y valor obtenido de forma privada de la clave de Vault `doinglio_wa_gateway_key` del proyecto Supabase n8n_1. No se incluye la clave en ningún JSON, GitHub, Notion, tarjeta ni conversación. Seleccionar esta credencial en el nodo HTTP del flujo manual y en los tres nodos nuevos de gateway del flujo completo.

**Prueba primero:** importar solamente la prueba manual, seleccionar la credencial y pulsar *Execute Workflow*. Verificar el resultado del nodo final. Solo después importar la copia completa como workflow separado **inactivo**. Dos WhatsApp Trigger activos asociados al mismo número pueden entrar en conflicto: el cambio productivo debe hacerse de manera controlada tras verificar credenciales, ramas anteriores y respaldo.

**Observaciones de seguridad:** los nodos de descarga de imágenes del archivo original contenían un token Meta escrito en claro. La copia entregada lo sustituyó por referencia a la credencial existente `Header Auth account 200`, que debe ser actualizada tras rotar el token de Meta. El envío que Meta acepta no acredita entrega; el webhook de estados Meta sigue pendiente. El conector SQL Windows y la respuesta de cola a WhatsApp no están verificados extremo a extremo.

**Estado Trello:** https://trello.com/c/LJIlXAeR — En prueba. Esta guía pública no incluye los archivos JSON con identificadores de teléfonos y referencias privadas; permanecen en la Biblioteca del usuario.
