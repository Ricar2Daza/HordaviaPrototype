## Hazards ambientales (roadmap 3.3): lava/veneno (daño continuo), niebla/escarcha
## (ralentizan). Se regeneran por bioma vía main._apply_biome().
extends Node3D

var terrain = null
var _zones: Array = []   # {node, pos, radius, kind}


func setup(t) -> void:
	terrain = t


func spawn_for_biome(b: Dictionary) -> void:
	for z in _zones:
		if is_instance_valid(z.get("node")):
			(z["node"] as Node).queue_free()
	_zones.clear()
	var kind := String(b.get("hazard", "lava"))
	var count := int(b.get("hazard_count", 4))
	for i in count:
		var ang := randf() * TAU
		var dist := randf_range(8.0, 31.0)
		var pos := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		pos.y = float(terrain.call("height_at", pos.x, pos.z)) if terrain != null else 0.0
		var radius := randf_range(2.4, 4.2)
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius
		cyl.bottom_radius = radius
		cyl.height = 0.08
		cyl.radial_segments = 20
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		match kind:
			"lava":
				mat.albedo_color = Color(1.0, 0.32, 0.08, 0.55)
			"poison":
				mat.albedo_color = Color(0.35, 0.85, 0.20, 0.42)
			"ice":
				mat.albedo_color = Color(0.55, 0.82, 1.0, 0.42)
			_:
				mat.albedo_color = Color(0.55, 0.35, 0.95, 0.40)
		cyl.material = mat
		mi.mesh = cyl
		mi.position = pos + Vector3(0.0, 0.05, 0.0)
		add_child(mi)
		_zones.append({"node": mi, "pos": pos, "radius": radius, "kind": kind})
	if GameState.debug_auto_upgrade:
		print("SMOKE_HAZARDS zones=%d kind=%s" % [_zones.size(), kind])


func _physics_process(dt: float) -> void:
	GameState.slow_mult = 1.0
	var p = EnemyManager.player
	if p == null or not GameState.run_active:
		return
	var px: float = p.global_position.x
	var pz: float = p.global_position.z
	for z in _zones:
		var pos: Vector3 = z["pos"]
		var r := float(z["radius"])
		var dx := px - pos.x
		var dz := pz - pos.z
		if dx * dx + dz * dz <= r * r:
			match String(z["kind"]):
				"slow":
					GameState.slow_mult = 0.55
				"ice":
					GameState.slow_mult = 0.45
				"poison":
					GameState.take_dot(4.5 * dt)
				_:
					GameState.take_dot(9.0 * dt)
