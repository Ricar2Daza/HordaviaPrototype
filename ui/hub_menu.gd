## HubMenu — menú clásico con submenús, tienda, personajes, maldiciones,
## códice, logros y ajustes. Se construye 100 % por código para móvil.
## No controla el árbol pausado: HUD decide cuándo abrir/cerrar y conectar señales.
extends Control

signal play_requested
signal resume_requested
signal quit_requested

const RARITY_COLORS := {
	"comun": Color(0.58, 0.62, 0.68),
	"raro": Color(0.35, 0.60, 0.95),
	"epico": Color(0.68, 0.42, 0.95),
	"legendario": Color(1.0, 0.76, 0.25),
}

const TAB_IDS := ["jugar", "personajes", "tienda", "maldiciones", "codice", "logros", "ajustes"]
const NAV_LABELS := {
	"jugar": "▶ JUGAR",
	"personajes": "PERSONAJES",
	"tienda": "TIENDA",
	"maldiciones": "MALDICIONES",
	"codice": "CÓDICE",
	"logros": "LOGROS",
	"ajustes": "AJUSTES",
}
const FPS_OPTIONS := [[30, "30"], [60, "60"], [120, "120"], [0, "∞"]]
const QUALITY_OPTIONS := [["auto", "Auto"], ["bajo", "Baja"], ["medio", "Media"], ["alto", "Alta"]]
const CAMERA_OPTIONS := [["fija", "Fija"], ["mouse", "Mouse"]]
const SHAKE_OPTIONS := [[0.0, "Off"], [0.5, "Suave"], [1.0, "Normal"]]
const TOGGLE_OPTIONS := [[false, "Off"], [true, "On"]]
const TOUCH_OPTIONS := [[0.0, "Auto"], [0.9, "S"], [1.0, "M"], [1.15, "L"]]

# Paleta "fuego sobre negro": el menú inicial es negro con llamas procedurales.
const FIRE_SHADER := """
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec3 fire_color : source_color = vec3(1.0, 0.30, 0.04);
uniform vec3 core_color : source_color = vec3(1.0, 0.78, 0.30);
uniform float speed = 1.0;
uniform float scale = 3.0;
uniform float intensity = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float h = uv.y;
	vec2 p = vec2(uv.x * scale, (1.0 - h) * scale * 1.15 - t * 1.7);
	float warp = fbm(p * 0.7 + vec2(t * 0.33, 0.0));
	float n = fbm(p + vec2(warp * 1.5, 0.0));
	float mask = smoothstep(0.0, 0.82, h + (n - 0.5) * 0.95);
	float body = smoothstep(0.28, 0.78, n + h * 0.55);
	float flame = clamp(mask * body * intensity, 0.0, 1.0);
	vec3 col = mix(fire_color, core_color, pow(flame, 2.2));
	col += fire_color * 0.22 * mask * mask;
	COLOR = vec4(col * flame, flame);
}
"""

const C_TEXT := Color(0.96, 0.93, 0.88)
const C_MUTED := Color(0.74, 0.68, 0.60, 0.88)
const C_AMBER := Color(1.0, 0.62, 0.22)
const C_AMBER_SOFT := Color(1.0, 0.80, 0.48)
const C_PANEL := Color(0.022, 0.018, 0.014, 0.80)
const C_BORDER := Color(0.34, 0.21, 0.11, 0.85)

var _tab := "jugar"
var _codex_sub := "armas"
var _margin: MarginContainer
var _coins: Label
var _resume_btn: Button
var _nav_buttons := {}
var _title: Label
var _subtitle: Label
var _content: VBoxContainer
var _scroll: ScrollContainer
var _embers: CPUParticles2D
var _fire_far: ColorRect
var _fire_near: ColorRect


func setup() -> void:
	# Un Control creado oculto bajo un CanvasLayer no recibe layout automático:
	# sin tamaño explícito el hub queda en 0x0 y el botón JUGAR es inalcanzable.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_deferred("size", get_viewport().get_visible_rect().size)
	_build_background()
	_build_shell()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	refresh()


func refresh() -> void:
	if _coins == null:
		return
	_coins.text = "◈  %d monedas" % SaveManager.total_coins
	_resume_btn.visible = GameState.run_active
	_style_nav()
	_render_tab()


func select_tab(tab: String) -> void:
	_tab = tab if TAB_IDS.has(tab) else "jugar"
	AudioManager.play_sfx("pickup", 1.15)
	refresh()


# ---------------- estructura visual ----------------

func _build_background() -> void:
	# Fondo negro puro: las llamas son las únicas que aportan luz.
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var shader := Shader.new()
	shader.code = FIRE_SHADER
	_fire_far = _make_fire(shader, 0.36, 0.58, Color(1.0, 0.20, 0.03), Color(1.0, 0.50, 0.10), 2.1, 0.80, 0.85)
	_fire_near = _make_fire(shader, 0.62, 1.00, Color(1.0, 0.36, 0.05), Color(1.0, 0.90, 0.48), 3.4, 1.35, 1.10)
	_build_embers()

	# Brasas tenues en la parte alta para que el negro no quede muerto.
	var haze := ColorRect.new()
	haze.color = Color(0.30, 0.08, 0.02, 0.10)
	haze.set_anchors_preset(Control.PRESET_FULL_RECT)
	haze.anchor_top = 0.55
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(haze)


func _make_fire(shader: Shader, top: float, bottom: float, fc: Color, cc: Color,
		sc: float, sp: float, it: float) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.anchor_top = top
	r.anchor_bottom = bottom
	r.offset_left = 0
	r.offset_right = 0
	r.offset_top = 0
	r.offset_bottom = 0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("fire_color", Vector3(fc.r, fc.g, fc.b))
	m.set_shader_parameter("core_color", Vector3(cc.r, cc.g, cc.b))
	m.set_shader_parameter("scale", sc)
	m.set_shader_parameter("speed", sp)
	m.set_shader_parameter("intensity", it)
	r.material = m
	add_child(r)
	return r


func _build_embers() -> void:
	_embers = CPUParticles2D.new()
	_embers.amount = 64
	_embers.lifetime = 4.5
	_embers.preprocess = 2.0
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(620, 6)
	_embers.direction = Vector2(0, -1)
	_embers.spread = 22.0
	_embers.initial_velocity_min = 26.0
	_embers.initial_velocity_max = 96.0
	_embers.gravity = Vector2(0, -14)
	_embers.scale_amount_min = 0.05
	_embers.scale_amount_max = 0.18
	_embers.color = Color(1.0, 0.62, 0.22, 0.9)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	ramp.set_color(1, Color(1.0, 0.16, 0.02, 0.0))
	_embers.color_ramp = ramp
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	_embers.texture = tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_embers.material = mat
	add_child(_embers)


func _layout_background() -> void:
	if _embers == null:
		return
	var vs := get_viewport().get_visible_rect().size
	_embers.position = Vector2(vs.x * 0.5, vs.y * 0.99)
	_embers.emission_rect_extents = Vector2(vs.x * 0.52, 8.0)


func _build_shell() -> void:
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_left", 26)
	_margin.add_theme_constant_override("margin_right", 26)
	_margin.add_theme_constant_override("margin_top", 18)
	_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(_margin)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 10)
	_margin.add_child(shell)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	shell.add_child(header)

	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 1)
	header.add_child(brand)
	var logo := Label.new()
	logo.text = "HORDAVIA"
	logo.add_theme_font_size_override("font_size", 40)
	logo.add_theme_color_override("font_color", Color(1.0, 0.92, 0.82))
	brand.add_child(logo)
	var tag := Label.new()
	tag.text = "SUPERVIVENCIA SIN FIN"
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", C_MUTED)
	brand.add_child(tag)
	var brand_line := ColorRect.new()
	brand_line.color = Color(1.0, 0.45, 0.10, 0.75)
	brand_line.custom_minimum_size = Vector2(150, 2)
	brand.add_child(brand_line)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_resume_btn = _button(header, "▶  VOLVER AL JUEGO", func() -> void: resume_requested.emit(), 190, 42)
	_resume_btn.name = "ResumeButton"
	_resume_btn.add_theme_stylebox_override("normal", _style(Color(0.18, 0.10, 0.03, 0.95), C_AMBER, 2))
	_resume_btn.add_theme_color_override("font_color", C_AMBER_SOFT)
	_resume_btn.visible = false

	_coins = Label.new()
	_coins.add_theme_font_size_override("font_size", 20)
	_coins.add_theme_color_override("font_color", C_AMBER_SOFT)
	_coins.custom_minimum_size.x = 190
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_coins)

	var accent := ColorRect.new()
	accent.color = Color(1.0, 0.38, 0.08, 0.55)
	accent.custom_minimum_size = Vector2(0, 2)
	shell.add_child(accent)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	shell.add_child(nav)
	for id in TAB_IDS:
		var b := _button(nav, String(NAV_LABELS[id]), select_tab.bind(id), 124, 36)
		b.add_theme_font_size_override("font_size", 12)
		_nav_buttons[id] = b
	var quit := _button(nav, "SALIR", func() -> void: quit_requested.emit(), 76, 36)
	quit.add_theme_font_size_override("font_size", 12)
	quit.add_theme_color_override("font_color", Color(1.0, 0.50, 0.40))

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(C_PANEL, C_BORDER, 1, 14))
	shell.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(pad)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	pad.add_child(body)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 25)
	_title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.78))
	body.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.add_theme_color_override("font_color", C_MUTED)
	body.add_child(_subtitle)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	_scroll.add_child(_content)

	var footer := Label.new()
	footer.text = "WASD / joystick  ·  C cámara  ·  ESC o ☰ pausa  ·  guardado automático"
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.34))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(footer)


func _apply_safe_area() -> void:
	_layout_background()
	if _margin == null:
		return
	var vs := get_viewport().get_visible_rect().size
	if vs.x > 0.0 and vs.y > 0.0 and size != vs:
		set_deferred("size", vs)
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return
	var sx := vs.x / float(win.x)
	var sy := vs.y / float(win.y)
	var left := maxf(float(safe.position.x) * sx, 0.0)
	var top := maxf(float(safe.position.y) * sy, 0.0)
	var right := maxf(float(win.x - safe.position.x - safe.size.x) * sx, 0.0)
	var bottom := maxf(float(win.y - safe.position.y - safe.size.y) * sy, 0.0)
	_margin.add_theme_constant_override("margin_left", 26 + int(left))
	_margin.add_theme_constant_override("margin_right", 26 + int(right))
	_margin.add_theme_constant_override("margin_top", 18 + int(top))
	_margin.add_theme_constant_override("margin_bottom", 16 + int(bottom))


# ---------------- estilos y helpers ----------------

func _style(bg: Color, border: Color, width: int = 1, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(width)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	return sb


func _button(parent: Node, text: String, action: Callable, width: float = 0.0, height: float = 40.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", C_TEXT)
	if width > 0.0:
		b.custom_minimum_size.x = width
	b.custom_minimum_size.y = height
	b.add_theme_stylebox_override("normal", _style(Color(0.055, 0.045, 0.035, 0.88), Color(0.24, 0.18, 0.13, 0.95), 1))
	b.add_theme_stylebox_override("hover", _style(Color(0.12, 0.075, 0.035, 0.96), C_AMBER, 1))
	b.add_theme_stylebox_override("pressed", _style(Color(0.22, 0.12, 0.04, 1.0), C_AMBER_SOFT, 2))
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _primary(parent: Node, text: String, action: Callable, width: float = 0.0, height: float = 52.0) -> Button:
	var b := _button(parent, text, action, width, height)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(0.10, 0.05, 0.01))
	b.add_theme_stylebox_override("normal", _style(Color(0.95, 0.55, 0.16), Color(1.0, 0.86, 0.52), 2))
	b.add_theme_stylebox_override("hover", _style(Color(1.0, 0.68, 0.28), Color(1.0, 0.95, 0.75), 2))
	b.add_theme_stylebox_override("pressed", _style(Color(0.78, 0.40, 0.09), Color(1.0, 0.80, 0.40), 2))
	return b


func _label(parent: Node, text: String, size: int = 13, color: Color = Color(1, 1, 1, 0.86), wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l


func _card(parent: Node, min_width: float = 0.0, border: Color = C_BORDER) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(0.035, 0.028, 0.022, 0.80), border, 1, 10))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if min_width > 0.0:
		p.custom_minimum_size.x = min_width
	parent.add_child(p)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	return v


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _selected_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _style(Color(0.20, 0.11, 0.04, 1.0), C_AMBER, 2))
	b.add_theme_color_override("font_color", C_AMBER_SOFT)


func _unselected_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _style(Color(0.055, 0.045, 0.035, 0.88), Color(0.24, 0.18, 0.13, 0.95), 1))
	b.add_theme_color_override("font_color", C_TEXT)


func _style_nav() -> void:
	for id in _nav_buttons:
		var b: Button = _nav_buttons[id]
		if String(id) == _tab:
			_selected_button(b)
		else:
			_unselected_button(b)


# ---------------- render por pestaña ----------------

func _render_tab() -> void:
	if _content == null:
		return
	_clear(_content)
	match _tab:
		"personajes":
			_title.text = "PERSONAJES"
			_subtitle.text = "Tres formas de sobrevivir. Elige tu estilo antes de lanzarte al ciclo."
			_render_characters()
		"tienda":
			_title.text = "TIENDA META"
			_subtitle.text = "Mejoras permanentes entre partidas. Las monedas no se pierden al morir."
			_render_shop()
		"maldiciones":
			_title.text = "MALDICIONES"
			_subtitle.text = "Más peligro, más recompensa. Una maldición activa por expedición."
			_render_curses()
		"codice":
			_title.text = "CÓDICE"
			_subtitle.text = "Armas, pasivas, recetas de evolución y bestiario del prototipo."
			_render_codex()
		"logros":
			_title.text = "LOGROS Y RÉCORDS"
			_subtitle.text = "Tu historial de supervivencia, bajas y objetivos completados."
			_render_records()
		"ajustes":
			_title.text = "AJUSTES"
			_subtitle.text = "Rendimiento, cámara, audio y diagnóstico del dispositivo."
			_render_settings()
		_:
			_title.text = "PARTIDA SIN FIN"
			_subtitle.text = "Siete ambientes, clima dinámico y una horda que nunca deja de crecer."
			_render_play()


func _render_play() -> void:
	var hero := _card(_content, 0.0, Color(0.62, 0.34, 0.12))
	hero.add_theme_constant_override("separation", 10)
	_label(hero, "LA HORDA NO DUERME", 30, Color(1.0, 0.92, 0.82))
	_label(hero, "Sobrevive sin límite de tiempo. Cada 6 minutos el mundo cambia de bioma, el clima se vuelve hostil y los jefes escalan. Solo la muerte termina la partida.", 13, C_MUTED)

	if GameState.run_active:
		var cont := _button(hero, "▶  CONTINUAR PARTIDA", func() -> void: resume_requested.emit(), 0.0, 54)
		cont.name = "ContinueButton"
		cont.add_theme_font_size_override("font_size", 20)
		var again := _button(hero, "Empezar una expedición nueva", func() -> void: play_requested.emit(), 0.0, 40)
		again.add_theme_font_size_override("font_size", 14)
	var play := _primary(hero, "EMPEZAR EXPEDICIÓN", func() -> void: play_requested.emit(), 0.0, 76)
	play.name = "PlayButton"
	play.add_theme_font_size_override("font_size", 26)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_content.add_child(row)

	var ch: Dictionary = ContentDB.characters.get(SaveManager.character, {})
	var cur: Dictionary = {}
	for c in ContentDB.curses:
		if String(c.get("id", "")) == String(SaveManager.settings.get("curse", "ninguna")):
			cur = c
			break
	_stat_chip(row, "PERSONAJE", String(ch.get("name", "Vagabundo")),
		"%d HP  ·  vel %.1f" % [int(ch.get("hp", 100)), float(ch.get("speed", 6.0))])
	_stat_chip(row, "MALDICIÓN", String(cur.get("name", "Sin maldición")),
		"monedas +%d%%" % int(round(float(cur.get("coins", 0.0)) * 100.0)))
	_stat_chip(row, "RÉCORD", "%d:%02d" % [int(SaveManager.best_time) / 60, int(SaveManager.best_time) % 60],
		"%d bajas  ·  %d jefes" % [SaveManager.total_kills, SaveManager.boss_kills])

	_label(_content, "Armas %d  ·  Evoluciones %d  ·  Pasivas %d  ·  Bestias %d  ·  7 biomas en ciclo de 42 min" % [
		ContentDB.weapons.size(), ContentDB.evolutions.size(),
		ContentDB.upgrades.size(), ContentDB.enemies.size(),
	], 11, Color(0.80, 0.72, 0.62, 0.72))
	_render_contracts()


func _render_contracts() -> void:
	_label(_content, "CONTRATO DE EXPEDICIÓN", 18, C_AMBER_SOFT)
	_label(_content, "Elige un objetivo opcional. Al cumplirlo, recibes monedas durante la run.", 11, C_MUTED)
	var selected := String(SaveManager.settings.get("contract", ""))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	var none := _card(grid, 220.0, C_BORDER if selected != "" else C_AMBER)
	_label(none, "Sin contrato", 16, C_TEXT)
	_label(none, "Juega sin objetivo adicional.", 11, C_MUTED)
	var none_btn := _button(none, "ACTIVO" if selected == "" else "ELEGIR", _select_contract.bind(""), 0.0, 36)
	if selected == "":
		_selected_button(none_btn)
	for contract in ContentDB.contracts:
		var id := String(contract.get("id", ""))
		var active := selected == id
		var card := _card(grid, 220.0, C_AMBER if active else C_BORDER)
		_label(card, String(contract.get("name", id)), 16, C_TEXT)
		_label(card, String(contract.get("desc", "")), 11, C_MUTED)
		_label(card, "Recompensa: ◈ %d" % int(contract.get("reward", 0)), 12, C_AMBER_SOFT)
		var button := _button(card, "ACTIVO" if active else "ELEGIR", _select_contract.bind(id), 0.0, 36)
		if active:
			_selected_button(button)


func _stat_chip(parent: Node, title: String, value: String, sub: String) -> void:
	var c := _card(parent, 0.0, Color(0.34, 0.22, 0.12))
	c.add_theme_constant_override("separation", 2)
	_label(c, title, 10, Color(0.76, 0.62, 0.46))
	_label(c, value, 19, Color(1.0, 0.88, 0.70))
	_label(c, sub, 10, C_MUTED)


func _render_characters() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_content.add_child(grid)
	for id in ContentDB.characters:
		var def: Dictionary = ContentDB.characters[id]
		var selected := String(id) == SaveManager.character
		var card := _card(grid, 260.0, Color(0.32, 0.85, 0.58) if selected else Color(0.16, 0.22, 0.27))
		_label(card, "%s%s" % ["▶ " if selected else "", String(def.get("name", id))], 21, Color(0.80, 1.0, 0.86) if selected else Color(1, 1, 1, 0.90))
		_label(card, String(def.get("desc", "")), 12, Color(1, 1, 1, 0.66))
		_label(card, "HP %d\nVelocidad %.1f\nDaño x%.2f\nCadencia x%.2f\nImán %.1f" % [
			int(def.get("hp", 100)), float(def.get("speed", 6.0)), float(def.get("dmg", 1.0)),
			float(def.get("fire", 1.0)), float(def.get("magnet", 3.0)),
		], 12, Color(0.78, 0.90, 1.0, 0.82))
		var b := _button(card, "ELEGIDO" if selected else "ELEGIR", _select_char.bind(String(id)), 0.0, 38)
		if selected:
			_selected_button(b)


func _render_shop() -> void:
	var head := _card(_content, 0.0, Color(0.42, 0.36, 0.16))
	_label(head, "Monedas disponibles: %d" % SaveManager.total_coins, 18, Color(1.0, 0.88, 0.40))
	_label(head, "Compra mejoras permanentes para todas las partidas. El coste sube con cada nivel.", 11, Color(1, 1, 1, 0.60))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	for def in ContentDB.meta_upgrades:
		var id := String(def.get("id", ""))
		var lvl := GameState.meta_level(id)
		var mx := int(def.get("max", 5))
		var cost := GameState.meta_cost(def)
		var card := _card(grid, 260.0, Color(0.40, 0.78, 0.48) if lvl > 0 else Color(0.16, 0.22, 0.27))
		_label(card, String(def.get("name", id)), 16, Color(0.82, 1.0, 0.82))
		_label(card, String(def.get("desc", "")), 11, Color(1, 1, 1, 0.62))
		var pips := ""
		for i in mx:
			pips += "●" if i < lvl else "○"
		_label(card, "%s   %d/%d" % [pips, lvl, mx], 14, Color(1.0, 0.82, 0.36))
		var buy := _button(card, "MÁXIMO" if lvl >= mx else "COMPRAR  %d" % cost, _buy_meta.bind(id), 0.0, 36)
		buy.disabled = lvl >= mx or SaveManager.total_coins < cost


func _render_curses() -> void:
	var current := String(SaveManager.settings.get("curse", "ninguna"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_content.add_child(grid)
	for def in ContentDB.curses:
		var id := String(def.get("id", ""))
		var selected := id == current
		var card := _card(grid, 300.0, Color(0.95, 0.48, 0.30) if selected else Color(0.22, 0.18, 0.20))
		_label(card, "%s%s" % ["▶ " if selected else "", String(def.get("name", id))], 20, Color(1.0, 0.72, 0.48) if selected else Color(1, 1, 1, 0.90))
		_label(card, String(def.get("desc", "")), 12, Color(1, 1, 1, 0.68))
		_label(card, "HP enemigo x%.2f   ·   Spawn x%.2f   ·   Monedas +%d%%" % [
			float(def.get("hp", 1.0)), float(def.get("spawn", 1.0)),
			int(round(float(def.get("coins", 0.0)) * 100.0)),
		], 11, Color(1.0, 0.86, 0.52, 0.86))
		var b := _button(card, "ACTIVA" if selected else "ACTIVAR", _select_curse.bind(id), 0.0, 36)
		if selected:
			_selected_button(b)


func _render_codex() -> void:
	var subnav := HBoxContainer.new()
	subnav.add_theme_constant_override("separation", 6)
	_content.add_child(subnav)
	var subs := [["armas", "ARMAS"], ["pasivas", "PASIVAS"], ["evoluciones", "EVOLUCIONES"], ["bestiario", "BESTIARIO"], ["reliquias", "RELIQUIAS"]]
	for pair in subs:
		var val := String(pair[0])
		var b := _button(subnav, String(pair[1]), _set_codex_sub.bind(val), 128, 34)
		b.add_theme_font_size_override("font_size", 12)
		if val == _codex_sub:
			_selected_button(b)
	match _codex_sub:
		"pasivas":
			_codex_passives()
		"evoluciones":
			_codex_evolutions()
		"bestiario":
			_codex_bestiary()
		"reliquias":
			_codex_relics()
		_:
			_codex_weapons()


func _codex_weapons() -> void:
	var evo_results := {}
	for e in ContentDB.evolutions:
		evo_results[String(e.get("result", ""))] = true
	_label(_content, "%d armas. Las marcadas con ★ son evoluciones que se desbloquean con nivel 8 + pasiva." % ContentDB.weapons.size(), 12, Color(0.70, 0.86, 1.0, 0.78))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	for id in ContentDB.weapons:
		var def: Dictionary = ContentDB.weapons[id]
		var evolved := evo_results.has(String(id))
		var card := _card(grid, 300.0, Color(0.62, 0.46, 0.18) if evolved else Color(0.16, 0.22, 0.27))
		_label(card, "%s%s" % ["★ " if evolved else "", String(def.get("display", id))], 16, Color(1.0, 0.86, 0.50) if evolved else Color(0.84, 1.0, 0.90))
		_label(card, "%s   ·   Daño %s   ·   Cadencia %s" % [
			_pattern_label(String(def.get("pattern", "nearest"))),
			_format_num(def.get("dmg", 0.0)), _format_num(def.get("interval", 0.0)),
		], 11, Color(0.68, 0.84, 1.0, 0.82))
		_label(card, String(def.get("note", "")), 11, Color(1, 1, 1, 0.60))


func _codex_passives() -> void:
	var passive_count := 0
	for u in ContentDB.upgrades:
		if String(u.get("effect", "")) != "weapon":
			passive_count += 1
	_label(_content, "%d pasivas. Se ofrecen en las cartas de nivel y potencian el build de la run." % passive_count, 12, Color(0.70, 0.86, 1.0, 0.78))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	for u in ContentDB.upgrades:
		if String(u.get("effect", "")) == "weapon":
			continue
		var rarity := String(u.get("rarity", "comun"))
		var card := _card(grid, 300.0, RARITY_COLORS.get(rarity, Color(0.16, 0.22, 0.27)))
		_label(card, String(u.get("name", "")), 15, Color(1, 1, 1, 0.90))
		_label(card, String(u.get("desc", "")), 11, Color(1, 1, 1, 0.64))
		_label(card, "%s · máx. %d" % [rarity.to_upper(), int(u.get("max", 1))], 10, RARITY_COLORS.get(rarity, Color.WHITE))


func _codex_evolutions() -> void:
	_label(_content, "%d recetas. Sube el arma a nivel 8 y la pasiva indicada; la evolución aparecerá en las cartas." % ContentDB.evolutions.size(), 12, Color(0.70, 0.86, 1.0, 0.78))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	for e in ContentDB.evolutions:
		var base: Dictionary = ContentDB.weapons.get(String(e.get("base", "")), {})
		var result: Dictionary = ContentDB.weapons.get(String(e.get("result", "")), {})
		var card := _card(grid, 300.0, Color(0.58, 0.46, 0.20))
		_label(card, "★ %s" % String(e.get("name", "Evolución")), 16, Color(1.0, 0.86, 0.48))
		_label(card, "%s L%d + %s %s" % [
			String(base.get("display", e.get("base", ""))), int(e.get("weapon_level", 8)),
			_upgrade_name(String(e.get("passive", ""))), _roman(int(e.get("passive_levels", 1))),
		], 11, Color(0.72, 0.88, 1.0, 0.85))
		_label(card, "→ %s" % String(result.get("display", e.get("result", ""))), 13, Color(0.84, 1.0, 0.86))


func _codex_bestiary() -> void:
	_label(_content, "%d criaturas. Los jefes aparecen al agotar el tiempo de cada bioma." % ContentDB.enemies.size(), 12, Color(0.70, 0.86, 1.0, 0.78))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	for id in ContentDB.enemies:
		var def: Dictionary = ContentDB.enemies[id]
		var boss := bool(def.get("boss", false))
		var card := _card(grid, 230.0, Color(0.70, 0.26, 0.26) if boss else Color(0.16, 0.22, 0.27))
		_label(card, "%s%s" % ["☠ " if boss else "", String(def.get("display", id))], 14, Color(1.0, 0.62, 0.54) if boss else Color(0.86, 1.0, 0.92))
		_label(card, "HP %s · Vel %s · Daño %s" % [
			_format_num(def.get("hp", 0.0)), _format_num(def.get("speed", 0.0)), _format_num(def.get("dmg", 0.0)),
		], 10, Color(1, 1, 1, 0.60))


func _codex_relics() -> void:
	_label(_content, "Las reliquias son únicas por run y aparecen al derrotar jefes. Cada una combina una ventaja con un costo.", 12, Color(0.70, 0.86, 1.0, 0.78))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_content.add_child(grid)
	for relic in ContentDB.relics:
		var card := _card(grid, 300.0, RARITY_COLORS["legendario"])
		_label(card, String(relic.get("name", "")), 16, C_AMBER_SOFT)
		_label(card, String(relic.get("desc", "")), 11, Color(1, 1, 1, 0.72))


func _render_records() -> void:
	var stats := _card(_content, 0.0, Color(0.22, 0.34, 0.44))
	_label(stats, "HISTORIAL", 17, Color(0.74, 0.90, 1.0))
	_label(stats, "Partidas: %d   ·   Victorias: %d   ·   Bajas: %d   ·   Jefes: %d" % [
		SaveManager.runs_played, SaveManager.victories, SaveManager.total_kills, SaveManager.boss_kills,
	], 12, Color(1, 1, 1, 0.76))
	_label(stats, "RÉCORDS DE UNA PARTIDA", 13, Color(1.0, 0.86, 0.52))
	_label(stats, "Mejor tiempo %d:%02d   ·   Mejor nivel %d   ·   Ciclo máximo %d\nMás bajas %d   ·   Más daño %s   ·   Monedas por logros %d" % [
		int(SaveManager.best_time) / 60, int(SaveManager.best_time) % 60,
		SaveManager.best_level, SaveManager.best_loop,
		SaveManager.best_kills, _format_num(SaveManager.best_damage), SaveManager.achievement_coins,
	], 12, Color(1, 1, 1, 0.76))
	_label(stats, "Monedas ganadas: %d   ·   Monedas actuales: %d" % [
		SaveManager.coins_earned, SaveManager.total_coins,
	], 12, Color(0.84, 0.92, 1.0, 0.72))
	var unlocked := 0
	for a in ContentDB.achievements:
		if bool(SaveManager.achievements.get(String(a.get("id", "")), false)):
			unlocked += 1
	_label(_content, "LOGROS   %d/%d" % [unlocked, ContentDB.achievements.size()], 18, Color(0.64, 1.0, 0.74))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	for a in ContentDB.achievements:
		var id := String(a.get("id", ""))
		var got := bool(SaveManager.achievements.get(id, false))
		var stat := String(a.get("stat", ""))
		var goal := float(a.get("goal", 0.0))
		var value := _stat_value(stat)
		var card := _card(grid, 300.0, Color(0.30, 0.72, 0.44) if got else Color(0.16, 0.22, 0.27))
		_label(card, "%s %s" % ["✓" if got else "○", String(a.get("name", id))], 14, Color(0.62, 1.0, 0.72) if got else Color(1, 1, 1, 0.70))
		_label(card, String(a.get("desc", "")), 11, Color(1, 1, 1, 0.56))
		var reward := int(a.get("reward", 0))
		if reward > 0:
			_label(card, "Recompensa: ◈ %d%s" % [reward, "  (cobrada)" if got else ""], 10, Color(1.0, 0.84, 0.36, 0.86))
		if not got and goal > 0.0:
			_label(card, "Progreso: %s / %s" % [_format_num(minf(value, goal)), _format_num(goal)], 10, Color(0.76, 0.86, 1.0, 0.62))


func _render_settings() -> void:
	var perf := _card(_content, 0.0, Color(0.20, 0.30, 0.38))
	_label(perf, "RENDIMIENTO", 17, Color(0.74, 0.90, 1.0))
	_label(perf, "FPS objetivo", 12, Color(1, 1, 1, 0.66))
	_segmented(perf, FPS_OPTIONS, GameState.fps_limit, _set_fps)
	_label(perf, "Calidad gráfica", 12, Color(1, 1, 1, 0.66))
	_segmented(perf, QUALITY_OPTIONS, GameState.quality_mode, _set_quality)
	_label(perf, "Cámara", 12, Color(1, 1, 1, 0.66))
	_segmented(perf, CAMERA_OPTIONS, GameState.camera_mode, _set_camera)
	_label(perf, "Tier detectado: %s   ·   Balas %d   ·   Enemigos %d   ·   FX %d%%" % [
		GameState.device_tier.to_upper(), GameState.max_bullets, GameState.enemy_cap,
		int(round(GameState.fx_mult * 100.0)),
	], 10, Color(0.70, 0.86, 1.0, 0.62))

	var audio := _card(_content, 0.0, Color(0.28, 0.24, 0.36))
	_label(audio, "AUDIO", 17, Color(0.84, 0.74, 1.0))
	_slider_row(audio, "Música", int(SaveManager.settings.get("music_vol", 70)), _set_music_volume)
	_slider_row(audio, "Efectos", int(SaveManager.settings.get("sfx_vol", 85)), _set_sfx_volume)

	# Accesibilidad (roadmap 1.6) + layout táctil adaptable (roadmap 5.5).
	var acc := _card(_content, 0.0, Color(0.24, 0.34, 0.26))
	_label(acc, "ACCESIBILIDAD Y TÁCTIL", 17, Color(0.80, 1.0, 0.84))
	_label(acc, "Sacudida de cámara", 12, Color(1, 1, 1, 0.66))
	_segmented(acc, SHAKE_OPTIONS, GameState.screen_shake, _set_shake)
	_label(acc, "Hitstop en impactos (pausa breve al golpear)", 12, Color(1, 1, 1, 0.66))
	_segmented(acc, TOGGLE_OPTIONS, GameState.hitstop_enabled, _set_hitstop)
	_label(acc, "Números de daño flotantes", 12, Color(1, 1, 1, 0.66))
	_segmented(acc, TOGGLE_OPTIONS, GameState.show_damage, _set_damage_numbers)
	_label(acc, "Tamaño táctil del joystick y botones", 12, Color(1, 1, 1, 0.66))
	_segmented(acc, TOUCH_OPTIONS, GameState.touch_scale, _set_touch_scale)
	_label(acc, "Layout actual: %s" % JoystickLayer.layout_label(), 10, Color(0.70, 0.86, 1.0, 0.62))

	var info := _card(_content, 0.0, Color(0.16, 0.22, 0.27))
	_label(info, "CONTROLES", 15, Color(0.82, 1.0, 0.90))
	_label(info, "Joystick virtual: mitad izquierda. Saltar/dash: botones táctiles. Teclado: WASD/flechas, Espacio salta, Shift dash, C cámara, ESC pausa.", 11, Color(1, 1, 1, 0.62))
	if GameState.run_active:
		_primary(info, "▶  VOLVER AL JUEGO", func() -> void: resume_requested.emit(), 0.0, 44)


func _segmented(parent: Node, options: Array, current, action: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	for pair in options:
		var value = pair[0]
		var b := _button(row, String(pair[1]), action.bind(value), 96, 32)
		b.add_theme_font_size_override("font_size", 12)
		if value == current:
			_selected_button(b)


func _slider_row(parent: Node, title: String, value: int, action: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := _label(row, title, 12, Color(1, 1, 1, 0.70), false)
	l.custom_minimum_size.x = 70
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = value
	s.custom_minimum_size = Vector2(280, 26)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float) -> void: action.call(int(v)))
	row.add_child(s)


# ---------------- acciones de hub ----------------

func _select_char(id: String) -> void:
	GameState.select_character(id)
	AudioManager.play_sfx("pickup", 1.15)
	refresh()


func _select_curse(id: String) -> void:
	GameState.select_curse(id)
	AudioManager.play_sfx("pickup", 1.2)
	refresh()


func _select_contract(id: String) -> void:
	if GameState.select_contract(id):
		AudioManager.play_sfx("pickup", 1.2)
	refresh()


func _buy_meta(id: String) -> void:
	if GameState.buy_meta(id):
		AudioManager.play_sfx("levelup", 1.25)
	refresh()


func _set_codex_sub(sub: String) -> void:
	_codex_sub = sub
	AudioManager.play_sfx("pickup", 1.1)
	refresh()


func _set_fps(value: int) -> void:
	GameState.set_fps_limit(value)
	SaveManager.save_settings({"fps_limit": value})
	AudioManager.play_sfx("pickup", 1.15)
	refresh()


func _set_quality(mode: String) -> void:
	GameState.set_quality_mode(mode)
	SaveManager.save_settings({"quality": mode})
	AudioManager.play_sfx("pickup", 1.15)
	refresh()


func _set_camera(mode: String) -> void:
	GameState.set_camera_mode(mode)
	SaveManager.save_settings({"camera_mode": mode})
	AudioManager.play_sfx("pickup", 1.15)
	refresh()


func _set_shake(v: float) -> void:
	GameState.set_screen_shake(v)
	AudioManager.play_sfx("pickup", 1.15)
	refresh()


func _set_hitstop(v: bool) -> void:
	GameState.set_hitstop_enabled(v)
	AudioManager.play_sfx("pickup", 1.15)
	refresh()


func _set_damage_numbers(v: bool) -> void:
	GameState.set_show_damage(v)
	AudioManager.play_sfx("pickup", 1.15)
	refresh()


func _set_touch_scale(v: float) -> void:
	GameState.set_touch_scale(v)
	AudioManager.play_sfx("pickup", 1.15)
	refresh()


func _set_music_volume(v: int) -> void:
	AudioManager.set_music_volume(v)
	SaveManager.save_settings({"music_vol": v})


func _set_sfx_volume(v: int) -> void:
	AudioManager.set_sfx_volume(v)
	SaveManager.save_settings({"sfx_vol": v})


# ---------------- utilidades de texto ----------------

func _pattern_label(p: String) -> String:
	match p:
		"nearest":
			return "Auto-aim"
		"orbit":
			return "Órbita"
		"aura":
			return "Aura"
		"boomerang":
			return "Bumerán"
		"mine":
			return "Minas"
		"chain":
			return "Cadena"
		"spiral":
			return "Espiral"
		"slam":
			return "Onda sísmica"
		"meteor":
			return "Meteoro"
		"drone":
			return "Dron"
		"void":
			return "Singularidad"
		_:
			return p.capitalize()


func _format_num(v) -> String:
	var f := float(v)
	if absf(f - round(f)) < 0.01:
		return str(int(round(f)))
	return "%.1f" % f


func _roman(n: int) -> String:
	var vals := [10, 9, 5, 4, 1]
	var syms := ["X", "IX", "V", "IV", "I"]
	var out := ""
	var x := clampi(n, 1, 10)
	for i in vals.size():
		while x >= int(vals[i]):
			out += String(syms[i])
			x -= int(vals[i])
	return out


func _upgrade_name(id: String) -> String:
	for u in ContentDB.upgrades:
		if String(u.get("id", "")) == id:
			return String(u.get("name", id))
	return id


func _stat_value(stat: String) -> float:
	match stat:
		"total_kills":
			return float(SaveManager.total_kills)
		"boss_kills":
			return float(SaveManager.boss_kills)
		"victories":
			return float(SaveManager.victories)
		"best_time":
			return SaveManager.best_time
		"coins_earned":
			return float(SaveManager.coins_earned)
		"runs_played":
			return float(SaveManager.runs_played)
		"best_level":
			return float(SaveManager.best_level)
		"best_kills":
			return float(SaveManager.best_kills)
		"best_damage":
			return SaveManager.best_damage
		"best_loop":
			return float(SaveManager.best_loop)
		_:
			return 0.0
