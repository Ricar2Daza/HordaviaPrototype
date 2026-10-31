## HUD — retícula táctil: timer, HP, XP, kills + tarjetas de level-up + Game Over.
## Autoload CanvasLayer con PROCESS_MODE_ALWAYS para que la UI viva con el árbol pausado.
extends CanvasLayer

const RARITY_COLORS := {
	"comun": Color(0.75, 0.75, 0.78),
	"raro": Color(0.35, 0.55, 0.9),
	"epico": Color(0.62, 0.35, 0.9),
	"legendario": Color(0.9, 0.7, 0.2),
}

var _time_label: Label
var _level_label: Label
var _kills_label: Label
var _hp_bar: ProgressBar
var _xp_bar: ProgressBar
var _coins_label: Label

var _levelup_root: Control
var _levelup_title: Label
var _levelup_cards: HBoxContainer
var _levelup_footer: HBoxContainer
var _reroll_btn: Button
var _skip_btn: Button
var _render_choices: Array = []

var _over_root: Control
var _over_title: Label
var _over_stats: Label
var _vig: ColorRect
var _vig_flash := 0.0
var _fade: ColorRect
var _fade_t := 0.0
var _biome_label: Label
var _biome_t := 0.0
var _boss_bar: ProgressBar
var _boss_label: Label

# Menú de pausa (ESC / móvil)
var _menu_root: Control
var _menu_btn: Button
var _menu_open := false
var _paused_before_menu := false
var _cam_btn: Button

# Pantalla de inicio / hub clásico con submenús (roadmap 4.1–4.2)
var _start_root: Control
var _hub_margin: MarginContainer
var _hub_nav: HBoxContainer
var _hub_nav_buttons := {}
var _hub_coins: Label
var _hub_title: Label
var _hub_sub: Label
var _hub_content: VBoxContainer
var _hub_resume_btn: Button
var _hub_tab := "jugar"
var _hub_codex_sub := "armas"
var _weather_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_hud()
	_build_fade()
	_build_levelup()
	_build_game_over()
	_build_start()
	GameState.xp_changed.connect(_on_xp)
	GameState.hp_changed.connect(_on_hp)
	GameState.leveled.connect(_on_leveled)
	GameState.run_ended.connect(_on_run_ended)
	GameState.run_started.connect(_on_run_started)
	SaveManager.achievements_unlocked.connect(_on_achievements_unlocked)
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	var qa_tab := OS.get_environment("HORDAVIA_OPEN_TAB")
	if not qa_tab.is_empty():
		_open_start(qa_tab)
	elif not GameState.debug_auto_upgrade and not GameState.auto_start_next:
		_open_start()
	# Tras apply_saved_display (diferido de GameState) refrescar textos de opciones.
	call_deferred("_refresh_start")


# ---------------- HUD base ----------------

func _build_hud() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_time_label = _label(root, 28, Color(1, 1, 1))
	_time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_label.position = Vector2(-40, 12)

	_level_label = _label(root, 18, Color(0.7, 1, 0.75))
	_level_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_level_label.position = Vector2(16, 44)

	_kills_label = _label(root, 16, Color(1, 0.85, 0.6))
	_kills_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_kills_label.position = Vector2(16, 72)

	_weather_label = _label(root, 13, Color(0.62, 0.86, 1.0))
	_weather_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_weather_label.position = Vector2(16, 98)
	_weather_label.text = ""

	_coins_label = _label(root, 16, Color(1, 0.95, 0.4))
	_coins_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_coins_label.position = Vector2(-140, 72)
	_coins_label.set_anchor_and_offset(SIDE_LEFT, 1.0, -140)
	_coins_label.set_anchor_and_offset(SIDE_RIGHT, 1.0, -24)

	_hp_bar = _bar(root, Color(0.85, 0.25, 0.3), Vector2(16, 14), Vector2(240, 16))

	_xp_bar = _bar(root, Color(0.3, 0.9, 0.5), Vector2(0, 0), Vector2(0, 0), true)

	_vig = ColorRect.new()
	_vig.color = Color(0.8, 0.08, 0.08, 0.0)
	_vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vig)

	_biome_label = Label.new()
	_biome_label.add_theme_font_size_override("font_size", 34)
	_biome_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_biome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_biome_label.text = ""
	_biome_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_biome_label.position = Vector2(-220, 52)
	_biome_label.size = Vector2(440, 44)
	add_child(_biome_label)
	GameState.biome_changed.connect(_on_biome_changed)

	# Barra del jefe (roadmap 3.4)
	_boss_label = _label(root, 20, Color(1.0, 0.5, 0.45))
	_boss_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_label.position = Vector2(-160, 96)
	_boss_label.size = Vector2(320, 26)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_bar = _bar(root, Color(0.9, 0.2, 0.2), Vector2(0, 0), Vector2(0, 0))
	_boss_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_boss_bar.anchor_left = 0.25
	_boss_bar.anchor_right = 0.75
	_boss_bar.offset_top = 122
	_boss_bar.offset_bottom = 136
	_boss_bar.value = 1.0
	_boss_bar.visible = false
	_boss_label.visible = false

	# Acceso al menú en cualquier pantalla (táctil y ratón), siempre visible en run.
	_menu_btn = Button.new()
	_menu_btn.text = "☰ MENÚ"
	_menu_btn.add_theme_font_size_override("font_size", 15)
	_menu_btn.custom_minimum_size = Vector2(96, 34)
	_menu_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_menu_btn.position = Vector2(-112, 12)
	_menu_btn.visible = false
	_menu_btn.pressed.connect(_toggle_menu)
	root.add_child(_menu_btn)
	_menu_btn.offset_left = -120
	_menu_btn.offset_right = -16
	_menu_btn.offset_top = 12
	_menu_btn.offset_bottom = 46

	_build_menu()


func _input(event: InputEvent) -> void:
	# Pausa con ESC/Start (no interfiere con cartas ni game over)
	if event.is_action_pressed("pause"):
		if _over_root.visible or _levelup_root.visible or _start_root.visible:
			return
		if _menu_open:
			_close_menu()
		else:
			_open_menu()


# ---------------- Menú de pausa ----------------

func _build_menu() -> void:
	_menu_root = Control.new()
	_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_root.visible = false
	add_child(_menu_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_root.add_child(dim)

	var panel := VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_constant_override("separation", 12)
	_menu_root.add_child(panel)

	var title := Label.new()
	title.text = "PAUSA"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	panel.add_child(_menu_button("Continuar", _close_menu))
	_cam_btn = _menu_button("", _toggle_camera)
	panel.add_child(_cam_btn)
	panel.add_child(_menu_button("Reiniciar partida", func() -> void:
		_close_menu()
		_restart()
	))
	panel.add_child(_menu_button("Opciones y códice", func() -> void:
		_close_menu()
		_open_start("ajustes")
	))
	panel.add_child(_menu_button("Menú principal", func() -> void:
		_close_menu()
		_open_start("jugar")
	))
	panel.add_child(_menu_button("Salir del juego", func() -> void:
		get_tree().quit()
	))


func _menu_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(320, 52)
	b.pressed.connect(action)
	return b


func _toggle_camera() -> void:
	GameState.set_camera_mode("mouse" if GameState.camera_mode == "fija" else "fija")
	_cam_btn.text = "Cámara: %s  [C]" % ("Mouse" if GameState.camera_mode == "mouse" else "Fija")


func _notification(what: int) -> void:
	## Ciclo de vida (roadmap 5.3): al perder foco se pausa y se muestra el menú;
	## al volver NO se reanuda sola: el jugador decide cuándo continuar.
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_on_app_focus_lost()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_on_app_resumed()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Botón atrás de Android: pausa/reanuda en vez de cerrar la app.
			if ((_start_root != null and _start_root.visible)
					or (_levelup_root != null and _levelup_root.visible)
					or (_over_root != null and _over_root.visible)):
				return
			if _menu_open:
				_close_menu()
			elif GameState.run_active:
				_open_menu()


func _on_app_focus_lost() -> void:
	_mute_music(true)
	if not GameState.run_active:
		return
	# En Android el proceso puede morir: guardar siempre antes de perder foco.
	if not GameState.debug_auto_upgrade:
		SaveManager.save_all()
	if _levelup_root.visible or _over_root.visible or _start_root.visible:
		get_tree().paused = true
		return
	if not _menu_open:
		_open_menu()
		AudioManager.play_sfx("pickup", 0.8)


func _on_app_resumed() -> void:
	_mute_music(false)


func _mute_music(muted: bool) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)


func _open_menu() -> void:
	_menu_open = true
	_paused_before_menu = get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # puntero libre para los botones
	_cam_btn.text = "Cámara: %s  [C]" % ("Mouse" if GameState.camera_mode == "mouse" else "Fija")
	_menu_root.visible = true


func _toggle_menu() -> void:
	if _menu_open:
		_close_menu()
	elif GameState.run_active:
		_open_menu()


func _close_menu() -> void:
	_menu_open = false
	get_tree().paused = _paused_before_menu
	if GameState.camera_mode == "mouse":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_menu_root.visible = false


func _build_fade() -> void:
	# Fundido de transición de bioma (roadmap 3.2), debajo de cartas y game over
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _on_biome_changed(b: Dictionary) -> void:
	_biome_t = 3.0
	_fade_t = 0.9
	var extra := ""
	if GameState.endless_loop > 0:
		extra = " · Ciclo %d" % (GameState.endless_loop + 1)
	var w: Dictionary = b.get("weather", {}) if b.get("weather", {}) is Dictionary else {}
	_biome_label.text = "- %s · %s%s -" % [String(b.get("name", "")), String(w.get("label", "")), extra]


func _apply_safe_area() -> void:
	## Safe area / notch (roadmap 5.2): mueve HUD fuera de la zona no segura.
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
	_hp_bar.position = Vector2(16 + left, 14 + top)
	_time_label.position = Vector2(-40, 12 + top)
	_level_label.position = Vector2(16 + left, 44 + top)
	_kills_label.position = Vector2(16 + left, 72 + top)
	_weather_label.position = Vector2(16 + left, 98 + top)
	_coins_label.offset_top = 72 + top
	_coins_label.offset_bottom = 96 + top
	_coins_label.offset_left = -140 - right
	_coins_label.offset_right = -24 - right
	_xp_bar.offset_top = 4 + top
	_xp_bar.offset_bottom = 14 + top
	_boss_label.position = Vector2(-160, 96 + top)
	_boss_bar.offset_top = 122 + top
	_boss_bar.offset_bottom = 136 + top
	_menu_btn.offset_left = -120 - right
	_menu_btn.offset_right = -16 - right
	_menu_btn.offset_top = 12 + top
	_menu_btn.offset_bottom = 46 + top
	_layout_levelup()
	if _over_title != null:
		_over_title.add_theme_font_size_override("font_size", int(clampf(vs.x / 1280.0 * 40.0, 26.0, 40.0)))
	if _over_stats != null:
		_over_stats.add_theme_font_size_override("font_size", int(clampf(vs.x / 1280.0 * 22.0, 15.0, 22.0)))


func _layout_levelup() -> void:
	## Cartas y título adaptados a 5", 6.5" y tablet (roadmap 5.5).
	if _levelup_title == null or _levelup_cards == null or _levelup_footer == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var cs := _card_size()
	var title_w := minf(vs.x - 48.0, 560.0)
	_levelup_title.position = Vector2(-title_w * 0.5, clampf(vs.y * 0.12, 60.0, 110.0))
	_levelup_title.size = Vector2(title_w, 54.0)
	_levelup_title.add_theme_font_size_override("font_size", int(clampf(vs.x / 1280.0 * 30.0, 20.0, 30.0)))
	_levelup_cards.add_theme_constant_override("separation", int(clampf(vs.x / 1280.0 * 24.0, 10.0, 24.0)))
	var footer_w := minf(vs.x - 48.0, 460.0)
	_levelup_footer.position = Vector2(-footer_w * 0.5, cs.y * 0.5 + 18.0)
	_levelup_footer.size = Vector2(footer_w, 54.0)
	var btn_w := clampf((footer_w - 18.0) * 0.5, 140.0, 190.0)
	if _reroll_btn != null:
		_reroll_btn.custom_minimum_size = Vector2(btn_w, 46)
	if _skip_btn != null:
		_skip_btn.custom_minimum_size = Vector2(btn_w, 46)


func _card_size() -> Vector2:
	var vs := get_viewport().get_visible_rect().size
	var w := clampf((vs.x - 120.0) / 3.0, 200.0, 300.0)
	return Vector2(w, clampf(w * 0.73, 170.0, 220.0))


func _label(parent: Control, size: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Control, c: Color, pos: Vector2, size: Vector2, full_width: bool = false) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.value = 1.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if full_width:
		b.set_anchors_preset(Control.PRESET_TOP_WIDE)
		b.custom_minimum_size = Vector2(0, 10)
		b.position = Vector2(0, 4)
		b.anchor_right = 1.0
	else:
		b.position = pos
		b.custom_minimum_size = size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.16, 0.85)
	sb.set_corner_radius_all(4)
	b.add_theme_stylebox_override("background", sb)
	var fg := StyleBoxFlat.new()
	fg.bg_color = c
	fg.set_corner_radius_all(4)
	b.add_theme_stylebox_override("fill", fg)
	parent.add_child(b)
	return b


func _process(_dt: float) -> void:
	if _menu_btn != null:
		_menu_btn.visible = (GameState.run_active and not _menu_open
			and not _over_root.visible and not _levelup_root.visible
			and not _start_root.visible)
	if GameState.run_active:
		var t := int(GameState.run_time)
		_time_label.text = "%d:%02d" % [t / 60, t % 60]
		_kills_label.text = "Bajas: %d" % GameState.kills
		_level_label.text = "Nivel %d  (XP %d/%d)" % [GameState.level, GameState.xp, GameState.xp_to_next(GameState.level)]
		_coins_label.text = "Monedas: %d" % GameState.coins
		_weather_label.text = "Clima: %s · Bioma %d/%d" % [
			GameState.weather_name, GameState.biome_index + 1, maxi(ContentDB.biomes.size(), 1),
		]
		_weather_label.visible = true
	else:
		_weather_label.visible = false
	# Banner de bioma: aparece 3 s al cambiar
	if _biome_t > 0.0:
		_biome_t = maxf(_biome_t - _dt, 0.0)
		_biome_label.modulate.a = clampf(_biome_t / 0.8, 0.0, 1.0)
	else:
		_biome_label.modulate.a = 0.0
	# Fundido de transición de bioma (roadmap 3.2)
	if _fade_t > 0.0:
		_fade_t = maxf(_fade_t - _dt, 0.0)
		_fade.color.a = sin((1.0 - _fade_t / 0.9) * PI) * 0.55
	elif _fade.color.a != 0.0:
		_fade.color.a = 0.0
	# Viñeta de daño: flash por golpe + pulso persistente con vida baja (roadmap 1.7)
	_vig_flash = maxf(_vig_flash - _dt * 1.2, 0.0)
	var pulse := 0.0
	if GameState.run_active and GameState.hp_ratio() < 0.3:
		pulse = 0.10 + 0.06 * absf(sin(Time.get_ticks_msec() * 0.006))
	var a := maxf(_vig_flash, pulse)
	_vig.color.a = a
	# Barra del jefe: visible mientras haya un boss activo (roadmap 3.4)
	var boss_alive: bool = EnemyManager.boss_active()
	if boss_alive != _boss_bar.visible:
		_boss_bar.visible = boss_alive
		_boss_label.visible = boss_alive
	if boss_alive:
		_boss_bar.value = EnemyManager.boss_ref.hp / maxf(EnemyManager.boss_ref.max_hp, 1.0)
		var def: Dictionary = ContentDB.enemies.get(String(EnemyManager.boss_ref.kind), {})
		_boss_label.text = String(def.get("display", "JEFE")).to_upper()


# ---------------- Level-up ----------------

func _build_levelup() -> void:
	_levelup_root = Control.new()
	_levelup_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_levelup_root.visible = false
	_levelup_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_levelup_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_levelup_root.add_child(dim)

	_levelup_title = Label.new()
	_levelup_title.text = "¡NIVEL COMPLETADO! — elige una mejora"
	_levelup_title.add_theme_font_size_override("font_size", 30)
	_levelup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_levelup_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_levelup_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_levelup_title.position = Vector2(-250, 100)
	_levelup_title.size = Vector2(500, 50)
	_levelup_root.add_child(_levelup_title)

	_levelup_cards = HBoxContainer.new()
	_levelup_cards.add_theme_constant_override("separation", 24)
	_levelup_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_levelup_cards.set_anchors_preset(Control.PRESET_CENTER)
	_levelup_cards.anchor_left = 0.5
	_levelup_cards.anchor_right = 0.5
	_levelup_cards.anchor_top = 0.5
	_levelup_cards.anchor_bottom = 0.5
	_levelup_cards.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_levelup_cards.grow_vertical = Control.GROW_DIRECTION_BOTH
	_levelup_root.add_child(_levelup_cards)

	# Pie de cartas: consumibles por run (roadmap 2.3)
	_levelup_footer = HBoxContainer.new()
	_levelup_footer.add_theme_constant_override("separation", 18)
	_levelup_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_levelup_footer.set_anchors_preset(Control.PRESET_CENTER)
	_levelup_footer.position = Vector2(-230, 152)
	_levelup_footer.size = Vector2(460, 54)
	_levelup_root.add_child(_levelup_footer)

	_reroll_btn = Button.new()
	_reroll_btn.add_theme_font_size_override("font_size", 18)
	_reroll_btn.custom_minimum_size = Vector2(190, 46)
	_reroll_btn.pressed.connect(_reroll)
	_levelup_footer.add_child(_reroll_btn)

	_skip_btn = Button.new()
	_skip_btn.add_theme_font_size_override("font_size", 18)
	_skip_btn.custom_minimum_size = Vector2(190, 46)
	_skip_btn.text = "Saltar (+15 XP)"
	_skip_btn.pressed.connect(_skip)
	_levelup_footer.add_child(_skip_btn)


func _on_leveled(choices: Array) -> void:
	# Guardia para headless/smoke: aplicar automático (una UI pausada bloquearía la run)
	if GameState.debug_auto_upgrade:
		if not choices.is_empty():
			GameState.apply_upgrade(choices[0])
		return
	GameState.overlay_open = true
	_levelup_root.visible = true
	get_tree().paused = true
	if GameState.card_source == "cofre":
		_levelup_title.text = "¡COFRE ABIERTO! — elige una mejora"
	else:
		_levelup_title.text = "¡NIVEL %d! — elige una mejora" % GameState.level
	_render_cards(choices)


## Dibuja (o redibuja) las cartas actuales + refresca los consumibles.
func _render_cards(choices: Array) -> void:
	_render_choices = choices
	for c in _levelup_cards.get_children():
		_levelup_cards.remove_child(c)
		c.queue_free()
	var cs := _card_size()
	for u in choices:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		var btn := Button.new()
		btn.custom_minimum_size = cs
		btn.text = "%s\n\n%s" % [String(u["name"]), String(u["desc"])]
		btn.add_theme_font_size_override("font_size", int(clampf(cs.x * 0.073, 16.0, 22.0)))
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var rarity := String(u.get("rarity", "comun"))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.14, 0.2)
		sb.set_border_width_all(4)
		sb.border_color = RARITY_COLORS.get(rarity, Color.WHITE)
		sb.set_corner_radius_all(10)
		btn.add_theme_stylebox_override("normal", sb)
		btn.pressed.connect(_choose_upgrade.bind(u))
		col.add_child(btn)
		var ban := Button.new()
		ban.text = "Desterrar (%d)" % GameState.banishes
		ban.add_theme_font_size_override("font_size", int(clampf(cs.x * 0.05, 13.0, 15.0)))
		ban.custom_minimum_size = Vector2(cs.x, 34)
		ban.disabled = not GameState.can_banish() or choices.size() <= 1
		ban.pressed.connect(_banish.bind(String(u["id"])))
		col.add_child(ban)
		_levelup_cards.add_child(col)
	_layout_levelup()
	_update_footer()


func _update_footer() -> void:
	if _reroll_btn == null:
		return
	_reroll_btn.text = "Reroll (%d)" % GameState.rerolls
	_reroll_btn.disabled = not GameState.can_reroll()


func _reroll() -> void:
	if not GameState.use_reroll():
		return
	var choices := ContentDB.roll_upgrades(GameState.upgrade_counts)
	if choices.is_empty():
		return
	AudioManager.play_sfx("pickup", 1.25)
	_render_cards(choices)


func _banish(id: String) -> void:
	if not GameState.banish_card(id):
		_update_footer()
		return
	var remaining: Array = []
	for u in _render_choices:
		if String(u.get("id", "")) != id:
			remaining.append(u)
	if remaining.is_empty():
		return
	AudioManager.play_sfx("hit", 0.7)
	_render_cards(remaining)


func _skip() -> void:
	_close_levelup()
	GameState.add_xp(15)


func _close_levelup() -> void:
	_levelup_root.visible = false
	GameState.overlay_open = false
	get_tree().paused = false


func _choose_upgrade(u: Dictionary) -> void:
	_close_levelup()
	GameState.apply_upgrade(u)


# ---------------- Game over ----------------

func _build_game_over() -> void:
	_over_root = Control.new()
	_over_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over_root.visible = false
	add_child(_over_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over_root.add_child(dim)

	var panel := VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_constant_override("separation", 14)
	_over_root.add_child(panel)

	_over_title = Label.new()
	_over_title.add_theme_font_size_override("font_size", 40)
	_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_over_title)

	_over_stats = Label.new()
	_over_stats.add_theme_font_size_override("font_size", 22)
	_over_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_over_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_over_stats)

	var restart := Button.new()
	restart.text = "Jugar otra vez"
	restart.add_theme_font_size_override("font_size", 26)
	restart.custom_minimum_size = Vector2(280, 70)
	restart.pressed.connect(_restart)
	panel.add_child(restart)

	var to_menu := Button.new()
	to_menu.text = "Volver al menú"
	to_menu.add_theme_font_size_override("font_size", 20)
	to_menu.custom_minimum_size = Vector2(280, 54)
	to_menu.pressed.connect(func() -> void: _open_start("jugar"))
	panel.add_child(to_menu)


## Hub clásico modular (Jugar / Personajes / Tienda / Maldiciones / Códice / Logros / Ajustes).
func _build_start() -> void:
	_start_root = Control.new()
	_start_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_start_root.visible = false
	_start_root.set_script(load("res://ui/hub_menu.gd"))
	add_child(_start_root)
	_start_root.connect("play_requested", _play)
	_start_root.connect("resume_requested", _resume_run)
	_start_root.connect("quit_requested", func() -> void: get_tree().quit())
	_start_root.call("setup")


func _refresh_start() -> void:
	if _start_root != null:
		_start_root.call("refresh")


func _open_start(tab: String = "jugar") -> void:
	_over_root.visible = false
	_levelup_root.visible = false
	_menu_root.visible = false
	_menu_open = false
	_start_root.visible = true
	_start_root.call("select_tab", tab)
	_start_root.call("refresh")
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _play() -> void:
	_start_root.visible = false
	get_tree().paused = false
	GameState.overlay_open = false
	if GameState.camera_mode == "mouse":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameState.start_run()


func _resume_run() -> void:
	_start_root.visible = false
	_menu_root.visible = false
	_menu_open = false
	GameState.overlay_open = false
	get_tree().paused = false
	if GameState.camera_mode == "mouse":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_achievements_unlocked(list: Array) -> void:
	if list.is_empty():
		return
	var names: Array[String] = []
	for a in list:
		names.append(String(a.get("name", "")))
	_biome_label.text = "LOGRO: %s" % ", ".join(names)
	_biome_t = 3.5
	if _start_root.visible:
		_refresh_start()
	AudioManager.play_sfx("levelup", 1.4)
	GameState.haptic(0.6, 55)


func _on_run_ended(result: Dictionary) -> void:
	_start_root.visible = false
	_menu_root.visible = false
	_menu_open = false
	_over_root.visible = true
	var mins := int(result["time"]) / 60
	var secs := int(result["time"]) % 60
	_over_title.text = "¡VICTORIA!" if bool(result["victory"]) else "GAME OVER"
	_over_stats.text = "Tiempo: %d:%02d   Nivel: %d   Bajas: %d   Monedas: %d\nMejor tiempo: %d:%02d   Monedas totales: %d" % [
		mins, secs, int(result["level"]), int(result["kills"]), int(result["coins"]),
		int(SaveManager.best_time) / 60, int(SaveManager.best_time) % 60, SaveManager.total_coins,
	]


func _restart() -> void:
	_over_root.visible = false
	_start_root.visible = false
	GameState.start_run()


func _on_run_started() -> void:
	_over_root.visible = false
	_levelup_root.visible = false
	_start_root.visible = false
	_menu_root.visible = false
	GameState.overlay_open = false
	_menu_open = false


func _on_xp(xp: int, needed: int) -> void:
	_xp_bar.value = float(xp) / float(maxi(needed, 1))


var _last_hp_ui := 100.0

func _on_hp(hp: float, max_hp: float) -> void:
	if hp < _last_hp_ui - 0.01:
		_vig_flash = 0.45
	_last_hp_ui = hp
	_hp_bar.value = hp / maxf(max_hp, 1.0)
