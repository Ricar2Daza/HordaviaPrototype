# Guía de Desarrollo — Roguelike "Bullet Heaven" 3D en Godot para Móviles

> **Propuesta nueva**: un roguelike survival 3D estilo *bullet heaven* (género inaugurado por Vampire Survivors y llevado al 3D con Megabonk), **100% original**, diseñado desde cero con **Godot 4.x** para **Android e iOS**.
>
> Esta guía se basa en **evidencia real obtenida con REA** (análisis estático de la build PC de Megabonk v1.0.69, carpeta local) y la traduce en decisiones concretas de diseño y arquitectura en Godot.

---

## 0. Base de evidencia (REA)

Análisis REA sobre `Megabonk.v1.0.69-0xdeadcode` (Evidence ID `ev_9c66099a9092fb6f00f4c0ea7fbeb2b86db7b5fadde7813970afee95ec0f8aff`):

| Hecho observado | Fuente (archivo observado) | Implicación para nuestro juego |
|---|---|---|
| Desarrollador "Ved", título "Megabonk" | `Megabonk_Data/app.info` | Referencia, no copiar branding |
| Motor Unity con **IL2CPP** (`global-metadata.dat` presente; lógica en `GameAssembly.dll`, 54 MB, SHA-256 `4350a7ae25ba…`) | `Megabonk_Data/il2cpp_data/Metadata/` | En Godot-Android el equivalente es export AAB con GDScript compilado; rendimiento nativo no es requisito |
| Carga de contenido vía **Addressables 1.21.20** | `StreamingAssets/aa/settings.json`, `catalog.json` (238 KB) | En Godot: **PCKs + `ResourceLoader`** para mods/DLC |
| 5 escenas/variantes de nivel | `level0`–`level4` en `Megabonk_Data/` | Plan de mapas: bien un mundo grande por shards, o arenas por bioma |
| Look cartoon/toon con **MK.Toon** + partículas en UI (**Coffee.UIParticle**) | `ScriptingAssemblies.json` (103 assemblies) | En Godot: shader toon propio + partículas ancladas a nodos de interfaz (`Control`) |
| Input profesional con **Rewired** (PC) | `ScriptingAssemblies.json` | En móvil: joystick virtual propio + gamepad opcional |
| **Steamworks.NET** + **Discord** Rich Presence | `ScriptingAssemblies.json` | En móvil: Google Play Games / Game Center + achievements |
| **MelonLoader** instalado (cadena de mods .NET 6) | carpeta `MelonLoader/` (deps json observados) | El mercado de mods importa: diseñar API de mods desde el día 1 |
| Física 3D estándar (Unity Physics) + plataformas/objetos respawnables | módulos Unity en `ScriptingAssemblies.json` | Godot: `CharacterBody3D` + pools |

> ⚠️ **Nota legal**: todo lo observado se usa como *referencia técnica y de diseño*. El nombre "Megabonk", sus assets, audio, personajes y arte pertenecen a Ved. Nuestra propuesta usa **assets y nombres originales** — mecánicas de juego no son protegibles, la expresión sí.

---

## 1. Concepto de la nueva propuesta (mobile-first)

**Título provisional**: *Hordavia* (nombre placeholder, elige el tuyo final).

| Pilar PC (Megabonk) | Adaptación móvil |
|---|---|
| Runs de ~15–30 min | **Runs de 8–15 min** (+ modo "quickie" de 5 min para jugar en el bus) |
| WASD + ratón + salto | Joystick virtual de un pulgar; el segundo queda libre para dash y salto |
| Hordas masivas 3D horizontales | Hordas masivas pero con **budget escalado por hardware** (escala 0.75× en gama baja) |
| Upgrades nivel 1–50 XP | Igual, con **elección en arco** (tarjetas grandes táctiles) |
| Steam leaderboards | **Google Play Games / Game Center** + leaderboard diario sin conexión |
| Mods (MelonLoader) | **PCK mods** + API JSON/data-driven |

**Loop core explotable en 60 s**: moverse → orbes de XP → levelear → elegir 1 de 3 upgrades → armas disparan solas → sobrevivir oleadas + boss a los N minutos → muerte/victoria → meta-progresión (monedas, unlocks) → siguiente run.

---

## 2. Setup del proyecto en Godot 4.x

**Versión**: Godot 4.4+ (stable). **Lenguaje**: GDScript (arranque rápido, 100% soportado; C# opcional solo si el equipo ya domina .NET).

### 2.1 Project Settings críticas (mobile)

```ini
# project.godot (resumen)
[rendering]
renderer/rendering_method="mobile"           # renderer Vulkan Mobile (o gl_compatibility para gama ultra-baja)
textures/vram_compression/import_etc2_astc=true
anti_aliasing/quality/msaa_3d=0              # nada de MSAA en móvil

[display]
window/stretch/mode="canvas_items"           # así el HUD no se distorsiona en proporciones raras
window/stretch/aspect="expand"
window/handheld/orientation=1                # landscape
window/size/viewport_width=1280
window/size/viewport_height=720

[physics]
common/physics_ticks_per_second=30           # 30 Hz de física basta y ahorra batería; lógica de armas en _process

[audio]
driver/output_latency=30                     # menos crackeo en gama baja
```

- Formato de texturas: **ASTC** (Android moderno) + ETC2 fallback.
- Cámara 3D con **FOV ~60–65** y campos bajos en detalle.
- Sombra: **una sola DirectionalLight3D con sombra** o sombras bakeadas; nada de OmniLight con sombra en masa.

### 2.2 Estructura de carpetas

```
res://
  core/          # autoloads: GameState, RunDirector, SaveManager, AudioManager
  data/          # recursos .tres/.json: weapons.tres, enemies.json, upgrades.json
  player/        # Player.tscn, JoystickVirtual.tscn, DashGesture...
  weapons/       # una escena por arma + su lógica data-driven
  enemies/       # prefabs de enemigos + spawner
  world/         # arenas/biomas, coleccionables, props
  ui/            # HUD, LevelUpCards, menus, pause
  fx/            # shaders toon, GPU particles, trails
  mods/          # PCK loader (产能 futuro)
```

**Autoloads** (singletons): `GameState` (run actual), `ContentDB` (tablas data-driven), `SaveManager`, `PoolManager` (object pooling global).

---

## 3. Los 7 sistemas core

### 3.1 Movimiento táctil (1 dedo)

Joystick virtual flotante (aparece donde tocas en la mitad izquierda):

```gdscript
# JoystickVirtual.gd (Control)
signal move_vector_changed(v: Vector2)
var _touch_idx := -1

func _gui_input(ev: InputEvent) -> void:
    if ev is InputEventScreenTouch:
        if ev.pressed and _touch_idx == -1:
            _touch_idx = ev.index
        elif not ev.pressed and ev.index == _touch_idx:
            _touch_idx = -1; move_vector_changed.emit(Vector2.ZERO)
    elif ev is InputEventScreenDrag and ev.index == _touch_idx:
        var v := (ev.position - _origin) / radius
        move_vector_changed.emit(v.limit_length(1.0))
```

```gdscript
# Player.gd (CharacterBody3D)
func _physics_process(delta: float) -> void:
    var dir := Vector3(joy.move_vector.x, 0, joy.move_vector.y).rotated(Vector3.UP, cam_yaw)
    velocity.x = dir.x * move_speed * speed_mult
    velocity.z = dir.z * move_speed * speed_mult
    if not is_on_floor(): velocity.y -= fall_gravity * delta
    elif jump_requested and can_jump(): velocity.y = jump_impulse
    move_and_slide()
    # lean/facing hacia velocidad con poco coste:
    $Model.rotation.y = lerp_angle($Model.rotation.y, atan2(velocity.x, velocity.z), 10 * delta)
```

### 3.2 Mega-grupo de balas: **MultiMesh** obligatorio

Nunca un `Node3D` por bala. Un `MultiMeshInstance3D` por familia de proyectil:

```gdscript
# BulletSwarm.gd — pool + MultiMesh (mismo patrón que usan los shooters móviles)
@export var max_bullets := 4096
var _mm: MultiMesh
var _alive: PackedInt32Array      # índices vivos
var _pos: PackedVector3Array; var _vel: PackedVector3Array; var _life: PackedFloat32Array

func _ready() -> void:
    _mm = MultiMesh.new(); _mm.transform_format = MultiMesh.TRANSFORM_3D
    _mm.mesh = preload("res://fx/bullet_mesh.tres")
    _mm.instance_count = max_bullets
    $View.multimesh = _mm; _mm.visible_instance_count = 0

func fire(start: Vector3, dir: Vector3, speed: float, dmg: float) -> void:
    if _alive.size() >= max_bullets: return          # presupuesto duro
    var i := _free_idx(); _pos[i] = start; _vel[i] = dir * speed; _life[i] = 3.0; _alive.append(i)

func _process(delta: float) -> void:
    for idx in _alive.size():
        var i := _alive[idx]
        _pos[i] += _vel[i] * delta; _life[i] -= delta
        if _life[i] <= 0.0 or _hit_enemy(i): _kill(i)
    _mm.visible_instance_count = _alive.size()
    # escribir transforms por índice activo…
```

Reglas de rendimiento que aplicamos (derivadas del budget móvil, no del PC de Megabonk):
- **< 2.000 balas visibles** en gama media; **< 800** en gama baja (`OS.get_processor_count()` + `Performance` para auto-adjust).
- Colisión de balas: **no usar Area3D por bala**. Opciones por orden de coste: (a) distancia bala↔enemigo sobre una grilla espacial 2D (recomendado), (b) raycast batched, (c) areas solo para balas "hero" de alta importancia.

### 3.3 Hordas: Spawn Director data-driven

Archivo JSON controla todo el pacing (como los `catalog.json` de Addressables en Megabonk data):

```json
// data/spawn_table.json
{
  "by_minute": [
    { "t": 0,  "budget": 8,   "pools": { "goblin": 70, "bat": 30 }, "hp_mult": 1.0 },
    { "t": 3,  "budget": 16,  "pools": { "goblin": 50, "bat": 50 }, "hp_mult": 1.6 },
    { "t": 8,  "budget": 34,  "pools": { "goblin": 40, "bat": 40, "brute": 20 }, "hp_mult": 3.2 },
    { "t": 12, "budget": 50,  "pools": { "brute": 60, "boss_swarm": 40 }, "hp_mult": 5.0 }
  ],
  "ring_events": [ { "t": 5, "kind": "circle", "count": 40 }, { "t": 10, "kind": "wall" } ]
}
```

```gdscript
# SpawnDirector.gd
func _tick(delta: float) -> void:
    var tier := _tier_for(_run_time)
    _budget_accum += tier.budget * delta
    while _budget_accum >= 1.0 and _live_count < _cap_for_device():
        _spawn_one(_pick_weighted(tier.pools), tier.hp_mult)
        _budget_accum -= 1.0
```

Enemigos: `CharacterBody3D` reutilizados de pool, con **steering barato** (seek + separación por grid). Sin animación de esqueleto en masa: bob de escala/trayectoria en código o lerp entre 2 poses.

### 3.4 Arma automática (el corazón del bullet heaven)

Cada arma es un **Recurso** (data) + script genérico — no una escena por arma:

```json
// data/weapons.json
{ "id": "axe_spin", "dmg": 12, "fireinterval_s": 0.9, "pattern": "orbit", "count": 2,
  "scale_upgrade": [ { "lvl": 2, "count": 3 }, { "lvl": 4, "count": 4, "dmg": 18 } ] }
```

```gdscript
# WeaponInstance.gd
var db := ContentDB.weapons[self.weapon_id]
func _process(delta: float) -> void:
    _t += delta
    if _t >= db.fire_interval / _fire_rate_mult:
        _t = 0.0; SwarmRte.fire_pattern(db.pattern, player.pos, compute_stats(db))
```

- Patrones orbitales, cono, boomerang, aura y cadena de rayo — todos emiten al mismo `BulletSwarm`.
- **8–10 armas + 6–8 pasivas** para v1 (Megabonk observó un catálogo similar; se confirma el tamaño sensible).

### 3.5 XP, level-up y el "momento tienda" táctil

- Orbes de XP: `MultiMesh` también (son cientos). Magnet radius vía upgrade.
- Level-up **pausa el juego** y muestra 3 cartas grandes (área táctil ≥ 88 dp, feedback háptico `Input.vibrate_handheld(30)`).
- Regla de **rareza**: común 60% / raro 30% / épico 8% / legendario 2%; se evita repetir lo ofrecido cuando no puede combinarse (anti-duplicado).

### 3.6 Meta progresión y guardado

```gdscript
# SaveManager.gd — FileAccess (no preferencias nativas): portátil y fácil de sincronizar
const SAVE := "user://save.json"
func save() -> void:
    var d := { "coins": GameState.coins, "unlocked": GameState.unlocked,
               "high_score": GameState.best_time, "settings": audio.preset }
    FileAccess.open(SAVE, FileAccess.WRITE).store_string(JSON.stringify(d, "\t"))
```

- Desbloqueables por monedas de run (**arriba en la pantalla de muerte**, máximo impulso a jugar otra).
- **Leaderboard diario**: seed compartido → todos juegan la misma "run del día" (semi-online sin servidores).

### 3.7 Look toon (el estilo Megabonk se logra con shader + luz)

Shader toon mínimo (banding de 3 tonos + rim light):

```glsl
// fx/toon.gdshader
shader_type spatial;
uniform vec3 shade_color : source_color = vec3(0.25,0.22,0.35);
uniform float rim_power = 3.0;
void fragment() {
    ALBEDO = texture(base_tex, UV).rgb * mix(vec3(1.0), shade_color, shade_tone);
}
void light() {
    float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
    float band = step(0.5, ndl) * 0.7 + step(0.85, ndl) * 0.3;   // 3 bandas
    DIFFUSE_LIGHT += attenuation * LIGHT_COLOR * band * ALBEDO;
    float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
    DIFFUSE_LIGHT += rim * LIGHT_COLOR * 0.35;
}
```

- Outlines: **flip-normals shell mesh** (un mesh duplicado escalado 1.03 con `cull_front`) — más barato que postproceso en móvil.
- Partículas de impacto: `GPUParticles3D` (Android moderno) con fallback `CPUParticles3D` auto.

---

## 4. Presupuesto de rendimiento (móvil)

| Elemento | Gama alta | Gama media | Gama baja |
|---|---|---|---|
| Enemigos simultáneos | 250 | 140 | 70 |
| Balas activas (MultiMesh) | 2000 | 1200 | 600 |
| Draw calls por frame | < 150 | < 100 | < 60 |
| Cámara | + post-fx bloom barato | sin postproceso | renderer GL Compatibility |
| Resolución interna | nativa | 0.85× | 0.7× |

- Presupuesto medido con el **profiler de Godot** + `Engine.get_frames_per_second()` en build real (no editor).
- **Test de humo automatizado**: escena headless que simula 10 min de run a 4× la velocidad y reporta p95 frame time (CI con Godot CLI).
- Ojo con **AudioStreamPolyphonic** para sonidos de impacto masivos (pool de 8 voces).

---

## 5. Construcción y deployment

### Android
1. Export preset: **Android App Bundle (AAB)**, ARM64 + ARMv8, `textures/etc2_astc`.
2. Gradle: `minSdk 24`, target moderno; **AdMob/monetización** solo tras validar retención.
3. Play Standards: cumple los targets de API actuales; el AAB se firma con Play App Signing.

### iOS
1. Export Xcode project; Bitcode off, **Metal** automático (Godot maneja).
2. TestFlight para beta; Game Center para leaderboards.

### Mods/DLC estilo Addressables (hallazgo REA → decisión de diseño)
- Exporta **PCK adicionales** y cárgalos con `ProjectSettings.load_resource_pack()` → mapas/sets de armas como DLC sin rebuild del binario.
- Data-driven todo (JSON en `user://mods/` local permite mods de la comunidad, como el ecosistema MelonLoader observado).

---

## 6. Roadmap por fases (equipo 1–2 personas)

| Fase | Semanas | Entregable |
|---|---|---|
| 0 — Protoblocked | 1–2 | Movimiento táctil + 1 arma MultiMesh + 200 enemigos simples a 60 fps en tu móvil |
| 1 — Core loop | 3–5 | XP + level-up con cartas + 4 armas + 4 enemigos + 1 boss + muerte/victoria |
| 2 — Contenido | 6–8 | 10 armas, 12 enemigos, 3 mapas, meta-progresión + guardado |
| 3 — Pulido móvil | 9–10 | Batería, térmica, escalado por hardware, tutoriales, fixes de UX táctil |
| 4 — Release beta | 11–12 | AAB + TestFlight, analytics básicos, leaderboard diario |
| 5 — LiveOps | 13+ | Temporadas semanales (seed del día), PCK de mapas, mods |

**Criterio Go/No-Go Fase 0**: si tu gama media no logra 60 fps con 140 enemigos + 800 balas, reduzce el presupuesto o cambia a `gl_compatibility` — no apiles más sistemas encima de una base lenta.

---

## 7. Checklist de paridad con la referencia (desde evidencia)

- [x] Motor: realidad Unity IL2CPP → nuestro GraGodot AAB (GDScript)
- [x] Content pipeline Addressables → PCK mods
- [x] 5 escenas de nivel → plan 3 mapas v1 + seeds
- [x] Toon look (MK.Toon) → shader toon propio + rim
- [x] UI partículas (Coffee.UIParticle) → `GPUParticles2D` en Control nodes
- [x] Input profesional (Rewired) → joystick virtual configuráble + soporte gamepad
- [x] Platform services (Steamworks/Discord) → Google Play Games/Game Center
- [x] Moddability (MelonLoader) → API de mods PCK + JSON desde el día 1
- [ ] Evidencia nativa pendiente: pseudocódigo de sistemas individuales (análisis Ghidra de `GameAssembly.dll` en curso — se añadirá como apéndice cuando el snapshot se complete)

---

## 8. Notas finales

1. **Nunca copies los assets**: nombres de armas, música, personajes y UI de Megabonk son propiedad de Ved. Copia el *diseño de sistemas* (que es público), no la expresión.
2. Mide primero, optimiza después: el 90% del riesgo de un bullet-heaven móvil es rendimiento, no funciones.
3. La ventaja competitiva de tu propuesta no es "Megabonk en móvil" — es el **ritmo táctil** (runs 5–15 min, upgrades con una mano, sin menús profundos).
4. Cuando el análisis nativo de REA complete el snapshot de `GameAssembly.dll`, este documento ganará un **Apéndice A: operaciones por sistema** con pseudocódigo real de spawns/meta/XP — esa sección se insertará automáticamente en `rea-analysis/`.

---

*Generada el 24/10/2026 a partir de análisis REA estático de la build local. Evidencia principal: `ev_9c66099a9092fb6f00f4c0ea7fbeb2b86db7b5fadde7813970afee95ec0f8aff` (inventario de app), observación de `GameAssembly.dll` SHA-256 `4350a7ae25ba7aec35677c213fdceabbb638676bb00ab59131d7d9c37b6e3d9e`.*

---

**Apéndice A disponible:** la copia de trabajo de esta guía y el desglose de sistemas del juego de referencia están en HordaviaPrototype/docs/ (ver docs/00_INDICE.md).
