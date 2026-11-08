## HostileProjectiles — proyectiles de enemigos a distancia.
## Autoload Node3D. Pool en un MultiMesh (1 draw call) y colisión simple contra
## el jugador. Los proyectiles siguen la altura del terreno para no atravesar
## colinas y usan el color del atacante (orbe de niebla, ácido, arena, etc.).
extends Node3D

const MAX_PROJECTILES := 260
const PROJECTILE_RADIUS := 0.18
const WORLD_LIMIT := 55.0

var total_fired := 0

var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _dmg := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _color: Array[Color] = []
var _alive: Array[int] = []
var _free: Array[int] = []
var _max_used := 0


func _ready() -> void:
	_pos.resize(MAX_PROJECTILES)
	_vel.resize(MAX_PROJECTILES)
	_life.resize(MAX_PROJECTILES)
	_dmg.resize(MAX_PROJECTILES)
	_radius.resize(MAX_PROJECTILES)
	_color.resize(MAX_PROJECTILES)
	for i in MAX_PROJECTILES:
		_color[i] = Color.WHITE

	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.30
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mesh.material = mat

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = mesh
	_mm.instance_count = MAX_PROJECTILES
	_mm.visible_instance_count = 0
	for i in MAX_PROJECTILES:
		_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, -100.0, 0.0)))
		_mm.set_instance_color(i, Color.WHITE)

	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)

	GameState.run_reset.connect(reset)
	GameState.run_started.connect(reset)


## Dispara un proyectil hostil. `dir` solo usa el plano XZ; la altura se ajusta
## al terreno en cada tick. Devuelve el índice del pool o -1 si está lleno.
func fire(
	start: Vector3,
	dir: Vector3,
	speed: float,
	dmg: float,
	life: float,
	color: Color,
	radius: float = PROJECTILE_RADIUS
) -> int:
	if not GameState.run_active:
		return -1
	if _alive.size() >= MAX_PROJECTILES:
		return -1
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.001:
		flat = Vector3.FORWARD
	var b := -1
	if not _free.is_empty():
		b = int(_free.pop_back())
	else:
		b = _max_used
		_max_used += 1
	var gy := _terrain_y(start.x, start.z)
	_pos[b] = Vector3(start.x, gy + 0.9, start.z)
	_vel[b] = flat.normalized() * speed
	_life[b] = life
	_dmg[b] = dmg
	_radius[b] = radius
	_color[b] = color
	_mm.set_instance_color(b, color)
	_alive.append(b)
	total_fired += 1
	return b


func _physics_process(dt: float) -> void:
	if not GameState.run_active:
		return
	var p = EnemyManager.player
	var i := 0
	while i < _alive.size():
		var b := _alive[i]
		_pos[b] += _vel[b] * dt
		_life[b] -= dt
		_pos[b].y = _terrain_y(_pos[b].x, _pos[b].z) + 0.9
		var dead := _life[b] <= 0.0
		if absf(_pos[b].x) > WORLD_LIMIT or absf(_pos[b].z) > WORLD_LIMIT:
			dead = true
		if not dead and p != null:
			var dx: float = _pos[b].x - p.position.x
			var dz: float = _pos[b].z - p.position.z
			var dy: float = absf(_pos[b].y - (p.position.y + 0.8))
			var reach := float(_radius[b]) + 0.55
			if dx * dx + dz * dz <= reach * reach and dy < 1.25:
				GameState.take_damage(_dmg[b])
				DeathFx.spawn(_pos[b], _color[b], false)
				AudioManager.play_sfx("hit", 0.72)
				dead = true
		if dead:
			_pos[b] = Vector3(0.0, -100.0, 0.0)
			_mm.set_instance_transform(b, Transform3D(Basis.IDENTITY, _pos[b]))
			_free.append(b)
			_alive[i] = _alive[_alive.size() - 1]
			_alive.remove_at(_alive.size() - 1)
		else:
			_mm.set_instance_transform(b, Transform3D(Basis.IDENTITY, _pos[b]))
			i += 1
	_mm.visible_instance_count = _max_used


func active_count() -> int:
	return _alive.size()


func reset() -> void:
	_alive.clear()
	_free.clear()
	_max_used = 0
	total_fired = 0
	if _mm != null:
		_mm.visible_instance_count = 0


func _terrain_y(x: float, z: float) -> float:
	if GameState.terrain != null:
		return float(GameState.terrain.call("height_at", x, z))
	return 0.0
