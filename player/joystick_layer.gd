## JoystickLayer — joystick virtual flotante (guía §3.1).
## Autoload CanvasLayer. Empieza donde tocas, con fallback teclado/gamepad.
## El layout escala con la pantalla y respeta el safe area (notch).
extends CanvasLayer

signal moved(vec: Vector2)
signal jump_requested
signal dash_requested

const RADIUS := 110.0
const DEADZONE := 0.25
const BTN_HIT := 92.0
const BTN_RADIUS := 62.0
const UI_SCALE_MIN := 0.65
const UI_SCALE_MAX := 1.15

var move_vector := Vector2.ZERO

var _touch_idx := -1
var _btn_touch := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _draw_root: Control
var _dash_btn := Vector2.ZERO
var _jump_btn := Vector2.ZERO
var _ui_scale := 1.0
var _joy_radius := RADIUS
var _btn_radius := BTN_RADIUS
var _btn_hit := BTN_HIT
var _layout_reported := false


func _ready() -> void:
	layer = 5
	_draw_root = Control.new()
	_draw_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_root.draw.connect(_on_draw)
	add_child(_draw_root)
	_draw_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	call_deferred("_update_layout")


func _update_layout() -> void:
	## Calcula tamaño/posición una vez por frame de dibujo. Así 5", 6.5" y
	## tablet comparten la misma lógica y los botones no se salen del notch.
	var sz := _layout_size()
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var ins := _safe_insets()
	_ui_scale = clampf(minf(sz.x / 1280.0, sz.y / 720.0), UI_SCALE_MIN, UI_SCALE_MAX)
	_joy_radius = RADIUS * _ui_scale
	_btn_radius = BTN_RADIUS * _ui_scale
	_btn_hit = BTN_HIT * _ui_scale
	var right := 108.0 * _ui_scale + ins.x
	_dash_btn = Vector2(sz.x - right, sz.y - 118.0 * _ui_scale - ins.y)
	_jump_btn = Vector2(sz.x - right, sz.y - 258.0 * _ui_scale - ins.y)
	var inside := (_dash_btn.x - _btn_radius >= 0.0 and _dash_btn.y - _btn_radius >= 0.0
			and _dash_btn.x + _btn_radius <= sz.x and _dash_btn.y + _btn_radius <= sz.y
			and _jump_btn.x - _btn_radius >= 0.0 and _jump_btn.y - _btn_radius >= 0.0
			and _jump_btn.x + _btn_radius <= sz.x and _jump_btn.y + _btn_radius <= sz.y)
	if not inside:
		push_error("LAYOUT fuera de pantalla: viewport=%s dash=%s jump=%s" % [str(sz), str(_dash_btn), str(_jump_btn)])
	if OS.get_environment("HORDAVIA_LAYOUT_TEST") == "1" and not _layout_reported:
		_layout_reported = true
		print("LAYOUT viewport=%s scale=%.2f dash=%s jump=%s ok=%s" % [
			str(sz), _ui_scale, str(_dash_btn), str(_jump_btn), str(inside),
		])


func _layout_size() -> Vector2:
	## Hook de QA: permite simular 5"/6.5"/tablet en headless sin display.
	var forced := OS.get_environment("HORDAVIA_LAYOUT_SIZE")
	if not forced.is_empty():
		var parts := forced.split("x")
		if parts.size() == 2:
			return Vector2(float(parts[0]), float(parts[1]))
	return _draw_root.size


func _on_draw() -> void:
	_update_layout()
	if _touch_idx == -1:
		_draw_buttons(_btn_touch != -1)
		return
	_draw_root.draw_circle(_origin, _joy_radius, Color(1, 1, 1, 0.08))
	_draw_root.draw_circle(_origin, _joy_radius * 0.92 + 2, Color(1, 1, 1, 0.12), false, 3.0)
	_draw_root.draw_circle(_knob, 34.0 * _ui_scale, Color(1, 1, 1, 0.35))
	_draw_root.draw_circle(_knob, 30.0 * _ui_scale, Color(1, 1, 1, 0.6))
	_draw_buttons(true)


func _safe_insets() -> Vector2:
	## Insets derecho/inferior para no tapar botones con el notch.
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return Vector2.ZERO
	var sz := _draw_root.size
	var right := maxf(float(win.x - safe.position.x - safe.size.x) * sz.x / float(win.x), 0.0)
	var bottom := maxf(float(win.y - safe.position.y - safe.size.y) * sz.y / float(win.y), 0.0)
	return Vector2(right, bottom)


func _draw_buttons(active: bool) -> void:
	var a := 0.55 if active else 0.3
	_draw_root.draw_circle(_dash_btn, _btn_radius, Color(0.4, 0.75, 1.0, a))
	_draw_root.draw_circle(_dash_btn, _btn_radius, Color(1, 1, 1, a + 0.1), false, 3.0)
	_draw_root.draw_circle(_jump_btn, _btn_radius, Color(0.45, 1.0, 0.6, a))
	_draw_root.draw_circle(_jump_btn, _btn_radius, Color(1, 1, 1, a + 0.1), false, 3.0)
	var font := ThemeDB.fallback_font
	var fs := int(round(22.0 * _ui_scale))
	var w := _btn_radius * 2.0
	var dy := fs * 0.32
	_draw_root.draw_string(font, _dash_btn + Vector2(-_btn_radius, dy), "DASH", HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(0.05, 0.05, 0.1))
	_draw_root.draw_string(font, _jump_btn + Vector2(-_btn_radius, dy), "SALTO", HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(0.05, 0.05, 0.1))


func _process(_dt: float) -> void:
	# Teclado y gamepad comparten acciones; el táctil sigue usando el joystick.
	var kb := Input.get_vector("move_left", "move_right", "move_up", "move_down", DEADZONE)
	if kb.length() > 0.05:
		move_vector = kb
		_touch_idx = -1  # teclado/mando tienen prioridad en escritorio
	elif _mouse_look():
		# El ratón orbita la cámara: no debe quedar un toque/joystick pegado.
		_touch_idx = -1
		_btn_touch = -1
		move_vector = Vector2.ZERO
	elif _touch_idx == -1:
		move_vector = Vector2.ZERO  # soltar WASD no debe dejar al jugador andando
	_draw_root.queue_redraw()


func _mouse_look() -> bool:
	## Modo cámara "mouse" con puntero capturado en escritorio (sin táctil real).
	return (GameState.camera_mode == "mouse"
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			and not DisplayServer.is_touchscreen_available())


func _unhandled_input(ev: InputEvent) -> void:
	# En modo cámara "mouse" el ratón orbita la cámara: no debe arrastrar el
	# joystick (touch emulado). En táctil real seguimos aceptando el joystick.
	if _mouse_look():
		return
	_update_layout()
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if ev.index == _touch_idx:
				return
			# Prioridad: botones (dash/salto) antes que el joystick
			if _check_button(ev.position, ev.index):
				return
			if _touch_idx == -1 and _btn_touch == -1:
				_touch_idx = ev.index
				_origin = ev.position
				_knob = ev.position
		elif ev.index == _touch_idx:
			_touch_idx = -1
			_move(Vector2.ZERO)
		elif ev.index == _btn_touch:
			_btn_touch = -1
	elif ev is InputEventScreenDrag and ev.index == _touch_idx:
		var rel: Vector2 = ev.position - _origin
		if rel.length() > DEADZONE * _joy_radius:
			var v: Vector2 = rel / _joy_radius
			_move(v.limit_length(1.0))
		else:
			_move(Vector2.ZERO)
		_knob = _origin + move_vector * _joy_radius


func _check_button(pos: Vector2, idx: int) -> bool:
	_update_layout()
	if pos.distance_to(_dash_btn) <= _btn_hit:
		_btn_touch = idx
		dash_requested.emit()
		return true
	if pos.distance_to(_jump_btn) <= _btn_hit:
		_btn_touch = idx
		jump_requested.emit()
		return true
	return false


func _move(v: Vector2) -> void:
	move_vector = v
	moved.emit(v)
