# HordaviaPrototype — prototipo Godot (v0)

Prototipo jugable del concepto **roguelike bullet-heaven 3D móvil** de la guía
`Guia_Roguelike_BulletHeaven_Godot_Movil.md` (basada en análisis REA de Megabonk).

📚 **Toda la documentación ahora vive en [`docs/00_INDICE.md`](docs/00_INDICE.md):**
guía maestra, apéndice de sistemas, roadmap de features, celulares objetivo y guía de assets.

## Cómo ejecutarlo

1. Descarga **Godot 4.7.2** (editor estándar, no .NET): https://godotengine.org/download
   El proyecto se abrió por última vez con 4.7.2; `project.godot` declara features `4.7`.
2. `Importar` → selecciona `HordaviaPrototype/project.godot`
3. Play ▶ (o F5). En escritorio el touch se emula con el ratón (`emulate_touch_from_mouse`),
   y hay fallback de **WASD** para iterar rápido.
4. **Android**: instala `build/Hordavia.apk` en un teléfono ARM64.
   Guía completa en [`docs/05_EXPORT_ANDROID.md`](docs/05_EXPORT_ANDROID.md).
   Para recompilar el APK con el código actual: `bash tools/build_android.sh`.

## Android (APKs en `build/`)

- `build/Hordavia.apk`: plantilla **release** (25.5 MiB), firmada con keystore propio
  (`CN=Hordavia`), lista para instalar y medir FPS reales.
- `build/Hordavia-debug.apk`: plantilla debug (27.2 MiB), para logcat y depuración.
- Ambos: `arm64-v8a`, Android 7+, target SDK 36, paquete `com.hordavia.prototype`,
  label **Hordavia**, icono original `assets/icon.png` y lanzador visible en el teléfono.
- Keystore y credenciales fuera del repo: `C:\Users\Usuario\Tools\hordavia-release.keystore`
  y `...\hordavia-release-keystore.txt` (haz backup; sin ellos no hay actualizaciones).
- SDK en `C:\Users\Usuario\Tools\android-sdk` y JDK 21 en `...\Tools\jdk-21` (ver la guía).
- El **GSI Android 17** no se usa para compilar: es una imagen de sistema para un teléfono
  ARM64 con bootloader desbloqueado. Instrucciones de flasheo e instalación en la guía.
- Falta probarlo en hardware real: al compilar no había ningún dispositivo conectado.
- **Los APK de `build/` son del 26/10** y no incluyen el layout táctil responsive ni
  los hápticos de este cambio. Recompila con `bash tools/build_android.sh` (debug) o
  `bash tools/build_android.sh --release` (release con keystore).
- AAB para Play sigue pendiente (bloque 5.6 del roadmap).

## Qué contiene (fase 0 + parte de fase 1 de la guía)

| Sistema (guía) | Estado en el prototipo |
|---|---|
| §3.1 Joystick de un pulgar | ✅ flotante, deadzone y knob; escala 5"/6.5"/tablet + safe area |
| §3.2 MultiMesh bullets | ✅ cap 1500, grilla espacial para impactos |
| §3.3 Spawn Director JSON | ✅ budget/seg por minuto + eventos de círculo |
| §3.4 Armas data-driven | ✅ 8 armas base + niveles I–VIII + 8 evoluciones |
| §3.5 XP + tarjetas de level-up | ✅ rareza ponderada + reroll/desterrar/saltar + pasiva suerte |
| §3.6 Guardado FileAccess | ✅ monedas, meta, personaje, stats/logros y settings (v3) |
| §3.7 Shader toon | ✅ 3 bandas + rim |
| Hápticos móviles | ✅ daño/dash/salto/jefe/level-up/game over + toggle persistente |
| Game over/restart | ✅ (+ menú de pausa ESC/☰ con cámara/reiniciar/menú/salir) |
| Boss con IA propia | ✅ 3 jefes (carga, slam rápido, slam pesado) que reaparecen cada ciclo |
| Mapa procedural | ✅ heightfield por run + cofres + relieve seguido por entidades |
| Hazards ambientales | ✅ lava (DoT) y niebla (slow) por bioma |
| Pickups de mapa | ✅ cura / imán / bomba + cofre por élite |
| Supervivencia sin fin | ✅ biomas en bucle + HP/daño/spawn escalando por minuto y ciclo |
| Presupuestos por dispositivo | ✅ RAM/GPU → balas, enemigos y partículas (Fase 5.1) |

## Rendimiento medible

- `BulletSwarm.active_count()` / `EnemyManager.active_count()` exponen el budget en vivo.
- Consola Godot: `_monitor_stats` rápido o usar el profiler del editor.
- Gama baja: baja `cap` en `spawn_table.json` y `MAX_BULLETS` en `bullet_swarm.gd`.

## Desviaciones deliberadas del guide

- El prototipo usa `Node3D` para jugador/enemigos (sin `CharacterBody3D`): la altura sigue
  al terreno y el dash/salto se resuelven con cinemática propia — menos coste de física a 30 Hz.
- Los bucles de daño usan una **grilla hashmap de celdas 2×2 m** (guía §3.2 opción a).

## Notas de balance rápido

- **Sin fin**: la run solo termina al morir. Cada bioma dura 6 min; los 7 biomas
  (`data/biomes.json`) completan un ciclo de 42 min, tras el cual vuelven en orden.
  La presión sube: HP ×(1 + 0.16·min + 0.06·min^1.5), daño ×(1 + 0.045·min),
  spawn ×(1 + 0.22·ciclo + 0.012·min).
- Curva XP: `5 + 6*lvl^1.6` (en `game_state.gd`).
- Subida de dificultad: editar `tiers` en `data/biomes.json`.
- Élites: cada 90 s suelta 1 prefab del tier con HP×8 y orbe×4 (`spawn_director.gd`).
- Enemigos: `goblin`, `bat`, `brute`, `wisp` (veloz), `bomber` (explota al morir),
  `shaman` (invoca murciélagos) + jefes. Los tiers altos los mezclan.

## Controles (Fase 1 integrada)

| Entrada | Acción |
|---|---|
| Arrastrar / WASD / flechas | Movimiento (joystick flotante, **relativo a cámara**) |
| Stick izquierdo / cruceta (mando) | Movimiento analógico |
| Botón **DASH** (derecha-abajo) / Shift* / **B** | Dash 0.22 s + i-frames, cooldown 3 s |
| Botón **SALTO** (derecha-arriba) / Espacio / **A** | Salto (con coyote 0.12 s) |
| **C** / **Y** | Alternar cámara: Fija ⇄ Mouse |
| **ESC** / **Start** / botón **☰ MENÚ** | Menú de pausa en cualquier pantalla (continuar / cámara / reiniciar / menú / salir) |
| Clic izquierdo (modo mouse) | Captura el mouse para orbitar la cámara |
| Stick derecho / **Q-E** (modo mouse) | Orbitar la cámara |
| Clic en cartas | Elegir mejora al subir de nivel |

*Dash/salto por teclado y mando se detectan por borde de pulsación (una pulsación = una acción).
En móvil el pulgar derecho maneja DASH/SALTO (botones táctiles); el modo cámara
"Mouse" es la variante de escritorio. El modo **Fija** es el equilibrio para móvil.
Todas las entradas pasan por `core/input_setup.gd` (InputMap), así que añadir un
mando o remapear teclas no requiere tocar la lógica del jugador.

## Juice activo tras la Fase 1

- Números de daño flotantes billboarding (pool 40, recicla el más antiguo).
- Explosión voxel al morir enemigos (pool 24 CPUParticles3D, color por tipo, x2 en élite).
- Élites cada 90 s: escala 1.5×, HP×8, orbe de XP×4.
- Shake de cámara al recibir daño + viñeta roja (flash por golpe y pulso con HP<30%).
- Squash & stretch del jugador al aterrizar.

## Mapa procedural + cofres (roadmap 1.2)

- `world/terrain.gd` genera un **heightfield por run** (FastNoiseLite semilla
  aleatoria, cuantizado en escalones de 0.5 m, acantilado en el borde) y lo pinta
  con **1 sola draw call** (MultiMesh de columnas). Player, enemigos y orbes
  siguen el relieve con `height_at(x, z)`.
- **Cofres**: cada cambio de bioma suelta 2-3 cofres dorados girando en el mapa.
  Al tocarlos: 3 cartas (o +20 monedas si otra UI está abierta).

## Fase 3.4 — jefes por bioma (7/7), sin fin

Cada bioma define su jefe y el segundo de aparición local en `data/biomes.json`; las
estadísticas y el patrón se leen de `data/enemies.json`.

| Jefe | Bioma (aparición local) | Patrón | Invoca |
|---|---|---|---|
| **Guardián de Niebla** | Bosque, 150 s | Carga telegrafiada | 10 murciélagos |
| **Reina de las Profundidades** | Cuevas, 120 s | Slam de área | 12 murciélagos |
| **Coloso de Dunas** | Dunas, 90 s | Slam de área | 8 goblins |
| **Madre de Esporas** | Pantano, 150 s | Slam de área | 14 fuegos fatuos |
| **Titán de Escarcha** | Tundra, 150 s | Carga telegrafiada | 10 brutos |
| **Devorador de Magma** | Volcán, 150 s | Slam de área | 12 bombarderos |
| **Heraldo del Eclipse** | Ruinas, 150 s | Carga telegrafiada | 12 acechadores |

Todos muestran su barra de vida, aparecen a 9 m del jugador y su ataque ignora los
iframes de contacto. Al derrotarlos, la run continúa: dan 60 monedas (150 el Coloso),
curan hasta 30 % de la vida máxima y ofrecen cartas de cofre. Reaparecen en el ciclo
siguiente con la escala global de vida y daño.

## Fase 3.1 — biomas data-driven

Cada bioma ocupa 6 minutos del ciclo de 42 minutos (`data/biomes.json`):

| Bioma (minuto del ciclo) | Hazard | Clima | Jefe |
|---|---|---|---|
| **Bosque de Niebla** (0–6) | Niebla lenta | Niebla baja | Guardián de Niebla |
| **Cuevas Profundas** (6–12) | Lava | Brasas subterráneas | Reina de las Profundidades |
| **Dunas Ardientes** (12–18) | Lava | Tormenta de arena | Coloso de Dunas |
| **Pantano de Esporas** (18–24) | Veneno | Lluvia ácida | Madre de Esporas |
| **Tundra Quebrada** (24–30) | Hielo | Ventisca | Titán de Escarcha |
| **Corazón de Ceniza** (30–36) | Lava | Lluvia de ceniza | Devorador de Magma |
| **Ruinas del Eclipse** (36–42) | Niebla lenta | Tormenta del eclipse | Heraldo del Eclipse |

Cada bioma trae sus tiers, eventos de horda, props y hazards; el HUD anuncia los cambios
y el mundo actualiza la paleta, la luz y el suelo. La dificultad se escala por tiempo
y por ciclo.

## Fase 2.5 — Pasivas restantes

| Carta | Efecto | Máx |
|---|---|---|
| Savia viva (`regen_1`) | +0.6 HP/s (emite `hp_changed` 2 veces/s) | 5 |
| Onda expansiva (`area_1`) | +12 % radio de aura, órbitas, minas y saltos de cadena | 5 |
| Corteza mineral (`armor_1`) | −8 % daño recibido (tope 60 %) | 5 |
| Ojo de tormenta (`crit_1`) | +8 % crítico (×2 daño, número flotante resaltado) | 5 |
| Sed de niebla (`lifesteal_1`) | +0.25 HP por baja | 4 |
| Diente de oro (`greed_1`) | +25 % monedas | 4 |

## Fase 5.1 — presupuestos por dispositivo

`GameState._detect_device()` lee `OS.get_memory_info()` y
`RenderingServer.get_video_adapter_name()` al arrancar y fija:

| Tier | RAM/GPU | Balas | Enemigos | Partículas FX |
|---|---|---|---|---|
| **bajo** | móvil o <3.2 GB | 500 | 110 | 50 % |
| **medio** | <6.5 GB o GPU integrada | 900 | 170 | 75 % |
| **alto** | resto | 1500 | 230 | 100 % |

Calidad añadida en la misma pasada (`GameState.shadows/render_scale/prop_mult/camera_far`):
bajo 0.72× resolución 3D, props 45 %, sin sombras, cámara 70 m; medio 0.9×, props 75 %,
sin sombras; alto 1.0×, props 100 %, sombras 2048 y glow. Se aplica en `main._apply_quality`
y al reconstruir props. **Safe area/notch (5.2):** HUD y botones DASH/SALTO se desplazan
con `DisplayServer.get_display_safe_area()` y se recalculan al cambiar de tamaño.

**Ciclo de vida (5.3):** al perder foco (`APPLICATION_FOCUS_OUT` / `WM_WINDOW_FOCUS_OUT`,
también `APPLICATION_PAUSED` en Android) se guarda la partida, se silencia la música,
se pausa el árbol y se abre el menú. Al recuperar el foco **no se reanuda automáticamente**:
el jugador pulsa Continuar. Si había cartas/nivel o game over, se mantiene esa pantalla
pausada. Además `NOTIFICATION_OS_MEMORY_WARNING` reduce en caliente balas (500),
enemigos (100) y partículas (50 %).

**Opciones de rendimiento (5.4):** en el menú inicial, junto a las monedas, hay dos
botones persistentes (`settings` en `save.json`):
- **FPS**: 30 → 60 → 120 → ∞ (`Engine.max_fps`).
- **Calidad**: Auto → Baja → Media → Alta. Auto usa el tier detectado; las otras
  fuerzan presupuestos, sombras, glow, resolución 3D, props y distancia de cámara.
  Se aplica en caliente (`main.apply_quality_live`, reconstruye props del bioma).

Se aplica a `BulletSwarm.spawn`, al `cap` del `SpawnDirector` y al pool/cantidad de
`DeathFx`; se imprime `DEVICE tier=… bullets=… enemies=… fx=…` en consola.

## Fase 4.1 / 4.2 — pantalla de inicio, tienda meta y personajes

Al abrir el juego aparece el **menú de inicio** (árbol pausado):

- **3 personajes** (`data/characters.json`): Vagabundo (100 HP, balanced), Corredor
  (75 HP, +20 % velocidad, +10 % cadencia), Coloso (140 HP, +15 % daño, más lento).
- **5 mejoras permanentes** (`data/meta.json`, se pagan con monedas totales):
  Corazón de hierro (+8 HP/nivel), Filo ancestral (+5 % daño), Botas ligeras
  (+0.15 velocidad), Brújula de niebla (+0.6 imán), Bolsa de fortuna (+10 % monedas).
  Coste = base + step × nivel; máximo 3–5 niveles.
- Persistencia en `save.json` (`version: 3`, `meta`, `character`).
- **4 maldiciones** (`data/curses.json`): Sin maldición · Sangre espesa (+20 % HP → +50 % monedas) · Marea imparable (+35 % HP, +30 % spawn → +100 % monedas) · Furia del coloso (+60 % HP, +50 % spawn → +200 % monedas). La elección se guarda en `settings.curse`.
- Al morir: «Jugar otra vez» reinicia directo; «Volver al menú» permite gastar monedas.

**Logros y estadísticas (4.4):** botón «LOGROS Y ESTADÍSTICAS» en el menú. Guarda bajas
totales, jefes, victorias, monedas ganadas y mejor tiempo; 7 logros data-driven
(`data/achievements.json`) que se desbloquean al terminar la run y avisan con banner.
El save sube a `version: 3` (campos nuevos con valores por defecto = migración tolerante).
La escritura es **atómica** (`save.json.tmp` → rename) y conserva `save.json.bak` del
último save válido; un cierre forzado ya no puede dejar el JSON a ceros.

## Fase 2.7 — pickups y cofre de élite

`world/pickups.gd` (cápsula/cubo/esfera, viven 25 s):

| Pickup | Efecto |
|---|---|
| **Cura** (verde) | +25 HP |
| **Imán** (azul) | +20 radio de atracción durante 6 s |
| **Bomba** (naranja) | 80 de daño a **todos** los enemigos vivos |

Drops: 2 % por baja normal; **élite → cofre en su posición** (3 cartas). El imán temporal
se suma en `XPManager` (`magnet + magnet_bonus`) y se limpia solo al expirar.

## Fase 3.2 — transición de bioma (fade + portal)

Al cambiar de bioma el HUD funde a negro 0.9 s (pico 0.55 de alfa) mientras aparece el
banner, y en el suelo del jugador se abre un **anillo de portal** (torus cian) que escala
y se desvanece en 1.1 s. Todo ocurre en la misma escena (sin recarga), así que no hace
falta `ResourceLoader` threaded.

## Fase 3.3 — Hazards ambientales

`world/hazards.gd` genera 4–6 zonas por bioma según `data/biomes.json`
(`"hazard": "slow"|"lava"`, `"hazard_count"`): **niebla densa** (×0.55 velocidad) en el
Bosque y **charcos de lava** (9 HP/s, ignora el grace de contacto) en Cuevas y Dunas.
Se regeneran en cada cambio de bioma; el daño aplica armadura.

## Fase 2.3 — consumibles de cartas (reroll / desterrar / saltar)

En la pantalla de level-up/cofre hay un pie con:

- **Reroll (1 por run)**: vuelve a tirar las 3 cartas.
- **Desterrar (1 por run)**, botón bajo cada carta: elimina esa carta del pool
  **durante toda la run** (`GameState.banished`), sin cerrar el overlay.
- **Saltar (+15 XP)**: cierra el overlay y convierte la elección en experiencia.

## Fase 2.4 — Pasiva de suerte

`Trébol de niebla` (raro, hasta 5 stacks, `luck_1`): cada stack multiplica ×1.3 el peso
de las cartas **no comunes**, así que sube la probabilidad de raras/épicas/legendarias
(incluidas las evoluciones). El peso se calcula en `ContentDB._eff_weight()`.

## Fase 2.2 — Evoluciones de armas (+ niveles I–VIII)

Cada arma sube de nivel con cartas **"Mejorar arma X"** (+12 % daño, +6 % cadencia
por nivel; tope VIII). Al llegar a **nivel 8** y tener la pasiva requerida al nivel
indicado, aparece una carta **legendaria de EVOLUCIÓN** (garantizada en el sorteo):

| Receta | Resultado | Cambio |
|---|---|---|
| Bastón de niebla L8 + Filo afilado III | **Railgun de niebla** | Bala perforante (hasta 3 enemigos), daño 30 |
| Nimbo escaldante L8 + Sigilo magnético II | **Supernova** | Anillo r=5.2 incandescente, daño 10 cada 0.35 s |
| Disco errante L8 + Gatillo ligero III | **Tempestad de discos** | 2 discos por lanzamiento, daño 18, alcance 11 |
| Mazo sísmico L8 + Onda expansiva II | **Rompecielos** | Onda sísmica de gran radio |
| Meteoro rúnico L8 + Viento de cola II | **Caída estelar** | 3 meteoros por lanzamiento |
| Dron de niebla L8 + Gatillo ligero III | **Enjambre de guerra** | 3 drones de combate |
| Vacío devorador L8 + Siega II | **Sol Negro** | Singularidad de mayor radio y duración |
| Cadencia de tormenta L8 + Ojo de tormenta II | **Tormenta encadenada** | Rayo de 6 saltos |

Hay 8 recetas en `data/evolutions.json` (100 % data-driven). Al evolucionar, el arma base
**desaparece** y el nodo se reconstruye en caliente (`weapons` → `upgrades_changed`).

## Fase 2.1 — arsenal (8 armas base, todas data-driven)

| Carta de desbloqueo | Arma | Qué hace |
|---|---|---|
| (inicial) | Bastón (`nearest`) | Auto-aim al más cercano con predicción de tiro |
| Cuchillas meridianas | `orbit` | Cuchillas que orbitan el cuerpo |
| Nimbo escaldante | `aura` | Anillo púrpura de daño continuo (pulsante) |
| Disco errante | `boomerang` | Disco que sale y vuelve, daña ida y vuelta |
| Sembrador de minas | `mine` | 3 minas máx, arman a 0.45 s, explotan por proximidad |
| Cadencia de tormenta | `chain` | Relámpago con 3 saltos entre enemigos (épica) |
| Espiral de esquirlas | `spiral` | Abanico giratorio de 3 proyectiles que cubre 360° |
| Escarcha rúnica | `frost` | Anillo helado que daña y ralentiza (×0.55 durante 1.2 s) |

Armas **evolucionadas** (solo vía receta 2.2): `railgun`, `supernova`, `disc_tempest`,
`earthbreaker`, `starfall`, `war_swarm`, `black_sun` y `thunderstorm`.

## Audio (100 % procedural, cero assets)

`AudioManager` sintetiza SFX (shoot/hit/pickup/jump/dash/boom/zap/levelup/gameover)
y un loop de música (progresión Am–F–C–G con bajo/arpegio/batería) **en código al
arrancar** — licencias limpias por diseño. Buses SFX y Music ya separados para
opciones de volumen futuras.

## QA automático (CI + validador de contenido)

`.github/workflows/ci.yml` corre en cada push/PR:

1. Descarga Godot `4.7-stable`.
2. Importa el proyecto (`--headless --import`).
3. Valida los JSON con `tools/validate_content.gd` (referencias de armas,
   evoluciones, biomas, jefes, pools, personajes, maldiciones y logros).
4. Comprueba el layout táctil en 5", 6.5" y tablet con `tools/check_layouts.sh`
   (sin display, simulando el viewport).
5. Ejecuta el smoke de 75 s y exige `SMOKE_RESULT` en el log.

Local:

```
Godot_v4.7-stable_linux.x86_64 --headless --path . --script res://tools/validate_content.gd
```

Para abrir una pestaña del hub directamente en QA (por ejemplo, la nueva tarjeta
Móvil): `HORDAVIA_OPEN_TAB=ajustes ./Godot_v4.7-stable_linux.x86_64 --path .`.

El validador sale con código 1 y lista `CONTENT_ERROR …` si algo quedó mal
referenciado. `.godot/` y el binario del engine están en `.gitignore`; el CI
siempre parte de un import limpio.

## Modo smoke (QA headless)

Para validar el build sin abrir el editor (lo que hace el pipeline de CI):

```
set HORDAVIA_SMOKE=1
Godot_console.exe --headless --path HordaviaPrototype
```

El jugador bot kitea 75 s, aplica mejoras automáticamente y sale con un resumen
Checkpoints: personaje/meta/maldición al arrancar
(`SMOKE_META char=… curse=…`), biomas a los 25 s/50 s, evolución
forzada a los 30 s (`SMOKE_EVOLVE result=railgun ok=true`), armas y stats nuevas
a los 40 s (`SMOKE_POWERS spiral=true frost=true`, enemigos `bomber`/`shaman`/`wisp`),
destierro a los 15 s (`SMOKE_BANISH ok=true`), pasivas nuevas a los 10 s, pickups a los 20 s
(`SMOKE_PICKUP kind=heal|magnet|bomb`), hazards por bioma (`SMOKE_HAZARDS zones=…`)
y **los 3 jefes a los 12 s locales de cada bioma**
(`SMOKE_BOSS spawn` → `SMOKE_BOSS killed kind=… final=…`). A los 70 s prueba
`SMOKE_DISPLAY fps=30 quality=bajo …` (opciones en caliente) y al cerrar simula
pérdida de foco (`SMOKE_LIFECYCLE paused=true menu=true`). Como es sin fin, la corrida
termina a los 75 s, no al matar al Coloso.

Validado en Godot 4.7.2 (26/10/2026): 0 errores de script; smoke de 75 s con 920 bajas,
nivel 12 y 3 jefes muertos, y la partida siguió (sin victoria). Guardado atómico
verificado con `HORDAVIA_SAVE_TEST=1` (`write=true bak=true clean=true`).
El APK Android debug se compiló y firmó con el mismo código.

> **No cierres el pipe de stdout** (`| Select-Object -First N`): Godot bloquea el print y
> el run se congela. Redirige a archivo y filtra después.

## Tres bugs que el smoke ya revendió (por si los reintroduces)

1. **Tunneling de balas**: la bala avanza 0.6 m entre ticks de física (30 Hz) y puede
   atravesar un enemigo de radio combinado < 0.7 m. Solución: barrido por segmento
   (posición previa→actual) en `EnemyManager.hit_sweep`.
2. **Doble conteo de kills**: los enemigos muertos permanecían en `_active`; al
   reciclar del pool la misma referencia se apilaba dos veces. Solución: eliminar
   de `_active` en `_kill` y protejer con guardia `if not e.visible`.
3. **Congelación al pisar un cofre en headless**: el cofre emitía `leveled`, el HUD abría
   la carta y pausaba el árbol sin input posible. Solución: en modo smoke la carta se
   aplica sola (`debug_auto_upgrade`) tanto en `GameState.offer_chest_cards()` como en
   `HUD._on_leveled()`.

