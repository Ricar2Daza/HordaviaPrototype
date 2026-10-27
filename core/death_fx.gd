## DeathFx — explosión voxel al morir un enemigo (roadmap 1.4).
## Autoload Node3D. Pool de 24 CPUParticles3D one-shot; recicla el más antiguo.
extends Node3D

const MAX_POOLS := 24

var _pool: Array[CPUParticles3D] = []
var _next := 0


func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.14, 0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	for i in maxi(int(MAX_POOLS * GameState.fx_mult), 8):
		var p := CPUParticles3D.new()
		p.mesh = mesh
		p.amount = maxi(int(16 * GameState.fx_mult), 6)
		p.lifetime = 0.55
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		p.direction = Vector3.ZERO
		p.spread = 180.0
		p.gravity = Vector3(0, -16, 0)
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 8.5
		p.damping_min = 1.0
		p.damping_max = 2.0
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.5
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.3
		p.visible = false
		add_child(p)
		_pool.append(p)


func spawn(pos: Vector3, color: Color, big: bool = false) -> void:
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.position = pos + Vector3(0.0, 0.5, 0.0)
	p.color = color
	if big:
		p.scale_amount_max = 2.2
		p.initial_velocity_max = 11.0
		p.amount = maxi(int(24 * GameState.fx_mult), 8)
	else:
		p.scale_amount_max = 1.5
		p.initial_velocity_max = 8.5
		p.amount = maxi(int(16 * GameState.fx_mult), 6)
	p.visible = true
	p.restart()
