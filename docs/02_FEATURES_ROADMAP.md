# Features a implementar — Hordavia (de prototipo a MVP jugable)

**Estado al 30/10:** Fase 1 ✅; Fase 2 2.1–2.7 ✅; Fase 3 3.1–3.5 ✅ (sin fin);
Fase 4: 4.1–4.5 ✅; Fase 5: 5.1–5.4 ✅; 5.5 🟡 (layout responsive + check
automático; falta prueba en hardware); export Android debug ✅ (5.6 parcial).
**Siguiente: 5.7** (traducciones es/en) y prueba física de 5.5/5.6.

Estado base: el prototipo ya valida el loop (joystick, MultiMesh bullets, spawn
director JSON, armas `aimed`/`orbit`, XP+cartas, guardado, shader toon, smoke QA).
Esta lista es **todo lo que falta** para tener un MVP publicable, ordenado por fase.
Esfuerzo: S = horas, M = días, L = semana+.

## Fase 1 — Game feel de combate (vertical slice) ✅ COMPLETA
| # | Feature | Detalle / Definition of Done | Esf. | Estado |
|---|---------|------------------------------|------|--------|
| 1.1 | **Salto + dash con botón táctil** | Botón derecho en pantalla (2.º pulgar). Coyote 0.12 s, dash 3 s cd + i-frames | M | ✅ |
| 1.2 | **Alturas/mapa procedural** | `world/terrain.gd`: heightfield por run (ruido, celdas 2 m, escalones 0.25 m, relieve bajo) + cofres con recompensas | M | ✅ (sin castigo de caída) |
| 1.3 | **Números de daño flotantes** | Pool de Labels billboarding, 40 | S | ✅ |
| 1.4 | **Partículas de muerte** | Cubos voxel one-shot pool 24, color por enemigo | S | ✅ |
| 1.5 | **Audio SFX + música** | 100 % procedural (`AudioManager`); SFX + loop Am–F–C–G | S | ✅ |
| 1.6 | **Screen shake + hitstop** | Shake al daño | S | ✅ (hitstop pendiente) |
| 1.7 | **Vignette de daño** | Flash + pulso HP<30 % | S | ✅ |
| 1.8 | **Élites periódicos** | Cada 90 s: escala 1.5×, HP×8, orbe×4 | S | ✅ |

## Fase 2 — Progresión completa en-run
| # | Feature | Detalle | Esf. | Estado |
|---|---------|---------|------|--------|
| 2.1 | **8 armas base (data-driven)** | `orbit`, `aura`, `boomerang`, `mine`, `chain`, `spiral` y `frost`, además del bastón inicial | M | ✅ |
| 2.2 | **Evoluciones de armas** | 8 recetas `data/evolutions.json` (arma L8 + pasiva N → evolucionada); carta legendaria garantizada | M | ✅ |
| 2.3 | **Reroll / banish / skip** | Pie de cartas: reroll 1/run, desterrar 1/run (fuera del pool toda la run), saltar +15 XP | S | ✅ |
| 2.4 | **Pasiva luck** | `luck_1` ×1.3 peso de rarezas no comunes por stack (máx 5) | S | ✅ |
| 2.5 | **Pasivas restantes** | `regen_1` (+0.6 HP/s), `area_1` (+12 % radios), `armor_1` (−8 % daño, tope 60 %) | S | ✅ |
| 2.6 | **Nivel de armas (I–VIII)** | Cartas dinámicas "mejorar arma X": +12 % daño / +6 % cadencia por nivel, tope VIII (`weapon_levels`) | M | ✅ |
| 2.7 | **Cofres y pickups de mapa** | Cofre por élite + drops 2 %: cura +25, imán +20/6 s, bomba 80 AoE | S | ✅ |

## Fase 3 — Mundo y jefes
| # | Feature | Detalle | Esf. | Estado |
|---|---------|---------|------|--------|
| 3.1 | **7 biomas con set dressing** | Paleta, luz, props y tablas de hordas propias; ciclo de 42 min | L | ✅ |
| 3.2 | **Transición de bioma** | Fundido 0.9 s + banner + anillo de portal en el jugador; sin recarga de escena | M | ✅ |
| 3.3 | **Hazards ambientales** | Data-driven por bioma: ralentización, lava, veneno y hielo; clima asociado | M | ✅ |
| 3.4 | **Jefe con IA por bioma** | 7/7: carga, slam o volley, visual único e invocaciones; reaparecen al repetirse el ciclo | L | ✅ |
| 3.5 | **Supervivencia sin fin** | Sin victoria: biomas en bucle, HP/daño/spawn escalan por minuto y ciclo; solo se termina al morir | S | ✅ |

### Extras entregados (fuera de numeración original)
- Controles corregidos: WASD/joystick ahora son **relativos a cámara** (antes invertidos).
- Cámara **Fija ⇄ Mouse** (tecla C; el mouse se captura y orbita la cámara). Persistencia del ajuste en save.json.
- **Menú de pausa** (ESC): continuar / cámara / reiniciar / salir.
- Monstruos por progresión: ya cubierto por tablas por bioma (JSON) + élites + jefe.
- Evoluciones: Railgun de niebla, Supernova y Tempestad de discos (nodos de arma reconstruidos en caliente); smoke verifica la receta con `SMOKE_EVOLVE`.
- **InputMap central** (`core/input_setup.gd`): teclado, ratón y gamepad comparten acciones (`move_*`, `jump`, `dash`, `toggle_camera`, `pause`, `cam_*`). Mando: stick izq. mover, A saltar, B dash, Y cámara, Start pausa, stick der. orbita en modo Mouse.
- **CI + validador de contenido**: `.github/workflows/ci.yml` importa, valida `data/*.json` con `tools/validate_content.gd` y corre el smoke. `.godot/` y el binario del engine quedan fuera de git (`.gitignore`).
- **Layout táctil responsive**: joystick y botones escalan con el viewport (5"/6.5"/tablet), respetan el safe area y la hitbox coincide con lo dibujado. `tools/check_layouts.sh` valida 3 tamaños en headless (también en CI).
- **Hápticos móviles**: vibración en daño, dash, salto, jefe, level-up y game over, con toggle persistente en Ajustes → Móvil. Permiso `VIBRATE` activado en el preset Android.
- **Build Android reproducible**: `tools/build_android.sh` compila debug/release y avisa si faltan export templates; checklist de prueba física en `docs/05_EXPORT_ANDROID.md`.
- **Enemigos a distancia**: `archer`, `spitter`, `sandcaster` y `shaman` mantienen rango, telegrafían y disparan proyectiles hostiles con pool propio (`core/hostile_projectiles.gd`).
- **Suelo legible**: centro casi llano, cordillera fuera del radio jugable y cámara con holgura sobre el terreno para que ninguna elevación falsa oculte al personaje.

## Fase 4 — Meta, retention y guardado
| # | Feature | Detalle | Esf. | Estado |
|---|---------|---------|------|--------|
| 4.1 | **Tienda meta** | Pantalla de inicio con monedas, 5 mejoras permanentes y 3 personajes | M | ✅ |
| 4.2 | **Selección de personaje** | 3 personajes data-driven (`characters.json`) con stats distintos | S | ✅ |
| 4.3 | **Curses/dificultad** | 4 maldiciones data-driven: HP/spawn enemigo ↑ a cambio de +50 %…+200 % monedas | S | ✅ |
| 4.4 | **Logros y estadísticas** | Pantalla local con 7 logros data-driven y stats acumuladas | S | ✅ |
| 4.5 | **Guardado robusto** | `version: 3` + carga tolerante y **escritura atómica** (`tmp`+rename, `.bak`) | S | ✅ |
| 4.6 | **Cloud save (opcional)** | Google Play Juegos; marcado `_PURGADO_ hasta release` si el equipo es chico | M | ⬜ |

## Fase 5 — Hardening móvil (paralelo desde F1)
| # | Feature | Detalle | Esf. | Estado |
|---|---------|---------|------|--------|
| 5.1 | **Presupuestos por dispositivo** | RAM/GPU → balas (500/900/1500), enemigos (110/170/230), partículas 50/75/100 %, resolución 3D, props y sombras | M | ✅ |
| 5.2 | **Safe area / notch** | HUD y botones táctiles dentro de `DisplayServer.get_display_safe_area()` | S | ✅ |
| 5.3 | **Ciclo de vida (Android)** | Foco perdido → guarda, pausa y muestra menú; al volver NO reanuda sola. `NOTIFICATION_APPLICATION_PAUSED/RESUMED` + mute de música | S | ✅ |
| 5.4 | **Thermal / batería** | Opciones persistentes: FPS 30/60/120/∞, calidad Auto/Baja/Media/Alta (sombras, glow, resolución, props, cámara) + `OS_MEMORY_WARNING` | S | ✅ |
| 5.5 | **Botones táctiles,** todos jugables con 2 pulgares | Layout escala 5"/6.5"/tablet + safe area; hitboxes corregidas; `tools/check_layouts.sh` en CI. Falta verificación real en 3 tamaños | S | 🟡 |
| 5.6 | **Export** | **APK release firmada ✅** (SDK 36, icono, lanzador, 16 KB, keystore propio); `tools/build_android.sh` para recompilar; faltan AAB para Play y test en dispositivo real de cada tier | M | ⏳ |
| 5.7 | **Traducciones** | es/en primero (Grid `CSV` + `tr()`), preparada para fr/pt | S |
| 5.8 | **IAP/ads (opcional)** | monedas cosméticas o remove-ads; NO pay-to-win. Revisión de políticas al final | M |

## Fase 6 — Release
1. **Vertical slice jugable** (F1–F2.1 bis) en manos de 5 testers → ahora → medir retención.
2. **Softlaunch** (Play Store en 2–3 países) con F1–F5 → métricas de sesión y crashes.
3. **Global** con nube+logros+IAP opcional.

### Métricas de éxito antes de invertir más
- Retención día 1 > 35 % en softlaunch.
- Crashes ANR < 1 % de sesiones.
- Sesión media 8–12 min (una run completa 12–15 min) y 2+ sesiones/día.
