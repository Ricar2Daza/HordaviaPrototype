## InputSetup — mapa de entrada único para teclado, ratón y gamepad.
## Autoload. Debe ejecutarse antes que JoystickLayer/Player para que InputMap
## esté listo desde el primer frame. Así el resto del código no consulta teclas
## crudas: usa acciones y también funciona con mando.
extends Node

const DEADZONE := 0.2


func _ready() -> void:
	# Movimiento (teclado + stick izquierdo + cruceta).
	_add("move_left", [KEY_A, KEY_LEFT], [
		_axis(JOY_AXIS_LEFT_X, -1.0), _btn(JOY_BUTTON_DPAD_LEFT),
	])
	_add("move_right", [KEY_D, KEY_RIGHT], [
		_axis(JOY_AXIS_LEFT_X, 1.0), _btn(JOY_BUTTON_DPAD_RIGHT),
	])
	_add("move_up", [KEY_W, KEY_UP], [
		_axis(JOY_AXIS_LEFT_Y, -1.0), _btn(JOY_BUTTON_DPAD_UP),
	])
	_add("move_down", [KEY_S, KEY_DOWN], [
		_axis(JOY_AXIS_LEFT_Y, 1.0), _btn(JOY_BUTTON_DPAD_DOWN),
	])
	# Acciones de combate y cámara.
	_add("jump", [KEY_SPACE], [_btn(JOY_BUTTON_A)])
	_add("dash", [KEY_SHIFT], [_btn(JOY_BUTTON_B)])
	_add("toggle_camera", [KEY_C], [_btn(JOY_BUTTON_Y)])
	_add("pause", [KEY_ESCAPE], [_btn(JOY_BUTTON_START)])
	# Cámara orbital con stick derecho (modo Mouse).
	_add("cam_left", [KEY_Q], [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_add("cam_right", [KEY_E], [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_augment_ui_actions()
	print("INPUT actions=%d gamepads=%d" % [
		InputMap.get_actions().size(), Input.get_connected_joypads().size(),
	])


func _add(action: StringName, keys: Array, pad: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, DEADZONE)
	for code in keys:
		InputMap.action_add_event(action, _key(int(code)))
	for ev in pad:
		InputMap.action_add_event(action, ev)


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	return ev


func _btn(index: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = index
	return ev


func _axis(axis: int, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	return ev


func _augment_ui_actions() -> void:
	# Navegación de menús con mando (Godot ya trae teclado; añadimos pad).
	_add_event_once("ui_accept", _btn(JOY_BUTTON_A))
	_add_event_once("ui_cancel", _btn(JOY_BUTTON_B))
	_add_event_once("ui_up", _btn(JOY_BUTTON_DPAD_UP))
	_add_event_once("ui_down", _btn(JOY_BUTTON_DPAD_DOWN))
	_add_event_once("ui_left", _btn(JOY_BUTTON_DPAD_LEFT))
	_add_event_once("ui_right", _btn(JOY_BUTTON_DPAD_RIGHT))
	_add_event_once("ui_up", _axis(JOY_AXIS_LEFT_Y, -1.0))
	_add_event_once("ui_down", _axis(JOY_AXIS_LEFT_Y, 1.0))
	_add_event_once("ui_left", _axis(JOY_AXIS_LEFT_X, -1.0))
	_add_event_once("ui_right", _axis(JOY_AXIS_LEFT_X, 1.0))


func _add_event_once(action: StringName, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	for existing in InputMap.action_get_events(action):
		if existing.is_match(ev):
			return
	InputMap.action_add_event(action, ev)
