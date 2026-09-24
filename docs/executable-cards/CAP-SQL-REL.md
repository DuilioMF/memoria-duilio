# CAP-SQL-REL — Capitán Rodolfo: aceptar conexión local a SQL Server

**Contrato piloto CE-1, 24/09/2026.** Proyecto `capitan-rodolfo` (hijo de DoingLio). Tarjeta https://trello.com/c/Ju1hmWW9. Estado: Espera de vos. Es una **validación funcional de un release existente**, no un pedido automático de cambios en producción.

## Fuente de verdad y conflicto detectado
Repositorio https://github.com/DuilioMF/capitan-rodolfo, `main` SHA `e004cc11d551df4e69c371cfe39ba3b8403ec88f` con archivo `VERSION=79` al auditar. La tarjeta decía v78 y describía pruebas v65; `README.md` también menciona v76. Son referencias históricas; no usarlas como protocolo de aceptación vigente. URL https://duiliomf.github.io/capitan-rodolfo/; **NO se ha comprobado con esta auditoría que el sitio o el conector del PC ya sean v79**. Antes de probar, verificar el SHA/versión real de ambos.

## Objetivo e insumos
Comprobar apertura desde Windows, actualización recuperable y lectura real **solo lectura** de SQL Server local en `DUILIO\SQLEXPRESS`, base `SISRL`, usuario `DUI`, sin publicar contraseña ni información comercial.
Fuente técnica a inspeccionar por el ejecutor: `bridge/`, `conexion-sql.html`, `sp_allowlist.json`, instaladores BAT, `VERSION`; contrastar con conector realmente instalado en `C:\Sistemas`. Backups de `conexion.json` y `credenciales.dat` protegidas localmente.

## Ejecutores y dependencias
La corrección de código, **solo si un caso falla**, se deriva mediante `memory_select_executor_v2`; `chatgpt-work` es fallback ready, `claude-code` sigue pending_connection. La **prueba contra ese SQL/Windows** necesita la PC de Duilio y no es reemplazable por una prueba simulada de CI. No marcar ejecución remota si no hay trabajo real.

## Casos de prueba reproducibles
- **C01:** ejecutar acceso directo con conector detenido; iniciar/actualizar desde la fuente válida y abrir DoingLio/Capitán **sin dejar consola DOS** residente. Debe identificar errores y no perder configuración.
- **C02:** abrir bridge; detectar el puerto local realmente disponible. Si todos fallan, instalar debe dejar `install.log` con error accionable y página NO debe indicar conectado.
- **C03:** con SQL encendido y acceso válido, seleccionar `SISRL`, consultar `SELECT * FROM SURPLA` por la vía de solo lectura permitida: devolver filas auténticas o estado sin filas; identificar instante y tabla.
- **C04:** consultar `Tanque`; surtidores/despachos solamente si ya hay SP autorizado para eso. Si aparece error `TRY_CONVERT` en versión antigua, identificar sentencia exacta, corregir en rama con alternativa compatible y agregar test antes de actualizar local.
- **C05:** apagar SQL o negar acceso controladamente → diagnóstico visible sin declarar lectura exitosa ni mostrar caché como actual; restaurar servicio y recuperar conexión.
- **C06:** cerrar y abrir conector de nuevo; recuperar instancia/base no secretas y contraseña cifrada, sin secretos en logs, Trello, capturas ni Git.

Cada C01–C06 requiere `pass/fail`, fecha, versión de bridge y UI, salida/registro anonimizado. Si falla, abrir subtarea de ese defecto con pasos y logs; NO combinar facturas/API key/voz con la aceptación de conexión.
Para autorizar cualquier actualización: identificar **último release local realmente funcional**, respaldar configuración y asociar SHA de restauración; la antigua rama `rollback-v63-before-cloud-sql` NO demuestra que sea la restauración adecuada de v79.
**Cierre:** Duilio confirma expresamente ejecución real C01–C06 en su PC; sin ese gate permanece en Espera de vos/En prueba.
