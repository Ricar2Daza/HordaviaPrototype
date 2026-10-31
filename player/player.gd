## Player — movimiento táctil + teclado, stats de GameState.
## Nodo simple (sin física de colisión): daño por contacto se resuelve en EnemyManager.
extends Node3D

const ARENA := 35.5

# Salto/dash (roadmap 1.1): coyote 0.12 s, dash 0.22 s + i-frames, cooldown 3 s
const GRAVITY := 24.0
const JUMP_V := 9.0
const COYOTE := 0.12
const DASH_CD := 3.0
const DASH_TIME := 0.22
const DASH_MULT := 3.0

var _weapons_holder: Node3D
var _facing := 0.0
var _vy := 0.0
var _coyote := 0.0
var _dash_t := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _jump_prev := false
var _dash_prev := false
var _smoke_next_action := 2.5
var _model: Node3D = null
var _g := 0.0   # altura del terreno bajo el player (procedural)


func _ready() -> void:
	_weapons_holder = Node3D.new()
	add_child(_weapons_holder)
	_rebuild_weapons()
	GameState.upgrades_changed.connect(_rebuild_weapons)
	GameState.run_reset.connect(_on_reset)
	# Los botones táctiles y el teclado disparan salto/dash:
	JoystickLayer.jump_requested.connect(jump)
	JoystickLayer.dash_requested.connect(dash)
	# El SpawnDirector/HUD/EnemyManager necesitan conocernos:
	EnemyManager.player = self
	_model = get_node_or_null("Model")


func _on_reset() -> void:
	position = Vector3.ZERO
	_vy = 0.0
	_coyote = 0.0
	_dash_t = 0.0
	_dash_cd = 0.0
	_smoke_next_action = 2.5
	_g = 0.0
	rotation.y = 0.0
	_facing = 0.0


func _terrain_h() -> float:
	if GameState.terrain != null:
		return float(GameState.terrain.call("height_at", position.x, position.z))
	return 0.0


func is_grounded() -> bool:
	return position.y <= _g + 0.03


## Convierte entrada 2D (joystick/teclado, pantalla-arriba = -y) a dirección de
## mundo RELATIVA A LA CÁMARA: W/joystick-arriba = alejarse de la cámara.
func _input_dir(v: Vector2) -> Vector3:
	var f := Vector3.FORWARD
	if GameState.cam_ref != null:
		var bz: Vector3 = GameState.cam_ref.global_basis.z
		f = -Vector3(bz.x, 0.0, bz.z)
		if f.length() < 0.001:
			f = Vector3.FORWARD
		f = f.normalized()
	var right := Vector3(-f.z, 0.0, f.x)   # derecha en pantalla
	return (f * (-v.y) + right * v.x)


func jump() -> void:
	if not GameState.run_active:
		return
	if is_grounded() or _coyote > 0.0:
		_vy = JUMP_V
		_coyote = 0.0
		AudioManager.play_sfx("jump")
		GameState.haptic(0.2, 16)


func dash() -> void:
	if not GameState.run_active or _dash_cd > 0.0:
		return
	var dir := _input_dir(JoystickLayer.move_vector)
	if dir.length() < 0.05:
		dir = Vector3(sin(_facing), 0.0, cos(_facing))
	_dash_dir = dir.normalized()
	_dash_t = DASH_TIME
	_dash_cd = DASH_CD
	AudioManager.play_sfx("dash")
	GameState.haptic(0.45, 28)
	# i-frames breves al hacer dash (sinergia con el gracia de contacto):
	GameState.damage_grace = maxf(GameState.damage_grace, 0.35)


func _physics_process(delta: float) -> void:
	if not GameState.run_active:
		return
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_g = _terrain_h()
	# JoystickLayer centraliza teclado, gamepad y táctil en move_vector.
	var v := JoystickLayer.move_vector
	if v.length() < 0.05:
		v = Vector2.ZERO
	# Salto/dash por borde de pulsación: funciona con teclado y mando sin que
	# un botón de UI con foco consuma el evento (Space también es ui_accept).
	var jump_down := Input.is_action_pressed("jump")
	if jump_down and not _jump_prev:
		jump()
	_jump_prev = jump_down
	var dash_down := Input.is_action_pressed("dash")
	if dash_down and not _dash_prev:
		dash()
	_dash_prev = dash_down
	var dir := _input_dir(v)
	if dir.length() > 1.0:
		dir = dir.normalized()
	# Modo smoke: kiting no predecible + ejercita salto y dash por turnos
	if GameState.debug_auto_upgrade:
		var t := GameState.run_time
		var a := t * 1.6
		if int(t / 6.0) % 2 == 1:
			a = -a
		var target := Vector3(cos(a) * 13.0 + sin(t * 0.7) * 4.0, 0.0, sin(a) * 13.0 + cos(t * 0.9) * 4.0)
		dir = (target - position)
		if dir.length() > 0.05:
			dir = dir.normalized()
		if t >= _smoke_next_action:
			_smoke_next_action = t + 4.0
			if is_grounded():
				jump()
			elif _dash_cd <= 0.0:
				dash()
	# --- Movimiento horizontal ---
	var horiz := Vector3.ZERO
	if _dash_t > 0.0:
		_dash_t -= delta
		horiz = _dash_dir * GameState.move_speed * DASH_MULT
	else:
		horiz = dir * GameState.move_speed * GameState.slow_mult * GameState.weather_speed_mult
	# --- Coyote antes del desplazamiento ---
	if is_grounded():
		_coyote = COYOTE
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	# --- Aplicar desplazamiento ---
	position += horiz * delta
	position.x = clampf(position.x, -ARENA, ARENA)
	position.z = clampf(position.z, -ARENA, ARENA)
	_g = _terrain_h()
	# --- Vertical (escalones + gravedad + aterrizaje) ---
	if position.y <= _g and _vy <= 0.0:
		# apoyado o caminando a un escalón más alto: snap (subir/bajar escalones)
		if _vy < -3.0:
			_squash()
		position.y = _g
		_vy = 0.0
	else:
		_vy -= GRAVITY * delta
		position.y += _vy * delta
		if position.y <= _g and _vy <= 0.0:
			if _vy < -3.0:
				_squash()
			position.y = _g
			_vy = 0.0
	if dir.length() > 0.05:
		_facing = atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, _facing, 12.0 * delta)


func _squash() -> void:
	if _model == null:
		return
	_model.scale = Vector3(1.15, 0.8, 1.15)
	var tw := create_tween()
	tw.tween_property(_model, "scale", Vector3.ONE, 0.18)


func _rebuild_weapons() -> void:
	var existing := {}
	for c in _weapons_holder.get_children():
		existing[String(c.get_meta("wid", ""))] = true
	for id in GameState.weapons:
		if not existing.has(id):
			var w := Node3D.new()
			w.set_script(load("res://weapons/weapon_instance.gd"))
			w.set_meta("wid", id)
			w.setup(id)          # antes de add_child: _ready() necesita weapon_id
			_weapons_holder.add_child(w)
	# Reset de run: las armas que ya no se eligen deben desaparecer de verdad
	var to_remove: Array = []
	for c in _weapons_holder.get_children():
		if not GameState.weapons.has(String(c.get_meta("wid", ""))):
			to_remove.append(c)
	for c in to_remove:
		_weapons_holder.remove_child(c)
		c.free()


func get_weapon_holder() -> Node3D:
	return _weapons_holder
