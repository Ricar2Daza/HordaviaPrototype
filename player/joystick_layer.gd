## JoystickLayer — joystick virtual flotante (guía §3.1).
## Autoload CanvasLayer. Empieza donde tocas (mitad izquierda/o cualquier zona),
## con fallback teclado WASD para probar en escritorio.
extends CanvasLayer

signal moved(vec: Vector2)
signal jump_requested
signal dash_requested

const RADIUS := 110.0
const DEADZONE := 0.25
const BTN_RADIUS := 62.0    # radio visual de los botones táctiles
const BTN_HIT := 92.0       # radio de acierto de los botones táctiles
const KNOB_RADIUS := 34.0
const LABEL_SIZE := 22
const BTN_MARGIN_X := 108.0
const BTN_MARGIN_Y := 118.0
const BTN_STACK := 140.0    # separación vertical DASH/SALTO

var move_vector := Vector2.ZERO
var _ui_scale := 1.0        # layout táctil adaptable (roadmap 5.5)

var _touch_idx := -1
var _btn_touch := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _draw_root: Control
var _dash_btn := Vector2.ZERO
var _jump_btn := Vector2.ZERO
var _btn_pos_valid := false
var _kb_active := false
var _kb_dir := Vector2.ZERO
var _dirty := true
var _last_size := Vector2.ZERO
var _last_win := Vector2i.ZERO
var _insets_cache := Vector2.ZERO
var _insets_size := Vector2(-1.0, -1.0)


func _ready() -> void:
	layer = 5
	_draw_root = Control.new()
	_draw_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_root.draw.connect(_on_draw)
	add_child(_draw_root)
	_draw_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	refresh_layout()


## Layout táctil adaptable (roadmap 5.5): auto por tamaño de pantalla o escala
## manual persistida en Ajustes. Recalcula posiciones y radios de acierto.
func refresh_layout() -> void:
	_ui_scale = _compute_ui_scale()
	_btn_pos_valid = false
	_dirty = true


func _compute_ui_scale() -> float:
	if GameState.touch_scale > 0.0:
		return clampf(GameState.touch_scale, 0.8, 1.3)
	# Tamaño físico de ventana/pantalla (los controles táctiles deben ser
	# cómodos en móviles pequeños y no gigantes en pantallas grandes).
	var win := DisplayServer.window_get_size()
	var sz := Vector2(float(win.x), float(win.y)) if win.x > 0 and win.y > 0 else Vector2.ZERO
	if sz.x <= 0.0 or sz.y <= 0.0:
		sz = _draw_root.size if _draw_root != null else Vector2.ZERO
	if sz.x <= 0.0 or sz.y <= 0.0:
		sz = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280.0, 720.0)
	var short_side := minf(sz.x, sz.y)
	if short_side < 620.0:
		return 0.9      # compacto
	if short_side < 860.0:
		return 1.0      # medio
	return 1.15         # grande


## Texto para el smoke/diagnóstico: "auto:medio x1.00".
func layout_label() -> String:
	var mode := "auto" if GameState.touch_scale <= 0.0 else "manual"
	var size_name := "compacto"
	if _ui_scale >= 1.1:
		size_name = "grande"
	elif _ui_scale >= 0.97:
		size_name = "medio"
	return "%s:%s x%.2f" % [mode, size_name, _ui_scale]


func _on_draw() -> void:
	_update_button_positions()
	var r := RADIUS * _ui_scale
	if _touch_idx == -1 and _btn_touch == -1:
		_draw_buttons(false)
		return
	_draw_root.draw_circle(_origin, r, Color(1, 1, 1, 0.08))
	_draw_root.draw_circle(_origin, r * 0.92 + 2.0, Color(1, 1, 1, 0.12), false, 3.0 * _ui_scale)
	_draw_root.draw_circle(_knob, KNOB_RADIUS * _ui_scale, Color(1, 1, 1, 0.35))
	_draw_root.draw_circle(_knob, (KNOB_RADIUS - 4.0) * _ui_scale, Color(1, 1, 1, 0.6))
	_draw_buttons(true)


## Posiciones de los botones táctiles (compartidas por dibujo y acierto).
func _update_button_positions() -> void:
	var sz := _draw_root.size
	if _btn_pos_valid and sz == _last_size:
		return
	_last_size = sz
	_btn_pos_valid = true
	_insets_cache = _compute_safe_insets(sz)
	var mx := BTN_MARGIN_X * _ui_scale
	var my := BTN_MARGIN_Y * _ui_scale
	_dash_btn = Vector2(sz.x - mx - _insets_cache.x, sz.y - my - _insets_cache.y)
	_jump_btn = Vector2(sz.x - mx - _insets_cache.x, sz.y - (my + BTN_STACK * _ui_scale) - _insets_cache.y)
	_dirty = true


func _compute_safe_insets(sz: Vector2) -> Vector2:
	## Insets derecho/inferior para no tapar botones con el notch.
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return Vector2.ZERO
	var right := maxf(float(win.x - safe.position.x - safe.size.x) * sz.x / float(win.x), 0.0)
	var bottom := maxf(float(win.y - safe.position.y - safe.size.y) * sz.y / float(win.y), 0.0)
	return Vector2(right, bottom)


func _draw_buttons(active: bool) -> void:
	var a := 0.55 if active else 0.3
	var r := BTN_RADIUS * _ui_scale
	_draw_root.draw_circle(_dash_btn, r, Color(0.4, 0.75, 1.0, a))
	_draw_root.draw_circle(_dash_btn, r, Color(1, 1, 1, a + 0.1), false, 3.0 * _ui_scale)
	_draw_root.draw_circle(_jump_btn, r, Color(0.45, 1.0, 0.6, a))
	_draw_root.draw_circle(_jump_btn, r, Color(1, 1, 1, a + 0.1), false, 3.0 * _ui_scale)
	var font := ThemeDB.fallback_font
	var fs := int(round(LABEL_SIZE * _ui_scale))
	var width := r * 2.0
	var off := Vector2(-r, fs * 0.34)
	_draw_root.draw_string(font, _dash_btn + off, "DASH", HORIZONTAL_ALIGNMENT_CENTER, width, fs, Color(0.05, 0.05, 0.1))
	_draw_root.draw_string(font, _jump_btn + off, "SALTO", HORIZONTAL_ALIGNMENT_CENTER, width, fs, Color(0.05, 0.05, 0.1))


func _process(_dt: float) -> void:
	var kb := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A): kb.x -= 1
	if Input.is_physical_key_pressed(KEY_D): kb.x += 1
	if Input.is_physical_key_pressed(KEY_W): kb.y -= 1
	if Input.is_physical_key_pressed(KEY_S): kb.y += 1
	var kb_pressed := kb.length() > 0.05
	if kb_pressed:
		if not _kb_active or _kb_dir != kb:
			_kb_active = true
			_kb_dir = kb
			move_vector = kb
			_touch_idx = -1  # el teclado tiene prioridad en escritorio
			_dirty = true
	elif _kb_active:
		# Al soltar el teclado se detiene el movimiento (antes quedaba "pegado").
		_kb_active = false
		_kb_dir = Vector2.ZERO
		if _touch_idx == -1:
			move_vector = Vector2.ZERO
			_knob = _origin
		_dirty = true
	var win := DisplayServer.window_get_size()
	if win != _last_win:
		_last_win = win
		_ui_scale = _compute_ui_scale()
		_btn_pos_valid = false
		_dirty = true
	var sz := _draw_root.size
	if sz != _last_size:
		_ui_scale = _compute_ui_scale()
		_btn_pos_valid = false
		_dirty = true
	# Redibuja solo cuando algo cambia (idle: ningún coste de dibujo).
	if _dirty:
		_dirty = false
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
				_dirty = true
		elif ev.index == _touch_idx:
			_touch_idx = -1
			_move(Vector2.ZERO)
		elif ev.index == _btn_touch:
			_btn_touch = -1
			_dirty = true
	elif ev is InputEventScreenDrag and ev.index == _touch_idx:
		var radius := RADIUS * _ui_scale
		var rel: Vector2 = ev.position - _origin
		if rel.length() > DEADZONE * radius:
			var v: Vector2 = rel / radius
			_move(v.limit_length(1.0))
		else:
			_move(Vector2.ZERO)
		_knob = _origin + move_vector * radius
		_dirty = true


func _check_button(pos: Vector2, idx: int) -> bool:
	if not _btn_pos_valid:
		_update_button_positions()
	var hit := BTN_HIT * _ui_scale
	if pos.distance_to(_dash_btn) <= hit:
		_btn_touch = idx
		_dirty = true
		dash_requested.emit()
		return true
	if pos.distance_to(_jump_btn) <= hit:
		_btn_touch = idx
		_dirty = true
		jump_requested.emit()
		return true
	return false


func _move(v: Vector2) -> void:
	move_vector = v
	_dirty = true
	moved.emit(v)
