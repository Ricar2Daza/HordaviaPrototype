## JoystickLayer — joystick virtual flotante (guía §3.1).
## Autoload CanvasLayer. Empieza donde tocas (mitad izquierda/o cualquier zona),
## con fallback teclado WASD para probar en escritorio.
extends CanvasLayer

signal moved(vec: Vector2)
signal jump_requested
signal dash_requested

const RADIUS := 110.0
const DEADZONE := 0.25
const BTN_HIT := 92.0    # radio de acierto de los botones táctiles

var move_vector := Vector2.ZERO

var _touch_idx := -1
var _btn_touch := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _draw_root: Control
var _dash_btn := Vector2.ZERO
var _jump_btn := Vector2.ZERO


func _ready() -> void:
	layer = 5
	_draw_root = Control.new()
	_draw_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_root.draw.connect(_on_draw)
	add_child(_draw_root)
	_draw_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _on_draw() -> void:
	var sz := _draw_root.size
	var ins := _safe_insets()
	_dash_btn = Vector2(sz.x - 108.0 - ins.x, sz.y - 118.0 - ins.y)
	_jump_btn = Vector2(sz.x - 108.0 - ins.x, sz.y - 258.0 - ins.y)
	if _touch_idx == -1 and _btn_touch == -1:
		_draw_buttons(false)
		return
	_draw_root.draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.08))
	_draw_root.draw_circle(_origin, RADIUS * 0.92 + 2, Color(1, 1, 1, 0.12), false, 3.0)
	_draw_root.draw_circle(_knob, 34.0, Color(1, 1, 1, 0.35))
	_draw_root.draw_circle(_knob, 30.0, Color(1, 1, 1, 0.6))
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
	_draw_root.draw_circle(_dash_btn, 62.0, Color(0.4, 0.75, 1.0, a))
	_draw_root.draw_circle(_dash_btn, 62.0, Color(1, 1, 1, a + 0.1), false, 3.0)
	_draw_root.draw_circle(_jump_btn, 62.0, Color(0.45, 1.0, 0.6, a))
	_draw_root.draw_circle(_jump_btn, 62.0, Color(1, 1, 1, a + 0.1), false, 3.0)
	var font := ThemeDB.fallback_font
	_draw_root.draw_string(font, _dash_btn + Vector2(-32.0, 7.0), "DASH", HORIZONTAL_ALIGNMENT_CENTER, 64, 22, Color(0.05, 0.05, 0.1))
	_draw_root.draw_string(font, _jump_btn + Vector2(-32.0, 7.0), "SALTO", HORIZONTAL_ALIGNMENT_CENTER, 64, 22, Color(0.05, 0.05, 0.1))


func _process(_dt: float) -> void:
	var kb := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): kb.x -= 1
	if Input.is_physical_key_pressed(KEY_D): kb.x += 1
	if Input.is_physical_key_pressed(KEY_W): kb.y -= 1
	if Input.is_physical_key_pressed(KEY_S): kb.y += 1
	if kb.length() > 0.05:
		move_vector = kb
		_touch_idx = -1  # el teclado tiene prioridad en escritorio
	_draw_root.queue_redraw()


func _unhandled_input(ev: InputEvent) -> void:
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
		if rel.length() > DEADZONE * RADIUS:
			var v: Vector2 = rel / RADIUS
			_move(v.limit_length(1.0))
		else:
			_move(Vector2.ZERO)
		_knob = _origin + move_vector * RADIUS


func _check_button(pos: Vector2, idx: int) -> bool:
	var sz := _draw_root.size
	_dash_btn = Vector2(sz.x - 108.0, sz.y - 118.0)
	_jump_btn = Vector2(sz.x - 108.0, sz.y - 258.0)
	if pos.distance_to(_dash_btn) <= BTN_HIT:
		_btn_touch = idx
		dash_requested.emit()
		return true
	if pos.distance_to(_jump_btn) <= BTN_HIT:
		_btn_touch = idx
		jump_requested.emit()
		return true
	return false


func _move(v: Vector2) -> void:
	move_vector = v
	moved.emit(v)
