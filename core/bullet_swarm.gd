## BulletSwarm — proyectiles en un solo MultiMesh (guía §3.2).
## Regula el presupuesto: si está lleno, IGNORA el disparo (culling duro del prototipo).
extends Node3D

const MAX_BULLETS := 1500
const BULLET_RADIUS := 0.25
const WORLD_LIMIT := 80.0

var _mm: MultiMesh
var _pos := PackedVector3Array()
var _prev := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _dmg := PackedFloat32Array()
var _pierce := PackedInt32Array()
var _hits: Array = []            # por bala: {instance_id: true} (solo perforantes)
var _alive: Array[int] = []
var _free: Array[int] = []
var _max_used := 0
var _mmi_ref: MultiMeshInstance3D = null


func _ready() -> void:
	_pos.resize(MAX_BULLETS)
	_vel.resize(MAX_BULLETS)
	_life.resize(MAX_BULLETS)
	_dmg.resize(MAX_BULLETS)
	_pierce.resize(MAX_BULLETS)
	_prev.resize(MAX_BULLETS)
	_hits.resize(MAX_BULLETS)
	for i in MAX_BULLETS:
		_hits[i] = {}

	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 8
	mesh.rings = 4

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.4)
	mesh.material = mat

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = MAX_BULLETS
	_mm.visible_instance_count = 0

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.set_as_top_level(true)
	add_child(mmi)
	_mmi_ref = mmi


func _physics_process(dt: float) -> void:
	if _alive.is_empty():
		if _mm.visible_instance_count != 0:
			_mm.visible_instance_count = 0
		return
	var i := 0
	while i < _alive.size():
		var b := _alive[i]
		_prev[b] = _pos[b]
		_pos[b] += _vel[b] * dt
		_life[b] -= dt
		var dead := _life[b] <= 0.0
		if not dead:
			var p := _pos[b]
			dead = absf(p.x) > WORLD_LIMIT or absf(p.z) > WORLD_LIMIT
		if not dead and _pierce[b] > 0:
			var hit := EnemyManager.hit_sweep_ex(_prev[b], _pos[b], BULLET_RADIUS, _dmg[b], _hits[b])
			if not hit.is_empty():
				(_hits[b] as Dictionary)[int(hit["id"])] = true
				if _pierce[b] <= 1:
					dead = true
				else:
					_pierce[b] -= 1
		elif not dead and EnemyManager.hit_sweep(_prev[b], _pos[b], BULLET_RADIUS, _dmg[b]):
			dead = true
		if dead:
			_pos[b] = Vector3(0.0, -100.0, 0.0)  # saca el sprite de cámara al reciclar
			_free.append(b)
			_alive[i] = _alive[_alive.size() - 1]
			_alive.remove_at(_alive.size() - 1)
		else:
			i += 1
	_flush_views()


func spawn(start: Vector3, dir: Vector3, speed: float, dmg: float, life: float, pierce: int = 0) -> int:
	if _alive.size() >= mini(MAX_BULLETS, GameState.max_bullets):
		return -1
	var b := -1
	if not _free.is_empty():
		b = int(_free.pop_back())
	else:
		b = _max_used
		_max_used += 1
	_pos[b] = start
	_vel[b] = dir.normalized() * speed
	_life[b] = life
	_dmg[b] = dmg
	_pierce[b] = maxi(pierce, 0)
	(_hits[b] as Dictionary).clear()
	_alive.append(b)
	return b


func _flush_views() -> void:
	for idx in _alive.size():
		var b := _alive[idx]
		_mm.set_instance_transform(b, Transform3D(Basis.IDENTITY, _pos[b]))
	_mm.visible_instance_count = _max_used + 1


func active_count() -> int:
	return _alive.size()


func reset() -> void:
	_alive.clear()
	_free.clear()
	_max_used = 0
	if _mmi_ref != null:
		_mmi_ref.multimesh.visible_instance_count = 0
