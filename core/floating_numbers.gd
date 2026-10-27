## FloatingNumbers — números de daño flotantes billboarding (roadmap 1.3).
## Autoload Node3D. Pool de 40 Label3D; recicla el más antiguo al llenarse.
extends Node3D

const MAX_NUMBERS := 40
const RISE_SPEED := 1.6
const LIFE := 0.65

var _pool: Array[Label3D] = []
var _t := PackedFloat64Array()
var _base := PackedVector3Array()
var _alive: Array[int] = []
var _free: Array[int] = []


func _ready() -> void:
	for i in MAX_NUMBERS:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 64
		l.pixel_size = 0.008
		l.outline_size = 14
		l.outline_modulate = Color(0.06, 0.05, 0.08, 0.95)
		l.modulate = Color(1, 1, 1, 1)
		l.visible = false
		add_child(l)
		_pool.append(l)
	_t.resize(MAX_NUMBERS)
	_base.resize(MAX_NUMBERS)
	GameState.run_reset.connect(reset)


func spawn(pos: Vector3, dmg: float, big: bool = false) -> void:
	var idx := -1
	if not _free.is_empty():
		idx = int(_free.pop_back())
	elif not _alive.is_empty():
		idx = _alive[0]  # recicla el más antiguo
		_alive.remove_at(0)
	if idx < 0:
		return
	var l := _pool[idx]
	l.text = str(int(round(dmg)))
	if big:
		l.modulate = Color(1.0, 0.55, 0.2, 1.0)
		l.font_size = 96
	else:
		l.modulate = Color(1.0, 1.0, 1.0, 1.0)
		l.font_size = 64
	_base[idx] = pos + Vector3(randf_range(-0.25, 0.25), 1.5, randf_range(-0.25, 0.25))
	l.position = _base[idx]
	l.rotation = Vector3.ZERO
	_t[idx] = 0.0
	l.visible = true
	if not _alive.has(idx):
		_alive.append(idx)


func _process(dt: float) -> void:
	if _alive.is_empty():
		return
	var i := 0
	while i < _alive.size():
		var idx := _alive[i]
		_t[idx] += dt
		var frac := float(_t[idx]) / LIFE
		if frac >= 1.0:
			_pool[idx].visible = false
			_free.append(idx)
			_alive[i] = _alive[_alive.size() - 1]
			_alive.remove_at(_alive.size() - 1)
		else:
			var l := _pool[idx]
			l.position = _base[idx] + Vector3(0.0, RISE_SPEED * float(_t[idx]), 0.0)
			l.modulate.a = 1.0 - frac
			i += 1


func reset() -> void:
	_alive.clear()
	_free.clear()
	for l in _pool:
		l.visible = false
