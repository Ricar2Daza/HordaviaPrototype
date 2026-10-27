## Pickups de mapa (roadmap 2.7): cura, imán temporal y bomba.
## Caen de enemigos (2 %) y de élites (cofre aparte). Viven 25 s y se recogen al pasar.
extends Node3D

const LIFETIME := 25.0
const PICK_RADIUS := 1.7

var _items: Array = []   # {node, t, kind, base_y}


func spawn_random(pos: Vector3) -> void:
	var kinds := ["heal", "magnet", "bomb"]
	spawn(String(kinds[randi() % kinds.size()]), pos)


func spawn(kind: String, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var color := Color(0.35, 1.0, 0.5)
	match kind:
		"magnet":
			color = Color(0.35, 0.7, 1.0)
		"bomb":
			color = Color(1.0, 0.45, 0.18)
		_:
			color = Color(0.35, 1.0, 0.5)
	var mesh: PrimitiveMesh
	if kind == "heal":
		var cap := CapsuleMesh.new()
		cap.radius = 0.22
		cap.height = 0.62
		mesh = cap
	elif kind == "bomb":
		var sph := SphereMesh.new()
		sph.radius = 0.3
		sph.height = 0.6
		mesh = sph
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.5, 0.5)
		mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.material = mat
	mi.mesh = mesh
	var gy := pos.y
	if GameState.terrain != null:
		gy = float(GameState.terrain.call("height_at", pos.x, pos.z))
	mi.position = Vector3(pos.x, gy + 0.5, pos.z)
	add_child(mi)
	_items.append({"node": mi, "t": 0.0, "kind": kind, "base_y": gy + 0.5})


func _physics_process(dt: float) -> void:
	var p = EnemyManager.player
	for it in _items.duplicate():
		var node: MeshInstance3D = it["node"]
		if not is_instance_valid(node):
			_items.erase(it)
			continue
		it["t"] = float(it["t"]) + dt
		var bob := float(it["t"])
		node.position.y = float(it["base_y"]) + 0.18 * sin(bob * 3.2)
		node.rotation.y += dt * 2.0
		if float(it["t"]) > LIFETIME:
			_items.erase(it)
			node.queue_free()
			continue
		if p == null or not GameState.run_active:
			continue
		if node.position.distance_to(p.position) < PICK_RADIUS:
			_apply(String(it["kind"]), node.position)
			_items.erase(it)
			node.queue_free()


func _apply(kind: String, pos: Vector3) -> void:
	if GameState.debug_auto_upgrade:
		print("SMOKE_PICKUP kind=%s" % kind)
	match kind:
		"heal":
			GameState.heal(25.0)
			DeathFx.spawn(pos, Color(0.35, 1.0, 0.5), false)
		"magnet":
			GameState.magnet_boost(20.0, 6.0)
			DeathFx.spawn(pos, Color(0.35, 0.7, 1.0), false)
		"bomb":
			EnemyManager.damage_all(80.0)
			DeathFx.spawn(pos, Color(1.0, 0.45, 0.18), true)
			AudioManager.play_sfx("boom", 0.6)
	AudioManager.play_sfx("pickup")


func clear() -> void:
	for it in _items:
		if is_instance_valid(it.get("node")):
			(it["node"] as Node).queue_free()
	_items.clear()
