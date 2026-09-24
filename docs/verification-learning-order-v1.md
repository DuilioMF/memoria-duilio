# Memoria Duilio 0.6.1 — verificación segura

## Corrección
Se corrigió el orden del Learning Loop: la clasificación de dominio ocurre antes de insertar una verificación. Esto evita que la inmutabilidad de experiencias verificadas bloquee una verificación legítima.

## Prueba real
La documentación viva de Fase 8 fue escrita en Notion, releída y verificada. La verificación quedó persistida con resultado `success` y la experiencia pasó a `learned`.

## Fase 8
El progreso ahora está protegido por evidencia. Son 8 controles; 7 están cumplidos. Estado observado: **88%**.

Pendiente único:
- recuperar correctamente Memoria Duilio desde otra conversación real y registrar `phase8-cross-conversation-e2e = success`.

El sistema no puede declarar 100% mientras falte esa prueba.
