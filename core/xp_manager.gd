## XPManager — orbes de XP en pool con imán (guía §3.5).
## Autoload Node3D. Cap duro de 150 orbes; los más antiguos se reciclan.
extends Node3D

const MAX_ORBS := 150
const COLLECT_DIST := 0.7

var _pool: Array[Node3D] = []
var _values: Array[float] = []
var _alive: Array[int] = []
var _free: Array[int] = []


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 1.0, 0.5)
	mesh.material = mat

	for i in MAX_ORBS:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visible = false
		mi.position = Vector3(0, -50, 0)
		add_child(mi)
		_pool.append(mi)
		_values.append(0.0)
	GameState.run_reset.connect(reset)
	GameState.run_started.connect(reset)


func spawn_orb(pos: Vector3, value: int) -> void:
	var idx := -1
	if not _free.is_empty():
		idx = int(_free.pop_back())
	elif _alive.size() > 0:
		# Cap alcanzado: recicla orbe más antiguo (primer alive) si jugador se aleja
		idx = _alive[0]
	else:
		return
	if idx < 0:
		return
	var gy := 0.4
	if GameState.terrain != null:
		gy = float(GameState.terrain.call("height_at", pos.x, pos.z)) + 0.4
	_pool[idx].position = Vector3(pos.x, gy, pos.z)
	_pool[idx].visible = true
	_values[idx] = float(maxi(value, 1))
	if not _alive.has(idx):
		_alive.append(idx)


func _physics_process(dt: float) -> void:
	if not GameState.run_active or EnemyManager.player == null:
		return
	var target := EnemyManager.player.position
	var magnet := GameState.magnet + GameState.magnet_bonus
	var i := 0
	while i < _alive.size():
		var idx := _alive[i]
		var orb := _pool[idx]
		var d3 := target - orb.position
		d3.y = 0.0
		var d := d3.length()
		if d < COLLECT_DIST:
			GameState.add_xp(int(_values[idx]))
			AudioManager.play_sfx("pickup", randf_range(0.95, 1.15))
			_pool[idx].visible = false
			_pool[idx].position = Vector3(0, -50, 0)
			_free.append(idx)
			_alive[i] = _alive[_alive.size() - 1]
			_alive.remove_at(_alive.size() - 1)
		elif d < magnet + 4.0:
			orb.position += (d3 / maxf(d, 0.01)) * 22.0 * dt
			if GameState.terrain != null:
				orb.position.y = float(GameState.terrain.call("height_at", orb.position.x, orb.position.z)) + 0.4
			i += 1
		else:
			i += 1


func reset() -> void:
	_alive.clear()
	_free.clear()
	for orb in _pool:
		orb.visible = false
		orb.position = Vector3(0, -50, 0)
