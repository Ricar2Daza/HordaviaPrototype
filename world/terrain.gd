## Terrain — mapa procedural ampliado (arena + cordillera) por run.
## Heightfield cuantizado en escalones de 0.25 m, terreno caminable en el centro y
## montañas altas en el perímetro. Render: MultiMesh de columnas + picos low-poly.
## API usada por player/enemigos/orbes: height_at(x, z) -> float.
extends Node3D

const HALF := 54.0         # mitad del mapa visual (108 x 108 m)
const CELL := 2.0          # ancho de columna (más fino = menos paredes falsas)
const STEP := 0.25         # altura por escalón
const MAX_H := 1.6         # relieve interior caminable (bajo, no tapa al jugador)
const CLIFF_FROM := 31.0   # inicio de la cordillera (fuera del área jugable)
const CLIFF_H := 24.0      # altura máxima de la cordillera
const DEPTH := 4.0         # profundidad visual bajo la cota
const PEAKS := 64

var _n := 0                          # columnas por lado
var _h: PackedFloat32Array = PackedFloat32Array()
var _mat: ShaderMaterial = null
var _mountain_mat: ShaderMaterial = null
var _peak_mat: ShaderMaterial = null


func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var broad := FastNoiseLite.new()
	broad.seed = rng.randi()
	broad.frequency = 0.026
	broad.noise_type = FastNoiseLite.TYPE_SIMPLEX

	var detail := FastNoiseLite.new()
	detail.seed = rng.randi()
	detail.frequency = 0.085
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX

	var ridge := FastNoiseLite.new()
	ridge.seed = rng.randi()
	ridge.frequency = 0.014
	ridge.fractal_octaves = 3
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_n = int(HALF * 2.0 / CELL)
	_h.resize(_n * _n)
	for iz in _n:
		for ix in _n:
			var cx: float = (float(ix) + 0.5) * CELL - HALF
			var cz: float = (float(iz) + 0.5) * CELL - HALF
			_h[iz * _n + ix] = _compute_h(broad, detail, ridge, cx, cz)

	# MultiMesh: una única draw call para todo el suelo.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = _n * _n
	var box := BoxMesh.new()
	box.size = Vector3(CELL, 1.0, CELL)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://fx/toon.gdshader")
	_mat.set_shader_parameter("base_color", Color(0.24, 0.33, 0.30))
	_mat.set_shader_parameter("height_color", Color(0.46, 0.56, 0.51))
	_mat.set_shader_parameter("height_start", 0.25)
	_mat.set_shader_parameter("height_end", 2.4)
	_mat.set_shader_parameter("height_amount", 0.30)
	_mat.set_shader_parameter("rim_strength", 0.42)
	box.material = _mat
	mm.mesh = box
	var idx := 0
	for iz in _n:
		for ix in _n:
			var h := _h[idx]
			var t := Transform3D(
				Basis.IDENTITY.scaled(Vector3(1.0, h + DEPTH, 1.0)),
				Vector3((float(ix) + 0.5) * CELL - HALF, h - DEPTH * 0.5, (float(iz) + 0.5) * CELL - HALF)
			)
			mm.set_instance_transform(idx, t)
			idx += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if GameState.shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	_build_peaks(rng)


func _build_peaks(rng: RandomNumberGenerator) -> void:
	# Picos low-poly sobre la cordillera: dos draw calls (roca + nieve).
	var rock_mm := MultiMesh.new()
	rock_mm.transform_format = MultiMesh.TRANSFORM_3D
	rock_mm.instance_count = PEAKS
	var peak := CylinderMesh.new()
	peak.top_radius = 0.02
	peak.bottom_radius = 1.0
	peak.height = 1.0
	peak.radial_segments = 5
	peak.rings = 2
	_mountain_mat = ShaderMaterial.new()
	_mountain_mat.shader = load("res://fx/toon.gdshader")
	_mountain_mat.set_shader_parameter("base_color", Color(0.26, 0.28, 0.34))
	_mountain_mat.set_shader_parameter("height_color", Color(0.78, 0.84, 0.92))
	_mountain_mat.set_shader_parameter("height_start", 10.0)
	_mountain_mat.set_shader_parameter("height_end", 30.0)
	_mountain_mat.set_shader_parameter("height_amount", 0.92)
	peak.material = _mountain_mat
	rock_mm.mesh = peak

	var snow_mm := MultiMesh.new()
	snow_mm.transform_format = MultiMesh.TRANSFORM_3D
	snow_mm.instance_count = PEAKS
	var cap := CylinderMesh.new()
	cap.top_radius = 0.01
	cap.bottom_radius = 1.0
	cap.height = 1.0
	cap.radial_segments = 5
	cap.rings = 1
	_peak_mat = ShaderMaterial.new()
	_peak_mat.shader = load("res://fx/toon.gdshader")
	_peak_mat.set_shader_parameter("base_color", Color(0.86, 0.92, 1.0))
	_peak_mat.set_shader_parameter("rim_strength", 0.7)
	cap.material = _peak_mat
	snow_mm.mesh = cap

	for i in PEAKS:
		var a := TAU * float(i) / float(PEAKS) + rng.randf_range(-0.05, 0.05)
		# Los picos quedan detrás de la cámara (radio > 47 m) para que nunca
		# se interpongan entre la vista y el jugador cerca del borde.
		var r := rng.randf_range(47.0, 52.5)
		var pos := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var base_y := height_at(pos.x, pos.z) - 1.0
		var h := rng.randf_range(6.0, 16.0)
		var width := rng.randf_range(3.0, 6.0)
		var t := Transform3D(
			Basis.IDENTITY.scaled(Vector3(width, h, width)),
			Vector3(pos.x, base_y + h * 0.5, pos.z)
		)
		rock_mm.set_instance_transform(i, t)
		var cap_h := h * rng.randf_range(0.20, 0.32)
		var cap_w := width * rng.randf_range(0.40, 0.58)
		var ct := Transform3D(
			Basis.IDENTITY.scaled(Vector3(cap_w, cap_h, cap_w)),
			Vector3(pos.x, base_y + h - cap_h * 0.5, pos.z)
		)
		snow_mm.set_instance_transform(i, ct)

	var rock_mi := MultiMeshInstance3D.new()
	rock_mi.multimesh = rock_mm
	rock_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if GameState.shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rock_mi)
	var snow_mi := MultiMeshInstance3D.new()
	snow_mi.multimesh = snow_mm
	snow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(snow_mi)


func _compute_h(broad: FastNoiseLite, detail: FastNoiseLite, ridge: FastNoiseLite, x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var n := broad.get_noise_2d(x, z) * 0.5 + 0.5
	var d := detail.get_noise_2d(x, z) * 0.5 + 0.5
	var base := clampf(n * 0.72 + d * 0.28, 0.0, 1.0)
	# Centro casi llano: el relieve solo aparece en el anillo exterior, con
	# pendientes suaves. Así ninguna colina tapa al personaje ni finge altura.
	var center_flat := 0.10 + 0.90 * clampf(r / 26.0, 0.0, 1.0)
	var relief := pow(base, 1.55) * MAX_H * center_flat
	if r > 18.0 and r < CLIFF_FROM:
		var k := sin((r - 18.0) / maxf(CLIFF_FROM - 18.0, 0.01) * PI)
		relief += k * 0.65 * (0.35 + 0.65 * d)
	# Cordillera perimetral: ruido ridged + muro de fondo.
	var mountain := 0.0
	if r > CLIFF_FROM:
		var k2 := clampf((r - CLIFF_FROM) / maxf(HALF - CLIFF_FROM, 0.01), 0.0, 1.0)
		var ridged := pow(1.0 - absf(ridge.get_noise_2d(x, z)), 2.0)
		mountain = pow(k2, 1.45) * CLIFF_H * (0.45 + 0.75 * ridged)
		mountain += pow(k2, 2.0) * 4.0
	return floorf((relief + mountain) / STEP) * STEP


func height_at(x: float, z: float) -> float:
	if _n <= 0:
		return 0.0
	var ix := clampi(int((x + HALF) / CELL), 0, _n - 1)
	var iz := clampi(int((z + HALF) / CELL), 0, _n - 1)
	return _h[iz * _n + ix]


func set_palette(c: Color) -> void:
	if _mat != null:
		_mat.set_shader_parameter("base_color", c)
		# Tinte sutil por altura: hace legible el relieve real sin convertirlo
		# en una pared visual que oculte al jugador.
		_mat.set_shader_parameter("height_color", c.lightened(0.30).lerp(Color.WHITE, 0.08))
		_mat.set_shader_parameter("height_start", 0.25)
		_mat.set_shader_parameter("height_end", 2.4)
		_mat.set_shader_parameter("height_amount", 0.30)
	if _mountain_mat != null:
		_mountain_mat.set_shader_parameter("base_color", c.darkened(0.42).lerp(Color(0.26, 0.28, 0.34), 0.60))
