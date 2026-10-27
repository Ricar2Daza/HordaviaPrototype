# Apéndice A — Desglose de sistemas del juego de referencia (Megabonk)

> **Método y alcance.** Este apéndice combina dos fuentes:
> 1. **Evidencia estática REA** (inventario de binarios, Evidence ID
>    `ev_9c66099a9092fb6f00f4c0ea7fbeb2b86db7b5fadde7813970afee95ec0f8aff`):
>    datos *comprobados* del paquete de la versión 1.0.69.
> 2. **Inferencia de diseño**: descripción de *cómo* funciona cada sistema jugable,
>    derivada de la observación del juego. El pseudocódigo es **contenido original
>    propio** (no descompilado de `GameAssembly.dll`).
>
> El proyecto de referencia pertenece a Ved. Este apéndice no reproduce código,
> assets ni textos del juego; describe patrones de sistemas para implementarlos
> de cero en Godot. El snapshot REA-Ghidra de `GameAssembly.dll` no persistió
> (ver §A.10 si quieres regenerarlo y llevar esto a pseudocódigo más fino).

---

## A.1 Inventario técnico observado (evidencia)

| Marcador en el binario | Qué implica para el diseño |
|---|---|
| Unity **IL2CPP** + `global-metadata.dat` | Juego compilado AOT: sin hot-reload. En Godot usamos GDScript/JSON: iteración instantánea |
| **Addressables 1.21.20** + `level0`–`level4` | Streaming de contenido por bioma/nivel: cargar solo lo necesario |
| **MK.Toon** (assembly) | Pipeline de sombreado toon (bandas + outline). Coincide con la guía §3.7 |
| **Rewired** | Capa de input multi-dispositivo (teclado+gamepad). En móvil se reemplaza por joystick virtual de un pulgar + botones |
| **Steamworks.NET** + **Discord SDK** | Logros/social en PC. En móvil: Play Games Services (fase release), no bloqueante |
| **MelonLoader** + `Mods/`, `Plugins/` | Comunidad de mods en PC. No aplica a móvil; posible API de contenido en el futuro |
| **Newtonsoft.Json** | Contenido data-driven en JSON (armas, items, spawns). Corrobora la arquitectura JSON de la guía |
| **Coffee.UIParticle** | Partículas sobre elementos de HUD/UI (juice 2D barato) |
| 103 assemblies totales | Alcance de estudio mediano; nuestro MVP móvil no necesita más de ~15 módulos propios |

## A.2 Loop de partida

Estructura tipo "sobrevive X minutos": el mapa tiene techo de tiempo (p. ej. 20 min
por bioma) y un jefe final. No hay "oleadas discretas": es **presión continua**
con presupuesto creciente por ventanas de tiempo y picos programados.

```
# Pseudocódigo propio — reloj maestro de run
const RUN_LIMIT := 20 * 60
var run_time := 0.0

func _process(dt: float) -> void:
    if run_activa:
        run_time += dt
        if run_time < RUN_LIMIT:
            return
        trigger_encuentro_final()   # jefe o derrota
```

Estado en el prototipo: ✅ `GameState.run_time` + `WIN_TIME` (15 min en la demo).

## A.3 Spawn Director (hordas y eventos)

Responsable del *ritmo*: presupuesto de enemigos por segundo en ventanas de tiempo,
pools ponderados por tier, multiplicador de HP global y **eventos scriptados**
(círculos que envuelven al jugador, minijefes, hordas de un solo tipo).

```
# Pseudocódigo propio — director de hordas
func tick(dt: float) -> void:
    var tier := ventana_por_tiempo(run_time)          # tabla data-driven
    acumulador += tier.budget_por_seg * dt
    while acumulador >= 1.0:
        acumulador -= 1.0
        if enemigos_activos >= CAP:
            break                                      # el exceso no se acumula
        spawn(pool_ponderado(tier.pools), anillo_alrededor_jugador(), tier.hp_mult)
    for ev in tier.eventos:
        if run_time >= ev.t and not ejecutado.has(ev):
            ejecutado[ev] = true
            ejecutar(ev)                               # "círculo de 40 murciélagos r=20"
```

Claves de calidad:
- Spawns **fuera de cámara** (anillo r≈18–26 m; aparecen detrás del jugador o fuera
  del frustum) — nunca a la vista.
- **CAP duro** de enemigos activos: presupuesto de CPU/GPU. El género vive de
  enjambres densos, no de miles de entidades dibujables.
- HP multiplicado por ventana: los mismos 3–4 prefabs escalan todo el mapa.

Estado en el prototipo: ✅ `SpawnDirector` + `spawn_table.json`.

## A.4 Armas automáticas data-driven

Cada arma es un **emisor** con: patrón, cadencia, daño, proyectiles, nivel (VIII)
y una receta de evolución (arma a nivel máximo + pasiva específica → arma evolucionada).
Arquetipos estándar del género:

| Arquetipo | Comportamiento |
|---|---|
| `aimed` | Dispara al enemigo más cercano con predicción de tiro |
| `orbit` | Cuchillas que orbitan el cuerpo (daño por solape, cooldown por enemigo) |
| `aura` | Anillo de daño continuo alrededor del jugador |
| `boomerang` | Proyectil que sale y regresa; golpea de ida y de vuelta |
| `mine` | Cargas estáticas que explotan por proximidad |
| `chain` | Rayo que salta de enemigo en enemigo |

```
# Pseudocódigo propio — evolución de armas
recetas := {
    "baston":  { "max": 8, "pasiva": "agilidad", "evolucion": "Baston_Optico" },
    "cuchillas": { "max": 8, "pasiva": "area",   "evolucion": "Cuchillas_Torbellino" },
}

func desbloquear_evolucion(arma) -> void:
    if arma.nivel == recetas[arma.id].max and pasivas.tiene(recetas[arma.id].pasiva):
        ofrecer_carta(recetas[arma.id].evolucion)      # reemplaza al arma base
```

Estado en el prototipo: ✅ `aimed` (`wand`) y `orbit`; `weapons.json`.
Pendientes: `aura`, `boomerang`, `mine`, `chain`, evoluciones → ver FEATURES.

## A.5 Stats, pasivas y level-up

- **Level-up**: gemas de XP → umbral → pantalla que ofrece 3–4 cartas
  (arma nueva / mejora de arma / pasiva). Herramientas del jugador:
  **reroll** (re-sorteo, consumible), **banish** (excluye una opción por run)
  y **skip** (saltar a cambio de monedas).
- **Pasivas** stackean con tope: daño%, cadencia%, velocidad, área, proyectiles extra,
  **luck** (peso del sorteo de cartas), imán, vida máxima, regeneración.
- Los multiplicadores se aplican **multiplicativamente** entre pasivas distintas y
  de forma aditiva entre copias de la misma pasiva.

```
# Pseudocódigo propio — composición de daño
dmg_final := arma.dmg_base * (1.0 + pasiva_daño.nivel * 0.10)
dmg_final *= (1.0 + bonus_sinergia_si_aplica)          # opcional, consistente
```

Estado prototipo: ✅ cartas con rareza ponderada; ⬜ reroll/banish/skip, luck, evoluciones, pasiva de regeneración.

## A.6 Mundo, biomas y cámara

- **Arena con alturas/plataformas**: el movimiento no es plano (saltos, escalones).
  La horda camina sobre el suelo y el jugador puede "kitar" verticalmente;
  caer del mapa castiga fuerte (daño o muerte): eso mantiene la tensión de ruta.
- **Biomas** (bosque / cuevas / desierto…) con: paleta y set dressing propio,
  tabla de spawns distinta, jefe final y hazards (charcos de lava, nieve lenta, vortex).
- **Cámara**: tercera persona aérea diagonal con pitch fijo, sigue con lerp + shake
  al recibir daño; el jugador se orienta respecto de la cámara.
- En PC el streaming es por Addressables; en Godot: **un `.tscn` + assets por bioma**
  y `ResourceLoader.load_threaded_request()` para precargar el siguiente bioma.

Estado prototipo: ✅ cámara + arena plana; ⬜ saltos/alturas, biomas, hazards.

## A.7 Jefes y élites

- **Élites**: enemigos normales con HP×N, aura visible y drop garantizado (cofre).
- **Jefe**: HP grande, fases con patrones telegráficos (barrido, invocar hordas,
  embestida), barra de vida con nombre; su loot: gema grande + monedas.
- El jefe **no** pausa el presupuesto de hordas: presión dual (enjambre + jefe).
  Por eso sus patrones deben esquivarse por **espacio y timing**, no por reflejo puro.

## A.8 Meta progresión y guardado

- **Monedas** por run → tienda meta: desbloquear personajes, mejoras permanentes
  (+HP inicial, +daño inicial, luck base…), cosméticos.
- **Save** local + registro (mejor tiempo, logros). En PC Steam Cloud;
  en móvil: `user://` → luego Google Play Juegos (guardado en la nube, fase release).
- **Curses/dificultad** opcionales para veteranos (más HP de horda, menos tiempo
  útil de run) a cambio de más monedas — retención para el skill ceiling.

Estado prototipo: ✅ monedas + mejor tiempo (`SaveManager`); ⬜ tienda, personajes, curses, nube.

## A.9 Juice y feedback

- Números de daño flotantes billboarding, hit flash del enemigo, hitstop muy corto,
  shake de cámara al recibir daño, partículas de muerte (cubos voxel estilizados),
  viñeta al recibir daño, audio diferenciado por hit/crit/pickup.
- Barato de imitar en Godot: `GPUParticles3D` + pool; y en HUD `GPUParticles2D`
  (equivalente funcional de Coffee.UIParticle).

Estado prototipo: ✅ hit flash + bob de enemigos; ⬜ números, partículas, sonido, shake, hitstop.

## A.10 Regenerar el análisis REA-Ghidra (opcional, PC)

El snapshot del DLL no persistió en la sesión (el `analyze.json` quedó vacío y se
relanzó en background). Si quieres regenerarlo manualmente (tarda 30–90+ min):

```powershell
cd C:\Users\Usuario\Downloads\Megabonk.v1.0.69-0xdeadcode
$env:GHIDRA_INSTALL_DIR = 'C:\Users\Usuario\Tools\ghidra_12.1.4_PUBLIC'
$env:JAVA_HOME          = 'C:\Users\Usuario\Tools\jdk-21'
$env:REA_GHIDRA_STARTUP_TIMEOUT_MS = '14400000'
npx -y rea-agents@6.7.0 analyze GameAssembly.dll --provider ghidra `
    --snapshot rea-analysis\GameAssembly.snapshot --format json `
    1> rea-analysis\GameAssembly.analyze.json 2> rea-analysis\analyze.stderr.txt
```

Si culmina: `rea-analysis\GameAssembly.snapshot` + `GameAssembly.analyze.json`
contendrán pseudocódigo por función (gestión de daño, director, armas). Eso permitiría
sustituir la inferencia de §A.3–A.5 por pseudocódigo de la implementación real.
