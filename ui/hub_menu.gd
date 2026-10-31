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
const HAPTIC_OPTIONS := [[true, "Sí"], [false, "No"]]

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


func setup() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	var bg := ColorRect.new()
	bg.color = Color(0.018, 0.025, 0.040, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	grad.colors = PackedColorArray([
		Color(0.03, 0.10, 0.10, 1.0),
		Color(0.04, 0.04, 0.09, 1.0),
		Color(0.10, 0.035, 0.08, 1.0),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 512
	gt.height = 512
	var tex := TextureRect.new()
	tex.texture = gt
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex)

	var watermark := Label.new()
	watermark.text = "HORDAVIA"
	watermark.add_theme_font_size_override("font_size", 150)
	watermark.add_theme_color_override("font_color", Color(0.65, 1.0, 0.8, 0.035))
	watermark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	watermark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	watermark.set_anchors_preset(Control.PRESET_FULL_RECT)
	watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(watermark)


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
	brand.add_theme_constant_override("separation", 0)
	header.add_child(brand)
	var logo := Label.new()
	logo.text = "HORDAVIA"
	logo.add_theme_font_size_override("font_size", 38)
	logo.add_theme_color_override("font_color", Color(0.82, 1.0, 0.88))
	brand.add_child(logo)
	var tag := Label.new()
	tag.text = "SUPERVIVENCIA SIN FIN  ·  HUB DE EXPEDICIONES"
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", Color(0.62, 0.80, 0.76, 0.82))
	brand.add_child(tag)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_resume_btn = _button(header, "▶  VOLVER AL JUEGO", func() -> void: resume_requested.emit(), 190, 42)
	_resume_btn.add_theme_stylebox_override("normal", _style(Color(0.10, 0.26, 0.18, 0.95), Color(0.40, 0.90, 0.58), 2))
	_resume_btn.add_theme_color_override("font_color", Color(0.80, 1.0, 0.86))
	_resume_btn.visible = false

	_coins = Label.new()
	_coins.add_theme_font_size_override("font_size", 20)
	_coins.add_theme_color_override("font_color", Color(1.0, 0.86, 0.34))
	_coins.custom_minimum_size.x = 190
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_coins)

	var accent := ColorRect.new()
	accent.color = Color(0.22, 0.62, 0.52, 0.65)
	accent.custom_minimum_size = Vector2(0, 2)
	shell.add_child(accent)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	shell.add_child(nav)
	for id in TAB_IDS:
		var b := _button(nav, String(NAV_LABELS[id]), select_tab.bind(id), 124, 38)
		b.add_theme_font_size_override("font_size", 12)
		_nav_buttons[id] = b
	var quit := _button(nav, "SALIR", func() -> void: quit_requested.emit(), 76, 38)
	quit.add_theme_font_size_override("font_size", 12)
	quit.add_theme_color_override("font_color", Color(1.0, 0.58, 0.52))

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(Color(0.035, 0.045, 0.065, 0.94), Color(0.18, 0.27, 0.32, 0.85), 1, 10))
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
	_title.add_theme_color_override("font_color", Color(0.88, 1.0, 0.92))
	body.add_child(_title)

	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.add_theme_color_override("font_color", Color(0.70, 0.80, 0.84, 0.80))
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
	footer.text = "WASD / joystick / mando · C cambia cámara · ESC o ☰ pausa · Todo el progreso se guarda solo"
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.38))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shell.add_child(footer)


func _apply_safe_area() -> void:
	if _margin == null:
		return
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return
	var vs := get_viewport().get_visible_rect().size
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
	if width > 0.0:
		b.custom_minimum_size.x = width
	b.custom_minimum_size.y = height
	b.add_theme_stylebox_override("normal", _style(Color(0.08, 0.10, 0.14, 0.92), Color(0.20, 0.26, 0.30), 1))
	b.add_theme_stylebox_override("hover", _style(Color(0.12, 0.17, 0.20, 0.96), Color(0.35, 0.62, 0.52), 1))
	b.add_theme_stylebox_override("pressed", _style(Color(0.10, 0.22, 0.18, 1.0), Color(0.45, 0.90, 0.62), 2))
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _primary(parent: Node, text: String, action: Callable, width: float = 0.0, height: float = 52.0) -> Button:
	var b := _button(parent, text, action, width, height)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(0.04, 0.10, 0.07))
	b.add_theme_stylebox_override("normal", _style(Color(0.38, 0.78, 0.56), Color(0.68, 1.0, 0.80), 2))
	b.add_theme_stylebox_override("hover", _style(Color(0.50, 0.92, 0.66), Color(0.85, 1.0, 0.90), 2))
	b.add_theme_stylebox_override("pressed", _style(Color(0.26, 0.62, 0.44), Color(0.70, 1.0, 0.80), 2))
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


func _card(parent: Node, min_width: float = 0.0, border: Color = Color(0.16, 0.22, 0.27)) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(0.055, 0.070, 0.095, 0.88), border, 1, 8))
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
	b.add_theme_stylebox_override("normal", _style(Color(0.08, 0.22, 0.16, 1.0), Color(0.42, 0.95, 0.64), 2))
	b.add_theme_color_override("font_color", Color(0.78, 1.0, 0.86))


func _unselected_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _style(Color(0.08, 0.10, 0.14, 0.92), Color(0.20, 0.26, 0.30), 1))
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.86))


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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(row)

	var left := _card(row, 0.0, Color(0.20, 0.38, 0.31))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(left, "EXPEDICIÓN", 24, Color(0.82, 1.0, 0.88))
	_label(left, "Sobrevive sin límite de tiempo. Cada 6 minutos el mundo cambia de bioma, el clima se vuelve hostil y los jefes escalan. Solo la muerte termina la partida.", 13, Color(1, 1, 1, 0.72))

	var ch: Dictionary = ContentDB.characters.get(SaveManager.character, {})
	var cur: Dictionary = {}
	for c in ContentDB.curses:
		if String(c.get("id", "")) == String(SaveManager.settings.get("curse", "ninguna")):
			cur = c
			break
	_label(left, "PERSONAJE · %s" % String(ch.get("name", "Vagabundo")), 17, Color(0.66, 1.0, 0.78))
	_label(left, "HP %d   ·   Velocidad %.1f   ·   Daño x%.2f   ·   Cadencia x%.2f\n%s" % [
		int(ch.get("hp", 100)), float(ch.get("speed", 6.0)),
		float(ch.get("dmg", 1.0)), float(ch.get("fire", 1.0)), String(ch.get("desc", "")),
	], 12, Color(1, 1, 1, 0.70))
	_label(left, "MALDICIÓN · %s" % String(cur.get("name", "Sin maldición")), 17, Color(1.0, 0.72, 0.46))
	_label(left, "%s\nRecompensa de monedas: +%d%%" % [
		String(cur.get("desc", "Experiencia estándar")), int(round(float(cur.get("coins", 0.0)) * 100.0)),
	], 12, Color(1, 1, 1, 0.66))

	if GameState.run_active:
		_primary(left, "▶  CONTINUAR PARTIDA", func() -> void: resume_requested.emit(), 0.0, 50)
		var new_run := _button(left, "Empezar una expedición nueva", func() -> void: play_requested.emit(), 0.0, 40)
		new_run.add_theme_font_size_override("font_size", 14)
	else:
		_primary(left, "EMPEZAR EXPEDICIÓN", func() -> void: play_requested.emit(), 0.0, 56)
	_label(left, "Récord: %d:%02d   ·   Bajas totales: %d   ·   Jefes: %d" % [
		int(SaveManager.best_time) / 60, int(SaveManager.best_time) % 60,
		SaveManager.total_kills, SaveManager.boss_kills,
	], 12, Color(0.68, 0.84, 1.0, 0.82))
	_label(left, "Armas %d · Evoluciones %d · Pasivas %d · Bestias %d" % [
		ContentDB.weapons.size(), ContentDB.evolutions.size(),
		ContentDB.upgrades.size(), ContentDB.enemies.size(),
	], 11, Color(1, 1, 1, 0.50))

	var right := _card(row, 450.0, Color(0.24, 0.27, 0.42))
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(right, "HORIZONTE DE 7 BIOMAS", 18, Color(0.74, 0.86, 1.0))
	_label(right, "El ciclo completo dura 42 minutos y vuelve a empezar con enemigos más fuertes.", 11, Color(1, 1, 1, 0.60))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	for i in ContentDB.biomes.size():
		var b: Dictionary = ContentDB.biomes[i]
		var w: Dictionary = b.get("weather", {}) if b.get("weather", {}) is Dictionary else {}
		var bv := _card(grid, 190.0, Color(0.16, 0.20, 0.30))
		_label(bv, "%d. %s" % [i + 1, String(b.get("name", ""))], 13, Color(0.84, 1.0, 0.90))
		_label(bv, "6 min · %s" % String(w.get("label", "Despejado")), 10, Color(0.68, 0.82, 0.94, 0.80))
	_label(right, "El clima ralentiza ligeramente el movimiento y reduce la visibilidad: aprovéchalo o sufre sus consecuencias.", 11, Color(1, 1, 1, 0.48))


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
	var subs := [["armas", "ARMAS"], ["pasivas", "PASIVAS"], ["evoluciones", "EVOLUCIONES"], ["bestiario", "BESTIARIO"]]
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


func _render_records() -> void:
	var stats := _card(_content, 0.0, Color(0.22, 0.34, 0.44))
	_label(stats, "HISTORIAL", 17, Color(0.74, 0.90, 1.0))
	_label(stats, "Partidas: %d   ·   Victorias: %d   ·   Bajas: %d   ·   Jefes: %d\nMejor tiempo: %d:%02d   ·   Monedas ganadas: %d   ·   Monedas actuales: %d" % [
		SaveManager.runs_played, SaveManager.victories, SaveManager.total_kills, SaveManager.boss_kills,
		int(SaveManager.best_time) / 60, int(SaveManager.best_time) % 60,
		SaveManager.coins_earned, SaveManager.total_coins,
	], 12, Color(1, 1, 1, 0.76))
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

	var mobile := _card(_content, 0.0, Color(0.20, 0.28, 0.24))
	_label(mobile, "MÓVIL", 17, Color(0.74, 1.0, 0.82))
	_label(mobile, "Vibración", 12, Color(1, 1, 1, 0.66))
	_segmented(mobile, HAPTIC_OPTIONS, GameState.haptics_enabled, _set_haptics)
	_label(mobile, "El joystick y los botones escalan con la pantalla y respetan el notch.", 10, Color(0.70, 1.0, 0.80, 0.62))

	var info := _card(_content, 0.0, Color(0.16, 0.22, 0.27))
	_label(info, "CONTROLES", 15, Color(0.82, 1.0, 0.90))
	_label(info, "Teclado: WASD/flechas, Espacio salta, Shift dash, C cámara, ESC pausa. Mando: stick izq. mover, A saltar, B dash, Y cámara, Start pausa, stick der. orbita (modo Mouse). Táctil: joystick + botones.", 11, Color(1, 1, 1, 0.62))
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


func _set_haptics(enabled: bool) -> void:
	GameState.set_haptics(enabled)
	if enabled:
		GameState.haptic(0.4, 30)
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
		_:
			return 0.0
