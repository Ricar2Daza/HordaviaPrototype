# Features por agregar — Hordavia

Este documento separa las nuevas features ya implementadas en el prototipo del
siguiente contenido recomendado. El orden prioriza variedad de decisiones durante
una expedición sin requerir otro bioma completo.

## Ya implementadas

- **Contratos de expedición:** objetivo opcional seleccionable antes de jugar, progreso
  durante la run y recompensa en monedas al completarlo. Definiciones en
  `data/contracts.json`.
- **Reliquias de jefe:** elección de una reliquia única tras derrotar a un jefe.
  Cada reliquia combina una ventaja con una penalización; datos en `data/relics.json`.
- **Prueba de regresión:** ejecutar `Godot_v4.7.2-stable_win64_console.exe --headless
  --path . --script tests/features_smoke.gd` para validar selección de datos, progreso
  y pago único de contratos, y aplicación/obtención única de reliquias.

## Siguiente backlog

### 1. Eventos de bioma con decisiones

Altares, cofres malditos y zonas de riesgo que ofrezcan una elección con consecuencias,
por ejemplo, perder vida máxima a cambio de una mejora o enfrentarse a una emboscada
para obtener una reliquia adicional.

**Criterio de terminado:** al menos un evento por bioma, opciones legibles en móvil,
efectos aplicados una sola vez y recompensa o penalización visible en el HUD.

### 2. Fases y mecánicas propias para jefes

Hacer que los jefes cambien de patrón en umbrales de vida, con ataques telegrafiados
y oportunidades claras para esquivar. Reutilizar los sistemas actuales de carga,
slam e invocación cuando sea apropiado.

**Criterio de terminado:** cada jefe tiene al menos dos fases distinguibles, ataques
anticipables y una prueba de combate que valide transición, daño y derrota.

### 3. Modificadores opcionales de expedición

Reglas configurables antes de empezar, como enemigos veloces, curación limitada o más
élites, con recompensa adicional proporcional al desafío.

**Criterio de terminado:** los modificadores se pueden combinar sin contradicciones,
se muestran antes de iniciar la run y su recompensa queda registrada al terminar.

## Fuera de alcance por ahora

No añadiría todavía más biomas, compras dentro del juego ni sistemas en línea.
Primero conviene comprobar que contratos, reliquias y eventos hacen que las builds
y decisiones de cada run se sientan distintas.
