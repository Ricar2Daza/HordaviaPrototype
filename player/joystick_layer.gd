## Joystick virtual flotante con teclado/gamepad, layout responsive y safe area.
extends CanvasLayer

signal moved(vec: Vector2)
signal jump_requested
signal dash_requested

const RADIUS := 110.0
const DEADZONE := 0.25
const BTN_RADIUS := 62.0
const BTN_HIT := 92.0
const KNOB_RADIUS := 34.0
const LABEL_SIZE := 22
const BTN_MARGIN_X := 108.0
const BTN_MARGIN_Y := 118.0
const BTN_STACK := 140.0

var move_vector := Vector2.ZERO
var _ui_scale := 1.0
var _joy_radius := RADIUS
var _btn_radius := BTN_RADIUS
var _btn_hit := BTN_HIT
var _touch_idx := -1
var _btn_touch := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _draw_root: Control
var _dash_btn := Vector2.ZERO
var _jump_btn := Vector2.ZERO
var _btn_pos_valid := false
var _dirty := true
var _last_size := Vector2(-1.0, -1.0)
var _last_win := Vector2i.ZERO
var _layout_reported := false


func _ready() -> void:
	layer = 5
	_draw_root = Control.new()
	_draw_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_root.draw.connect(_on_draw)
	_draw_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_draw_root)
	get_viewport().size_changed.connect(refresh_layout)
	refresh_layout()
	set_process(true)


## Recalcula la escala de botones por pantalla o por override de Ajustes.
func refresh_layout() -> void:
	_ui_scale = _compute_ui_scale()
	_btn_pos_valid = false
	_dirty = true
	if _draw_root != null:
		_draw_root.queue_redraw()


func _compute_ui_scale() -> float:
	if GameState.touch_scale > 0.0:
		return clampf(GameState.touch_scale, 0.8, 1.3)
	var sz := _layout_size()
	if sz.x <= 0.0 or sz.y <= 0.0:
		return 1.0
	var short_side := minf(sz.x, sz.y)
	if short_side < 620.0:
		return 0.9
	if short_side < 860.0:
		return 1.0
	return 1.15


func layout_label() -> String:
	var mode := "auto" if GameState.touch_scale <= 0.0 else "manual"
	var size_name := "compacto"
	if _ui_scale >= 1.1:
		size_name = "grande"
	elif _ui_scale >= 0.97:
		size_name = "medio"
	return "%s:%s x%.2f" % [mode, size_name, _ui_scale]


func _layout_size() -> Vector2:
	var forced := OS.get_environment("HORDAVIA_LAYOUT_SIZE")
	if not forced.is_empty():
		var parts := forced.split("x")
		if parts.size() == 2:
			return Vector2(float(parts[0]), float(parts[1]))
	if _draw_root != null and _draw_root.size.x > 0.0 and _draw_root.size.y > 0.0:
		return _draw_root.size
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO


func _update_button_positions() -> void:
	var sz := _layout_size()
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	var win := DisplayServer.window_get_size()
	if not _btn_pos_valid or sz != _last_size or win != _last_win:
		_last_size = sz
		_last_win = win
		_ui_scale = _compute_ui_scale()
		_joy_radius = RADIUS * _ui_scale
		_btn_radius = BTN_RADIUS * _ui_scale
		_btn_hit = BTN_HIT * _ui_scale
		var insets := _compute_safe_insets(sz)
		var right := BTN_MARGIN_X * _ui_scale + insets.x
		_dash_btn = Vector2(sz.x - right, sz.y - BTN_MARGIN_Y * _ui_scale - insets.y)
		_jump_btn = Vector2(
			sz.x - right, sz.y - (BTN_MARGIN_Y + BTN_STACK) * _ui_scale - insets.y
		)
		_btn_pos_valid = true
		_dirty = true
		var inside := (
			_dash_btn.x - _btn_radius >= 0.0 and _dash_btn.y - _btn_radius >= 0.0
			and _dash_btn.x + _btn_radius <= sz.x and _dash_btn.y + _btn_radius <= sz.y
			and _jump_btn.x - _btn_radius >= 0.0 and _jump_btn.y - _btn_radius >= 0.0
			and _jump_btn.x + _btn_radius <= sz.x and _jump_btn.y + _btn_radius <= sz.y
		)
		if not inside:
			push_error("LAYOUT fuera de pantalla: viewport=%s dash=%s jump=%s" % [
				str(sz), str(_dash_btn), str(_jump_btn),
			])
		if OS.get_environment("HORDAVIA_LAYOUT_TEST") == "1" and not _layout_reported:
			_layout_reported = true
			print("LAYOUT viewport=%s scale=%.2f dash=%s jump=%s ok=%s" % [
				str(sz), _ui_scale, str(_dash_btn), str(_jump_btn), str(inside),
			])


func _compute_safe_insets(sz: Vector2) -> Vector2:
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return Vector2.ZERO
	var right := maxf(float(win.x - safe.position.x - safe.size.x) * sz.x / float(win.x), 0.0)
	var bottom := maxf(float(win.y - safe.position.y - safe.size.y) * sz.y / float(win.y), 0.0)
	return Vector2(right, bottom)


func _on_draw() -> void:
	_update_button_positions()
	if _touch_idx == -1:
		_draw_buttons(_btn_touch != -1)
		return
	_draw_root.draw_circle(_origin, _joy_radius, Color(1, 1, 1, 0.08))
	_draw_root.draw_circle(
		_origin, _joy_radius * 0.92 + 2.0, Color(1, 1, 1, 0.12), false, 3.0 * _ui_scale
	)
	_draw_root.draw_circle(_knob, KNOB_RADIUS * _ui_scale, Color(1, 1, 1, 0.35))
	_draw_root.draw_circle(_knob, (KNOB_RADIUS - 4.0) * _ui_scale, Color(1, 1, 1, 0.6))
	_draw_buttons(true)


func _draw_buttons(active: bool) -> void:
	var a := 0.55 if active else 0.3
	_draw_root.draw_circle(_dash_btn, _btn_radius, Color(0.4, 0.75, 1.0, a))
	_draw_root.draw_circle(
		_dash_btn, _btn_radius, Color(1, 1, 1, a + 0.1), false, 3.0 * _ui_scale
	)
	_draw_root.draw_circle(_jump_btn, _btn_radius, Color(0.45, 1.0, 0.6, a))
	_draw_root.draw_circle(
		_jump_btn, _btn_radius, Color(1, 1, 1, a + 0.1), false, 3.0 * _ui_scale
	)
	var font := ThemeDB.fallback_font
	var fs := int(round(LABEL_SIZE * _ui_scale))
	var width := _btn_radius * 2.0
	var offset := Vector2(-_btn_radius, fs * 0.34)
	_draw_root.draw_string(
		font, _dash_btn + offset, "DASH", HORIZONTAL_ALIGNMENT_CENTER, width, fs, Color(0.05, 0.05, 0.1)
	)
	_draw_root.draw_string(
		font, _jump_btn + offset, "SALTO", HORIZONTAL_ALIGNMENT_CENTER, width, fs, Color(0.05, 0.05, 0.1)
	)


func _process(_dt: float) -> void:
	_update_button_positions()
	var next_move := Input.get_vector(
		"move_left", "move_right", "move_up", "move_down", DEADZONE
	)
	if next_move.length() > 0.05:
		_touch_idx = -1
		_move(next_move)
	elif _mouse_look():
		_touch_idx = -1
		_btn_touch = -1
		_move(Vector2.ZERO)
	elif _touch_idx == -1:
		_move(Vector2.ZERO)
	if _dirty:
		_dirty = false
		_draw_root.queue_redraw()


func _mouse_look() -> bool:
	return (
		GameState.camera_mode == "mouse"
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and not DisplayServer.is_touchscreen_available()
	)


func _unhandled_input(ev: InputEvent) -> void:
	if _mouse_look():
		return
	_update_button_positions()
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if ev.index == _touch_idx:
				return
			if _check_button(ev.position, ev.index):
				return
			if _touch_idx == -1 and _btn_touch == -1:
				_touch_idx = ev.index
				_origin = ev.position
				_knob = ev.position
				_dirty = true
		elif ev.index == _touch_idx:
			_touch_idx = -1
			_move(Vector2.ZERO)
		elif ev.index == _btn_touch:
			_btn_touch = -1
			_dirty = true
	elif ev is InputEventScreenDrag and ev.index == _touch_idx:
		var rel: Vector2 = ev.position - _origin
		if rel.length() > DEADZONE * _joy_radius:
			_move((rel / _joy_radius).limit_length(1.0))
		else:
			_move(Vector2.ZERO)
		_knob = _origin + move_vector * _joy_radius
		_dirty = true


func _check_button(pos: Vector2, idx: int) -> bool:
	_update_button_positions()
	if pos.distance_to(_dash_btn) <= _btn_hit:
		_btn_touch = idx
		_dirty = true
		dash_requested.emit()
		return true
	if pos.distance_to(_jump_btn) <= _btn_hit:
		_btn_touch = idx
		_dirty = true
		jump_requested.emit()
		return true
	return false


func _move(v: Vector2) -> void:
	if move_vector == v:
		return
	move_vector = v
	_dirty = true
	moved.emit(v)
