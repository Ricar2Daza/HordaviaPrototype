## Weather — clima procedural barato para móvil.
## Un MultiMesh de partículas sigue al jugador; cada bioma define tipo/intensidad.
## También expone niebla y un pulso de relámpago para tormentas.
extends Node3D

signal flash

const MAX_PARTICLES := 460
const FIELD := 30.0

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _mat: StandardMaterial3D
var _terrain = null
var _p: PackedVector3Array = PackedVector3Array()
var _phase: PackedFloat32Array = PackedFloat32Array()
var _kind := "clear"
var _label := "Despejado"
var _intensity := 0.0
var _active := 0
var _wind := Vector3.ZERO
var _speed_mult := 1.0
var _next_flash := 0.0
var _flash_t := 0.0


func setup(t) -> void:
	_terrain = t
	_p.resize(MAX_PARTICLES)
	_phase.resize(MAX_PARTICLES)
	for i in MAX_PARTICLES:
		_phase[i] = randf() * TAU
		_respawn(i, true)
	_build_mesh()


func _build_mesh() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.vertex_color_use_as_albedo = false
	_mat.albedo_color = Color(0.7, 0.8, 1.0, 0.55)
	_mat.emission_enabled = true
	_mat.emission = Color(0.3, 0.4, 0.6)
	_mat.emission_energy_multiplier = 0.4
	box.material = _mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = box
	_mm.instance_count = MAX_PARTICLES
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)


## w = {"type", "label", "intensity", "speed", "color", "wind"}
func set_weather(w: Dictionary, reset: bool = true) -> void:
	var old := _kind
	_kind = String(w.get("type", "clear"))
	_label = String(w.get("label", "Despejado"))
	_intensity = clampf(float(w.get("intensity", 0.8)), 0.0, 1.35)
	_speed_mult = clampf(float(w.get("speed", 1.0)), 0.8, 1.0)
	var col_arr: Array = w.get("color", [0.7, 0.8, 1.0])
	_mat.albedo_color = Color(float(col_arr[0]), float(col_arr[1]), float(col_arr[2]), 0.62)
	_mat.emission = Color(float(col_arr[0]), float(col_arr[1]), float(col_arr[2]))
	_wind = _wind_for(_kind)
	_set_active()
	_next_flash = randf_range(5.0, 12.0)
	if reset or old != _kind:
		for i in MAX_PARTICLES:
			_respawn(i, true)
		for i in MAX_PARTICLES:
			_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _p[i]))
		_mm.visible_instance_count = _active


func _wind_for(kind: String) -> Vector3:
	match kind:
		"rain":
			return Vector3(1.6, -19.0, 0.8)
		"storm":
			return Vector3(4.2, -25.0, 2.0)
		"snow":
			return Vector3(1.2, -2.4, 0.4)
		"ash":
			return Vector3(1.8, -1.8, 0.7)
		"sand":
			return Vector3(17.0, -0.8, 3.0)
		"embers":
			return Vector3(0.8, 1.4, 0.3)
		"fog":
			return Vector3(0.5, 0.05, 0.2)
		_:
			return Vector3.ZERO


func _set_active() -> void:
	var n := 0
	match _kind:
		"clear":
			n = 0
		"fog":
			n = int(70.0 * GameState.fx_mult * _intensity)
		"embers":
			n = int(110.0 * GameState.fx_mult * _intensity)
		"ash":
			n = int(220.0 * GameState.fx_mult * _intensity)
		_:
			n = int(300.0 * GameState.fx_mult * _intensity)
	_active = clampi(n, 0, MAX_PARTICLES)
	if _mm != null:
		_mm.visible_instance_count = _active


func apply_quality() -> void:
	_set_active()


func _respawn(i: int, high: bool = false) -> void:
	var x := randf_range(-FIELD, FIELD)
	var z := randf_range(-FIELD, FIELD)
	var y := randf_range(2.0, 26.0) if high else randf_range(18.0, 28.0)
	_p[i] = Vector3(x, y, z)


func _physics_process(dt: float) -> void:
	var p = EnemyManager.player
	if p != null:
		global_position = Vector3(p.position.x, 0.0, p.position.z)
	if _active <= 0:
		if _mm != null and _mm.visible_instance_count != 0:
			_mm.visible_instance_count = 0
		return
	if _kind == "storm" and GameState.run_active and not get_tree().paused:
		_next_flash -= dt
		if _next_flash <= 0.0:
			_next_flash = randf_range(6.0, 14.0)
			flash.emit()
			AudioManager.play_sfx("zap", 0.55)
	var pscale := _particle_scale()
	for i in _active:
		var pos := _p[i]
		match _kind:
			"rain", "storm":
				pos += Vector3(_wind.x, _wind.y, _wind.z) * dt
			"snow":
				pos.y += _wind.y * dt
				pos.x += (sin(Time.get_ticks_msec() * 0.001 + _phase[i]) * 1.2 + _wind.x) * dt
				pos.z += cos(Time.get_ticks_msec() * 0.0013 + _phase[i]) * 0.5 * dt
			"ash":
				pos.y += _wind.y * dt
				pos.x += (sin(Time.get_ticks_msec() * 0.0008 + _phase[i]) * 1.8 + _wind.x) * dt
				pos.z += _wind.z * dt
			"sand":
				pos.x += _wind.x * dt
				pos.y += _wind.y * dt
				pos.z += _wind.z * dt
			"embers":
				pos.y += _wind.y * dt
				pos.x += sin(Time.get_ticks_msec() * 0.0011 + _phase[i]) * 1.1 * dt
			"fog":
				pos.x += sin(Time.get_ticks_msec() * 0.0006 + _phase[i]) * 0.7 * dt
				pos.z += cos(Time.get_ticks_msec() * 0.0007 + _phase[i]) * 0.5 * dt
		var floor_y := 0.0
		if _terrain != null:
			floor_y = float(_terrain.call("height_at", global_position.x + pos.x, global_position.z + pos.z)) + 0.15
		var dead := false
		match _kind:
			"rain", "storm", "snow", "ash":
				dead = pos.y < floor_y
			"sand":
				dead = pos.x > FIELD or pos.y < floor_y
			"embers":
				dead = pos.y > 27.0
			"fog":
				dead = pos.y < floor_y or pos.y > 24.0
		if dead:
			if _kind == "sand":
				pos = Vector3(-FIELD, randf_range(0.5, 8.0), randf_range(-FIELD, FIELD))
			elif _kind == "embers":
				pos = Vector3(randf_range(-FIELD, FIELD), floor_y + 0.2, randf_range(-FIELD, FIELD))
			else:
				pos = Vector3(randf_range(-FIELD, FIELD), randf_range(20.0, 28.0), randf_range(-FIELD, FIELD))
		_p[i] = pos
		var t := Transform3D(Basis.IDENTITY.scaled(pscale), pos)
		_mm.set_instance_transform(i, t)
	_mm.visible_instance_count = _active


func _particle_scale() -> Vector3:
	match _kind:
		"rain", "storm":
			return Vector3(0.018, 0.62, 0.018)
		"snow":
			return Vector3(0.10, 0.10, 0.10)
		"ash":
			return Vector3(0.055, 0.055, 0.055)
		"sand":
			return Vector3(0.07, 0.035, 0.035)
		"embers":
			return Vector3(0.05, 0.05, 0.05)
		_:
			return Vector3(0.08, 0.08, 0.08)


func label() -> String:
	return _label


func speed_mult() -> float:
	return _speed_mult
