# Guía de assets — cómo agregar modelos, texturas, audio y fuentes

## 1. Estructura de carpetas (conveniencia del proyecto)

```
HordaviaPrototype/
  assets/
	models/            # .glb / .gltf (Blender, y-up, escala 1 unidad = 1 m)
	  enemies/         #   goblin.glb, bat.glb, brute.glb ...
	  player/          #   heroe.glb (con animaciones incluidas)
	  props/           #   roca.glb, arbol.glb, cofre.glb
	  weapons/         #   baston.glb, cuchilla.glb
	textures/          # .png (paleta, decals, partículas)
	audio/
	  sfx/             # .wav corto (disparo, hit, pickup, levelup)
	  music/           # .ogg loopada (menu.ogg, bioma_bosque.ogg)
	ui/                # iconos de armas (128×128), fuentes .ttf
	vfx/               # texturas de partícula (círculo suave, chispa)
  data/                # JSON data-driven (ya existe)
  fx/                  # shaders propios (toon.gdshader)
```

## 2. Modelos 3D (el camino feliz)

1. **Exportar de Blender como `.glb`**:
   - Escala 1 m = 1 unidad Godot. "Apply" de transformaciones antes de exportar.
   - Geometría low-poly (enemigo ≤ 500 tris, props ≤ 200 tris).
   - Animaciones en el mismo glb (AnimationPlayer las recoge con nombre).
2. **Arrastrar el `.glb` a `assets/models/...`** dentro del FileSystem de Godot → se importa solo.
3. **Asignarlo al nodo**: reemplaza la cápsula procedural del prototipo:
   ```gdscript
   # Ejemplo: goblin con modelo real (EnemyManager._make_visual)
   var scene := load("res://assets/models/enemies/goblin.glb") as PackedScene
   var model := scene.instantiate()
   model.position.y = 0.0
   root.add_child(model)
   ```
4. **Look toon**: el material del modelo se sobreescribe por el shader propio.
   En el Inspector del `MeshInstance3D`: **Geometry → Material Override** →
   nuevo `ShaderMaterial` con `fx/toon.gdshader`, y ajusta `base_color`.
   (Así heredas bandas + rim sin depender del material importado.)

> Truco: si el modelo trae su Material con textura difusa, puedes dejarlo y solo
> compartir el shader toon a futuro; el objetivo estético es "flat + rim", y ambas
> rutas lo logran. Para móvil, menos texturas = menos memoria.

## 3. Texturas

- Formato `.png` (o `.webp` para peso). Reglas para móvil:
  - UI/iconos: hasta 256–512 px. No necesita mipmaps.
  - Textura de entorno: ≤ 2048 px, **mipmaps ON**, filtrado anisotrópico 2x.
  - Partículas: 128–256 px, fondo transparente.
- Import (Import dock al seleccionar el png):
  - 3D textures → **VRAM Compressed** (el proyecto ya activa `import_etc2_astc=true`).
  - 2D/HUD → **Lossless**.
- El proyecto no usa atlas por ahora; si agregas muchas partículas, metelas todas
  en una sola textura-atlas y use `region_rect` para ahorrar draw calls.

## 4. Audio

- **SFX**: `.wav` PCM 16-bit, mono, 44 kHz, ≤ 300 KB c/u. Import por defecto ok.
  - Loop de música en import: enable **Loop Editing → Loop** o usa `.ogg` loop.
- Reproducción barata vía pool (ya existe patrón en los managers):
  ```gdscript
  var sfx := AudioStreamPlayer.new()
  sfx.stream = load("res://assets/audio/sfx/hit.wav")
  sfx.bus = "SFX"
  add_child(sfx)
  sfx.play()
  ```
- Crea un bus "Música" y "SFX" en el panel Audio → default_bus_layout.tres.

## 5. Fuentes e iconos de armas

- Fuente: arrastra `.ttf` a `assets/ui/`, luego en temas; sugerida la categoría
  "cabeza grande y carga dynamic" (para HUD con números legibles a toda distancia).
- Íconos de armas cartas: `assets/ui/icons/wand.png`, etc. Cuando agreguemos el
  feature "icono en carta", el JSON arma ganará un campo opcional:
  ```json
  "wand": { "pattern": "nearest", "dmg": 12, "icon": "res://assets/ui/icons/wand.png" }
  ```
  y la carta lo carga con `load(icon)` (extension point ya previsto).

## 6. Integración con el contenido (sin tocar código)

- **Enemigo nuevo**: agrega entrada en `data/enemies.json` (+ spawn en `spawn_table.json`)
  → cae al pool solo. Para modelo+color: usa `color` del JSON hoy; el modelo glb queda pendiente de 1.4.
- **Arma nueva**: entrada en `data/weapons.json` con `pattern` soportado hoy:
  `nearest` | `orbit`. Cuando lleguen los otros patrones (features 2.1), se agrega el emisor en `weapons/weapon_instance.gd` y el JSON solo lo data.
- **Mejora nueva**: entrada en `data/upgrades.json` (+ efecto nuevo en `game_state.apply_upgrade`).
- **Balance del mapa**: `data/spawn_table.json` (budget por minuto, pools, eventos ring).

## 7. Fuentes de assets gratuitos (con licencia bien limpia)

- **Kenney.nl** — packs de low-poly, UI, audio (CC0, sin atribución necesaria).
- **Quaternius.com** — packs de low-poly RPG/monstruos (CC0).
- **Kay Lousberg** (kenel). —, Godot-friendly low-poly characters (CC0).
- **OpenGameArt** — revisa licencia por asset (CC-BY ok con créditos).
- SFX: **jsfxr / Bfxr** para retro, o freesound (CC-BY con créditos).

> Regla del proyecto: **ningún asset extraído del juego de referencia.** Assets propios
> o CC0/CC-BY. Megabonk es marca y propiedad de su estudio; la imitación sera en mecánica,
> no en contenido.

## 8. Checklist por asset antes de commit

- [ ] Tiene licencia limpia o es propio.
- [ ] Peso razonable (modelo < 300 KB, textura < 1 MB, sfx < 300 KB).
- [ ] Import settings revisados (compresión VRAM si va en 3D).
- [ ] Cargado vía `load("res://assets/...")` o asignado en escena, y probado al menos una vez para verificar que se ve/escucha bien en el prototipo.
- [ ] Nombre_snake_consistente con el resto de la carpeta.
