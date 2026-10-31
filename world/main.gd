## Main — construir mundo, cámara, luces y parar/partir la run (prototipo).
extends Node3D

const CAM_OFFSET := Vector3(0.0, 19.5, 12.5)
const MOUSE_SENS := 0.004

var player: Node3D
var cam: Camera3D
var cam_yaw := 0.0           # yaw de cámara: fijo en "fija", se rota con mouse en "mouse"

var _shake := 0.0
var _last_hp := 100.0
var _biome_id := ""
var _biome_cur := {}
var _env: Environment = null
var _light: DirectionalLight3D = null
var _terrain: Node3D = null
var _weather: Node3D = null
var _hazards: Node3D = null
var _pickups: Node3D = null
var _fx_rings: Array = []   # {node, t} anillos de portal (roadmap 3.2)
var _smoke_pickups_done := false
var _props_holder: Node3D = null
var _prop_mat: ShaderMaterial = null
var _chests: Array = []      # [{node: MeshInstance3D, base_y: float, t: float}]
var _light_base := 1.1
var _flash_t := 0.0


func _ready() -> void:
	add_to_group("main")
	_build_environment()
	_build_terrain()
	_hazards = Node3D.new()
	_hazards.set_script(load("res://world/hazards.gd"))
	add_child(_hazards)
	_hazards.call("setup", _terrain)
	_pickups = Node3D.new()
	_pickups.set_script(load("res://world/pickups.gd"))
	add_child(_pickups)
	_props_holder = Node3D.new()
	add_child(_props_holder)
	player = _build_player()
	_build_weather()
	_spawn_camera()
	_apply_camera_mode()
	_apply_quality()
	var biomes: Array = ContentDB.biomes
	if not biomes.is_empty():
		_apply_biome(biomes[0])
	GameState.hp_changed.connect(_on_hp_changed)
	GameState.biome_changed.connect(_apply_biome)
	GameState.setting_changed.connect(_apply_camera_mode)
	GameState.kill_event.connect(_on_kill_event)
	GameState.run_reset.connect(_on_run_reset)
	if GameState.debug_auto_upgrade or GameState.auto_start_next:
		GameState.auto_start_next = false
		GameState.start_run()


func _on_hp_changed(hp: float, _max_hp: float) -> void:
	if hp < _last_hp - 0.01:
		_shake = 0.14
	_last_hp = hp


func _unhandled_input(event: InputEvent) -> void:
	# Cámara con mouse (modo "mouse") + toggle rápido con C
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if GameState.camera_mode == "mouse" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and GameState.camera_mode == "mouse":
		cam_yaw -= event.relative.x * MOUSE_SENS
	elif event.is_action_pressed("toggle_camera"):
		GameState.set_camera_mode("mouse" if GameState.camera_mode == "fija" else "fija")


func _physics_process(_dt: float) -> void:
	# Stick derecho / Q-E: orbitar solo en modo Mouse (en Fija la cámara no gira).
	if GameState.camera_mode == "mouse":
		var cam_x := Input.get_axis("cam_left", "cam_right")
		if absf(cam_x) > 0.05:
			cam_yaw -= cam_x * 2.4 * _dt
	_update_cam(_dt)
	_update_chests(_dt)
	_update_rings(_dt)
	# Relámpago de tormenta: pulso breve sobre la luz direccional.
	if _flash_t > 0.0 and _light != null:
		_flash_t = maxf(_flash_t - _dt, 0.0)
		_light.light_energy = _light_base + 3.2 * (_flash_t / 0.18)
	elif _light != null and absf(_light.light_energy - _light_base) > 0.01:
		_light.light_energy = _light_base
	# Smoke: a los 20 s suelta los 3 pickups bajo el bot para validar el pick (2.7)
	if (GameState.debug_auto_upgrade and GameState.run_active and not _smoke_pickups_done
			and GameState.run_time > 20.0 and player != null and _pickups != null):
		_smoke_pickups_done = true
		_pickups.call("spawn", "heal", player.position)
		_pickups.call("spawn", "magnet", player.position)
		_pickups.call("spawn", "bomb", player.position)


func _on_run_reset() -> void:
	if _pickups != null and _pickups.has_method("clear"):
		_pickups.call("clear")
	_spawn_chests(2 + randi() % 2)


func _on_kill_event(pos: Vector3, elite: bool) -> void:
	if not GameState.run_active:
		return
	if elite:
		_spawn_chest_at(pos)
	elif randf() < 0.02 and _pickups != null:
		_pickups.call("spawn_random", pos)


func _update_rings(dt: float) -> void:
	for r in _fx_rings.duplicate():
		var node: MeshInstance3D = r["node"]
		if not is_instance_valid(node):
			_fx_rings.erase(r)
			continue
		r["t"] = float(r["t"]) + dt
		var k: float = clampf(float(r["t"]) / 1.1, 0.0, 1.0)
		node.scale = Vector3.ONE * (0.4 + 4.0 * k)
		((node.mesh as TorusMesh).material as StandardMaterial3D).albedo_color.a = 0.7 * (1.0 - k)
		if k >= 1.0:
			_fx_rings.erase(r)
			node.queue_free()


func _portal_fx(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.45, 0.95, 1.0, 0.7)
	torus.material = mat
	mi.mesh = torus
	mi.position = Vector3(pos.x, _terrain_h(pos) + 0.2, pos.z)
	add_child(mi)
	_fx_rings.append({"node": mi, "t": 0.0})


func _update_cam(dt: float) -> void:
	if player == null or cam == null:
		return
	var off: Vector3 = Basis(Vector3.UP, cam_yaw) * CAM_OFFSET
	cam.position = cam.position.lerp(player.position + off, 0.18)
	if _shake > 0.0:
		_shake = maxf(_shake - dt, 0.0)
		cam.position += Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0) * 0.4, randf_range(-1.0, 1.0)
		) * 0.35 * _shake
	cam.look_at(player.position + Vector3(0.0, 0.5, 0.0))


func _apply_camera_mode() -> void:
	Input.mouse_mode = (
		Input.MOUSE_MODE_CAPTURED if GameState.camera_mode == "mouse" else Input.MOUSE_MODE_VISIBLE
	)
	cam_yaw = 0.0


func _terrain_h(pos: Vector3) -> float:
	if GameState.terrain != null:
		return float(GameState.terrain.call("height_at", pos.x, pos.z))
	return 0.0


# ------------------------------------------------------------------ chests --
func _update_chests(dt: float) -> void:
	if player == null or not GameState.run_active:
		return
	for c in _chests:
		if bool(c.get("open", false)) or not is_instance_valid(c.get("node")):
			continue
		var node: MeshInstance3D = c["node"]
		c["t"] = float(c["t"]) + dt
		node.rotation.y += dt * 1.6
		node.position.y = float(c["base_y"]) + 0.28 * sin(float(c["t"]) * 3.0) + 0.35
		if node.position.distance_to(player.position) < 2.2:
			c["open"] = true
			node.visible = false
			DeathFx.spawn(node.position, Color(1.0, 0.83, 0.25), false)
			AudioManager.play_sfx("pickup")
			GameState.offer_chest_cards()


func _spawn_chests(count: int) -> void:
	for c in _chests:
		var old = c.get("node")
		if old != null and is_instance_valid(old):
			_props_holder.remove_child(old)
			old.free()
	_chests.clear()
	for i in count:
		var ang := randf() * TAU
		var r := randf_range(9.0, 32.0)
		_spawn_chest_at(Vector3(cos(ang) * r, 0.0, sin(ang) * r))


func _spawn_chest_at(pos: Vector3) -> void:
	var p := Vector3(pos.x, _terrain_h(pos) + 0.3, pos.z)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.5, 0.55)
	box.material = _gold_mat()
	mi.mesh = box
	mi.position = p
	mi.set_meta("chest", true)
	_props_holder.add_child(mi)
	_chests.append({"node": mi, "base_y": p.y, "t": randf() * TAU, "open": false})


func _gold_mat() -> ShaderMaterial:
	var mat := _toon_mat(Color(0.95, 0.75, 0.2))
	mat.set_shader_parameter("rim_strength", 1.4)
	return mat


# ------------------------------------------------------------------ biomas --
func _col(a: Variant, fallback: Color) -> Color:
	if a is Array and a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


func _apply_biome(b: Dictionary) -> void:
	if _hazards != null:
		_hazards.call("spawn_for_biome", b)
	var id := String(b.get("id", "bosque"))
	var tag := "%s#%d" % [id, GameState.endless_loop]
	if tag != _biome_id:
		_biome_id = tag
		_biome_cur = b
		GameState.biome_name = String(b.get("name", id))
		GameState.biome_index = _biome_index(id)
		var g := _col(b.get("ground"), Color(0.24, 0.33, 0.30))
		if GameState.terrain != null:
			GameState.terrain.call("set_palette", g)
		if _env != null:
			_env.background_color = _col(b.get("bg"), Color(0.09, 0.08, 0.14))
			_env.ambient_light_color = _col(b.get("ambient"), Color(0.55, 0.55, 0.75))
		if _light != null:
			_light.light_color = _col(b.get("light"), Color(1.0, 0.95, 0.85))
			_light_base = float(b.get("light_energy", 1.1))
			_light.light_energy = _light_base
		_apply_weather(b)
		_prop_rebuild(b)
		_spawn_chests(2 + randi() % 2)
		if player != null:
			_portal_fx(player.position)
		if GameState.debug_auto_upgrade:
			print("SMOKE_BIOME id=%s weather=%s cycle=%d" % [
				id, GameState.weather_name, GameState.endless_loop,
			])


func _biome_index(id: String) -> int:
	for i in ContentDB.biomes.size():
		if String(ContentDB.biomes[i].get("id", "")) == id:
			return i
	return 0


func _apply_weather(b: Dictionary) -> void:
	var w: Dictionary = b.get("weather", {}) if b.get("weather", {}) is Dictionary else {}
	if _weather != null:
		_weather.call("set_weather", w)
		GameState.weather_name = String(_weather.call("label"))
		GameState.weather_speed_mult = float(_weather.call("speed_mult"))
	else:
		GameState.weather_name = "Despejado"
		GameState.weather_speed_mult = 1.0
	GameState.weather_type = String(w.get("type", "clear"))
	if _env != null:
		var fog := float(w.get("fog", 0.0))
		if fog > 0.0:
			_env.fog_enabled = true
			_env.fog_density = fog * (0.72 if GameState.device_tier == "bajo" else 1.0)
			_env.fog_light_color = _col(w.get("color"), _col(b.get("ambient"), Color(0.6, 0.65, 0.75)))
			_env.fog_light_energy = 0.8
			_env.fog_sun_scatter = 0.25
		else:
			_env.fog_enabled = false


func _on_weather_flash() -> void:
	_flash_t = 0.18
	_shake = maxf(_shake, 0.06)


func _prop_rebuild(b: Dictionary) -> void:
	var pc: Dictionary = b.get("props", {}) if b.get("props", {}) is Dictionary else {}
	var c := _col(pc.get("color"), Color(0.45, 0.42, 0.5))
	var kind := String(pc.get("kind", "rock"))
	var count := int(float(int(pc.get("count", 40))) * GameState.prop_mult * 1.15)
	count = maxi(count, 8)
	for child in _props_holder.get_children():
		if not child.has_meta("chest"):
			_props_holder.remove_child(child)
			child.free()
	_prop_mat = _toon_mat(c)
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 5:
		attempts += 1
		var ang := randf() * TAU
		var r := randf_range(7.0, 40.0)
		var pos := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var gy := _terrain_h(pos)
		if gy > 8.0:
			continue
		pos.y = gy
		var node := _make_prop(kind, _prop_mat)
		node.position = pos
		node.rotation.y = randf() * TAU
		_props_holder.add_child(node)
		placed += 1


func _make_prop(kind: String, mat: ShaderMaterial) -> Node3D:
	var root := Node3D.new()
	match kind:
		"stalg":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.02
			cone.bottom_radius = randf_range(0.25, 0.55)
			cone.height = randf_range(1.4, 3.0)
			cone.radial_segments = 5
			cone.material = mat
			_add_mesh(root, cone, Vector3(0.0, cone.height * 0.5, 0.0))
		"cactus":
			var box := BoxMesh.new()
			box.size = Vector3(0.35, randf_range(1.6, 2.8), 0.35)
			box.material = mat
			_add_mesh(root, box, Vector3(0.0, box.size.y * 0.5, 0.0))
			var arm := BoxMesh.new()
			arm.size = Vector3(0.22, 0.8, 0.22)
			arm.material = mat
			_add_mesh(root, arm, Vector3(0.35, box.size.y * 0.55, 0.0))
		"tree":
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.16
			trunk.bottom_radius = 0.28
			trunk.height = 1.8
			trunk.radial_segments = 5
			var bark := _toon_mat(Color(0.28, 0.22, 0.18))
			trunk.material = bark
			_add_mesh(root, trunk, Vector3(0.0, 0.9, 0.0))
			var crown := CylinderMesh.new()
			crown.top_radius = 0.02
			crown.bottom_radius = randf_range(1.1, 1.8)
			crown.height = randf_range(2.4, 3.8)
			crown.radial_segments = 6
			crown.material = mat
			_add_mesh(root, crown, Vector3(0.0, 1.8 + crown.height * 0.5, 0.0))
		"mushroom":
			var stem := CylinderMesh.new()
			stem.top_radius = 0.16
			stem.bottom_radius = 0.24
			stem.height = randf_range(0.7, 1.3)
			stem.radial_segments = 5
			var pale := _toon_mat(Color(0.78, 0.76, 0.62))
			stem.material = pale
			_add_mesh(root, stem, Vector3(0.0, stem.height * 0.5, 0.0))
			var cap := SphereMesh.new()
			cap.radius = randf_range(0.55, 0.95)
			cap.height = cap.radius * 0.8
			cap.radial_segments = 8
			cap.rings = 4
			cap.material = mat
			_add_mesh(root, cap, Vector3(0.0, stem.height + 0.1, 0.0))
		"crystal":
			for j in 3:
				var shard := CylinderMesh.new()
				shard.top_radius = 0.02
				shard.bottom_radius = randf_range(0.22, 0.45)
				shard.height = randf_range(1.4, 3.2)
				shard.radial_segments = 5
				shard.material = mat
				var a := TAU * float(j) / 3.0
				_add_mesh(root, shard, Vector3(cos(a) * 0.35, shard.height * 0.5, sin(a) * 0.35))
		"ruin":
			for j in 2:
				var pillar := BoxMesh.new()
				pillar.size = Vector3(0.55, randf_range(2.4, 3.8), 0.55)
				pillar.material = mat
				_add_mesh(root, pillar, Vector3(-0.9 + 1.8 * j, pillar.size.y * 0.5, 0.0))
			var lintel := BoxMesh.new()
			lintel.size = Vector3(2.8, 0.45, 0.65)
			lintel.material = mat
			_add_mesh(root, lintel, Vector3(0.0, 3.7, 0.0))
		"ice":
			for j in 2:
				var spike := CylinderMesh.new()
				spike.top_radius = 0.02
				spike.bottom_radius = randf_range(0.3, 0.65)
				spike.height = randf_range(1.8, 3.5)
				spike.radial_segments = 5
				spike.material = mat
				_add_mesh(root, spike, Vector3(-0.35 + 0.7 * j, spike.height * 0.5, 0.0))
		_:
			var rock := BoxMesh.new()
			var s := randf_range(0.5, 1.4)
			rock.size = Vector3(s, s * 0.8, s)
			rock.material = mat
			_add_mesh(root, rock, Vector3(0.0, s * 0.4, 0.0))
	return root


func _add_mesh(root: Node3D, mesh: PrimitiveMesh, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	root.add_child(mi)


func _toon_mat(c: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://fx/toon.gdshader")
	mat.set_shader_parameter("base_color", c)
	return mat


func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	light.light_energy = 1.1
	light.shadow_enabled = GameState.shadows
	if GameState.shadows:
		light.directional_shadow_max_distance = 85.0
		light.shadow_bias = 0.04
	add_child(light)
	_light = light

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.08, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.75)
	env.ambient_light_energy = 0.6
	env.fog_enabled = false
	env.fog_density = 0.0
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_terrain() -> void:
	_terrain = Node3D.new()
	_terrain.set_script(load("res://world/terrain.gd"))
	add_child(_terrain)
	_terrain.call("build")
	GameState.terrain = _terrain


func _build_weather() -> void:
	_weather = Node3D.new()
	_weather.set_script(load("res://world/weather.gd"))
	add_child(_weather)
	_weather.call("setup", _terrain)
	_weather.connect("flash", _on_weather_flash)


func _apply_quality() -> void:
	## Calidad por tier (roadmap 5.2): resolución 3D, MSAA, sombras, glow y distancia.
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = GameState.render_scale
		vp.msaa_3d = Viewport.MSAA_2X if GameState.device_tier == "alto" else Viewport.MSAA_DISABLED
	if cam != null:
		cam.far = GameState.camera_far
	if _weather != null:
		_weather.call("apply_quality")
	if _env != null:
		_env.glow_enabled = GameState.device_tier == "alto"
		if _env.glow_enabled:
			_env.glow_intensity = 0.6
			_env.glow_bloom = 0.08


## Aplicar calidad en caliente desde el menú de opciones (roadmap 5.4).
func apply_quality_live() -> void:
	_apply_quality()
	if _light != null:
		_light.shadow_enabled = GameState.shadows
	if _weather != null:
		_weather.call("apply_quality")
	if not _biome_cur.is_empty() and _props_holder != null:
		_prop_rebuild(_biome_cur)
		_apply_weather(_biome_cur)


func _build_player() -> Node3D:
	var p := Node3D.new()
	p.set_script(load("res://player/player.gd"))

	var holder := Node3D.new()
	holder.name = "Model"
	p.add_child(holder)

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.6
	var pmat := ShaderMaterial.new()
	pmat.shader = load("res://fx/toon.gdshader")
	pmat.set_shader_parameter("base_color", Color(0.95, 0.8, 0.55))
	capsule.material = pmat
	var cmi := MeshInstance3D.new()
	cmi.mesh = capsule
	cmi.position.y = 0.8
	holder.add_child(cmi)

	# marcador de frente
	var nose := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.22, 0.5)
	var nmat := StandardMaterial3D.new()
	nmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nmat.albedo_color = Color(1.0, 0.45, 0.35)
	box.material = nmat
	nose.mesh = box
	nose.position = Vector3(0, 1.1, -0.55)
	holder.add_child(nose)

	add_child(p)
	return p


func _spawn_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.position = Vector3.ZERO + CAM_OFFSET
	add_child(cam)
	cam.look_at_from_position(cam.position, Vector3.ZERO + Vector3(0, 0.5, 0))
	cam.current = true
	GameState.cam_ref = cam
