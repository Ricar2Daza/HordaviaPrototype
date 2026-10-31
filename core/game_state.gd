## GameState — estado de la run y progresión (guía §3.5/§3.6).
## Autoload. Señales para HUD; todo el gameplay lee stats desde aquí.
extends Node

signal xp_changed(xp: int, needed: int)
signal leveled(choices: Array)
signal hp_changed(hp: float, max_hp: float)
signal upgrades_changed
signal run_ended(result: Dictionary)
signal run_reset
signal run_started
signal biome_changed(b: Dictionary)
signal setting_changed
signal kill_event(pos: Vector3, elite: bool)

# --- Referencias globales de escena (registradas por world/Main) ---
var terrain = null                # mundo procedural con height_at(x, z) (world/terrain.gd)
var cam_ref: Camera3D = null
var arena_radius := 35.5          # radio jugable del mapa ampliado
var biome_name := ""              # bioma activo para HUD/hub
var biome_index := 0
var weather_name := "Despejado"   # clima activo para HUD
var weather_type := "clear"
var weather_speed_mult := 1.0     # penalización suave de movimiento por clima
var camera_mode := "fija"         # "fija" | "mouse" (WASD y joystick son cámara-relativos)
var haptics_enabled := true       # vibración móvil/mando (roadmap 5.5)
var card_source := "nivel"        # origen de las cartas: "nivel" | "cofre"
var overlay_open := false         # true si HUD tiene la pausa de cartas abierta
var rerolls := 1                  # consumibles por run (roadmap 2.3)
var banishes := 1
var banished: Array[String] = []  # ids desterrados esta run (fuera del pool)
var luck := 0                     # pasiva suerte (roadmap 2.4): pondera rarezas
var character_id := "vagabundo"   # personaje de la run (roadmap 4.2)
var coin_mult := 1.0              # meta "Bolsa de fortuna" (roadmap 4.1)
var auto_start_next := false      # reinicio directo sin pasar por el menú
var curse_id := "ninguna"         # maldición elegida (roadmap 4.3)
var enemy_hp_mult := 1.0
var spawn_mult := 1.0
var bosses_killed := 0            # jefes derrotados en la run (roadmap 4.4)
# --- Supervivencia sin fin (escala por tiempo/ciclos) ---
var endless_loop := 0             # vuelta actual del mapa (0,1,2…)
var run_hp_scale := 1.0           # multiplicador de vida enemiga por minuto
var run_dmg_scale := 1.0          # multiplicador de daño enemigo por minuto
var curse_spawn_mult := 1.0       # base de spawn de la maldición (sin escalado)
# --- Poderes avanzados ---
var crit_chance := 0.0            # probabilidad de golpe crítico (x2)
var lifesteal := 0.0              # HP curada por baja
var crit_dmg := 2.0               # multiplicador de crítico
var execute_bonus := 0.0          # daño extra a enemigos heridos
var chill_chance := 0.0           # probabilidad de ralentizar al golpear
var proj_speed_mult := 1.0        # velocidad de proyectiles
# --- Presupuestos por dispositivo (roadmap 5.1) ---
var device_tier := "medio"
var hardware_tier := "medio"       # tier detectado por RAM/GPU (inmutable)
var quality_mode := "auto"        # override del jugador: auto/bajo/medio/alto
var fps_limit := 60               # 30/60/120/0 (0 = sin límite)
var max_bullets := 900
var enemy_cap := 170
var fx_mult := 0.75
var shadows := false              # sombras direccionales (tier alto)
var render_scale := 1.0           # resolución 3D interna
var prop_mult := 1.0              # densidad de props del bioma
var camera_far := 100.0           # distancia de dibujado
var _last_haptic_ms := 0          # cooldown interno de vibración

func set_camera_mode(m: String) -> void:
	camera_mode = m
	SaveManager.save_settings({"camera_mode": m})
	setting_changed.emit()


func set_haptics(enabled: bool) -> void:
	haptics_enabled = enabled
	SaveManager.save_settings({"haptics": enabled})


## Vibración corta en móvil o en el primer mando conectado.
## El cooldown evita ráfagas cuando varios sistemas reaccionan al mismo golpe.
func haptic(strength := 0.5, duration_ms := 35, force := false) -> void:
	if not haptics_enabled:
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_haptic_ms < 30:
		return
	_last_haptic_ms = now
	var s := clampf(strength, 0.0, 1.0)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(duration_ms, s)
		return
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		Input.start_joy_vibration(int(pads[0]), s * 0.6, s, float(duration_ms) / 1000.0)


# --- Tienda meta y personajes (roadmap 4.1/4.2) ---
func meta_level(id: String) -> int:
	return int(SaveManager.meta.get(id, 0))


func meta_cost(def: Dictionary) -> int:
	return int(def.get("cost", 100)) + int(def.get("step", 0)) * meta_level(String(def.get("id", "")))


func buy_meta(id: String) -> bool:
	var def: Dictionary = {}
	for d in ContentDB.meta_upgrades:
		if String(d.get("id", "")) == id:
			def = d
			break
	if def.is_empty():
		return false
	var lvl := meta_level(id)
	if lvl >= int(def.get("max", 5)):
		return false
	var cost := meta_cost(def)
	if SaveManager.total_coins < cost:
		return false
	SaveManager.total_coins -= cost
	SaveManager.meta[id] = lvl + 1
	SaveManager.save_all()
	return true


func select_character(id: String) -> void:
	if ContentDB.characters.has(id):
		SaveManager.character = id
		SaveManager.save_all()


func select_curse(id: String) -> void:
	for c in ContentDB.curses:
		if String(c.get("id", "")) == id:
			SaveManager.save_settings({"curse": id})
			setting_changed.emit()
			return

# --- Stats de run (afectados por upgrades) ---
var move_speed := 6.0
var max_hp := 100.0
var hp := 100.0
var dmg_mult := 1.0        # multiplicador global de daño
var fire_mult := 1.0       # multiplicador de cadencia
var magnet := 3.0          # radio de recogida de orbes
var extra_proj := 0        # proyectiles extra del arma "wand"
var regen := 0.0           # HP/s (roadmap 2.5)
var area_mult := 1.0       # multiplicador de radios de arma (roadmap 2.5)
var armor := 0.0           # reducción de daño 0..0.6 (roadmap 2.5)
var slow_mult := 1.0       # ralentización por hazard (roadmap 3.3)
var magnet_bonus := 0.0    # imán temporal de pickup (roadmap 2.7)
var magnet_t := 0.0
var _regen_emit_t := 0.0

# --- Estado de run ---
var weapons: Array[String] = []
var weapon_levels := {}    # arma -> nivel I..VIII (roadmap 2.6/2.2)
var upgrade_counts := {}
var level := 1
var xp := 0
var run_time := 0.0
var kills := 0
var coins := 0
var run_active := false
var last_result := {}
var debug_auto_upgrade := false  # smoke headless: aplica mejoras automáticamente
var damage_grace := 0.0          # i-frames de contacto: cap de DPS cuando la horda apila
var _probe_t := 2.0              # diagnóstico temporal (smoke)
var _smoke_evo_done := false     # smoke: prueba única de evolución (2.2)
var _smoke_banish_done := false  # smoke: prueba única de destierro (2.3)
var _smoke_passive_done := false # smoke: prueba única de pasivas nuevas (2.5)
var _smoke_powers_done := false  # smoke: armas spiral/frost + crítico/lifesteal
var _smoke_definitive_done := false # smoke: armas mazo/meteoro/dron/vacío y clima
var _smoke_display_done := false # smoke: opciones FPS/calidad (5.4)

const WEAPON_START := "wand"


func _end_smoke() -> void:
	# Ciclo de vida (5.3): simula perder foco y verifica pausa + menú de pausa.
	if HUD != null and HUD.has_method("_on_app_focus_lost"):
		HUD.call("_on_app_focus_lost")
		print("SMOKE_LIFECYCLE paused=%s menu=%s" % [
			str(get_tree().paused), str(HUD.get("_menu_open")),
		])
	print("SMOKE_RESULT time=%d kills=%d level=%d xp=%d bullets=%d enemies=%d best_time=%d coins=%d" % [
		int(run_time), kills, level, xp, BulletSwarm.active_count(), EnemyManager.active_count(),
		int(SaveManager.best_time), SaveManager.total_coins,
	])
	get_tree().quit()


func _process(delta: float) -> void:
	# Diagnóstico temporal del smoke: pulso cada 2 s de juego con fps y contadores
	if debug_auto_upgrade and run_active and not get_tree().paused:
		_probe_t -= delta
		if _probe_t <= 0.0:
			_probe_t = 2.0
			print("SMOKE_PROBE t=%.1f fps=%d bullets=%d enemies=%d proc=%.1fms phys=%.1fms" % [
				run_time, Engine.get_frames_per_second(),
				BulletSwarm.active_count(), EnemyManager.active_count(),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			])
	damage_grace = maxf(damage_grace - delta, 0.0)
	# Buffs temporales de pickups (roadmap 2.7)
	if magnet_t > 0.0:
		magnet_t = maxf(magnet_t - delta, 0.0)
		if magnet_t <= 0.0:
			magnet_bonus = 0.0
	# Regeneración pasiva (roadmap 2.5): emite como mucho 2 veces/s para no saturar señales.
	if run_active and not get_tree().paused and regen > 0.0 and hp > 0.0 and hp < max_hp:
		hp = minf(hp + regen * delta, max_hp)
		_regen_emit_t += delta
		if _regen_emit_t >= 0.5:
			_regen_emit_t = 0.0
			hp_changed.emit(hp, max_hp)
	# Smoke: a los 10 s aplica las pasivas nuevas y verifica sus stats (2.5).
	if debug_auto_upgrade and run_active and not get_tree().paused and not _smoke_passive_done and run_time > 10.0:
		_smoke_passive_done = true
		for pid in ["regen_1", "area_1", "armor_1"]:
			for u in ContentDB.upgrades:
				if String(u.get("id", "")) == pid:
					apply_upgrade(u)
		print("SMOKE_PASSIVES regen=%.1f area=%.2f armor=%.2f" % [regen, area_mult, armor])
	# Smoke: a los 15 s destierra una carta y comprueba que desaparece del pool (2.3).
	if debug_auto_upgrade and run_active and not get_tree().paused and not _smoke_banish_done and run_time > 15.0:
		_smoke_banish_done = true
		banished.append("rate_1")
		var leaked := false
		for i in 200:
			for c in ContentDB.roll_upgrades(upgrade_counts):
				if String(c.get("id", "")) == "rate_1":
					leaked = true
		print("SMOKE_BANISH ok=%s" % str(not leaked))
	# Smoke: a los 30 s fuerza la receta del Railgun y verifica que la evolución
	# aparece en las cartas y se aplica (roadmap 2.2).
	if debug_auto_upgrade and run_active and not get_tree().paused and not _smoke_evo_done and run_time > 30.0:
		_smoke_evo_done = true
		if weapons.has("wand"):
			weapon_levels["wand"] = ContentDB.MAX_WEAPON_LEVEL
		upgrade_counts["dmg_1"] = maxi(int(upgrade_counts.get("dmg_1", 0)), 3)
		var evo_choices := ContentDB.roll_upgrades(upgrade_counts)
		var applied := ""
		for c in evo_choices:
			if String(c.get("effect", "")) == "evolve":
				apply_upgrade(c)
				applied = String(c.get("result", ""))
				break
		print("SMOKE_EVOLVE result=%s ok=%s" % [applied, str(applied != "")])
	# Smoke: a los 40 s prueba armas nuevas y stats avanzadas + enemigos nuevos.
	if debug_auto_upgrade and run_active and not get_tree().paused and not _smoke_powers_done and run_time > 40.0:
		_smoke_powers_done = true
		for pid in ["weapon_spiral", "weapon_frost", "crit_1", "lifesteal_1"]:
			for u in ContentDB.upgrades:
				if String(u.get("id", "")) == pid:
					apply_upgrade(u)
		if EnemyManager.player != null:
			var pp: Vector3 = EnemyManager.player.position
			EnemyManager.spawn("bomber", pp + Vector3(2.0, 0.0, 0.0), 1.0)
			EnemyManager.spawn("shaman", pp + Vector3(-2.0, 0.0, 0.0), 1.0)
			EnemyManager.spawn("wisp", pp + Vector3(0.0, 0.0, 2.0), 1.0)
		print("SMOKE_POWERS spiral=%s frost=%s crit=%.2f leech=%.2f" % [
			str(weapons.has("spiral")), str(weapons.has("frost")), crit_chance, lifesteal,
		])
	# Smoke: a los 55 s prueba el arsenal definitivo, el clima y el mapa ampliado.
	if debug_auto_upgrade and run_active and not get_tree().paused and not _smoke_definitive_done and run_time > 55.0:
		_smoke_definitive_done = true
		for pid in ["weapon_hammer", "weapon_meteor", "weapon_drone", "weapon_void",
				"projspeed_1", "critdmg_1", "execute_1", "chill_1"]:
			for u in ContentDB.upgrades:
				if String(u.get("id", "")) == pid:
					apply_upgrade(u)
		print("SMOKE_DEFINITIVE weapons=%s arena=%.1f biomes=%d weather=%s proj=%.2f critdmg=%.2f execute=%.2f chill=%.2f" % [
			str(weapons), arena_radius, ContentDB.biomes.size(), weather_name,
			proj_speed_mult, crit_dmg, execute_bonus, chill_chance,
		])
	# Smoke: a los 70 s prueba opciones de rendimiento (5.4) en caliente.
	if debug_auto_upgrade and run_active and not get_tree().paused and not _smoke_display_done and run_time > 70.0:
		_smoke_display_done = true
		set_fps_limit(30)
		set_quality_mode("bajo")
		print("SMOKE_DISPLAY fps=%d quality=%s bullets=%d enemies=%d scale=%.2f" % [
			fps_limit, quality_mode, max_bullets, enemy_cap, render_scale,
		])
	if run_active and not get_tree().paused:
		run_time += delta
		if debug_auto_upgrade and run_time > 75.0:
			_end_smoke()
	elif debug_auto_upgrade and not run_active and last_result.has("time"):
		_end_smoke()


static func xp_to_next(lvl: int) -> int:
	# Curva suave: 5 + 6*lvl^1.6 (ajustable en balance)
	return int(5.0 + 6.0 * pow(float(lvl), 1.6))


func _notification(what: int) -> void:
	## Hardening móvil: si el SO avisa de poca memoria, bajar presupuestos en caliente.
	if what == NOTIFICATION_OS_MEMORY_WARNING:
		max_bullets = mini(max_bullets, 500)
		enemy_cap = mini(enemy_cap, 100)
		fx_mult = minf(fx_mult, 0.5)
		print("LOW_MEMORY bullets=%d enemies=%d fx=%.2f" % [max_bullets, enemy_cap, fx_mult])


func _ready() -> void:
	# El autoload vive con PROCESS_MODE_ALWAYS: su propio reloj y el modo smoke
	# deben avanzar/a salir aunque el árbol esté pausado (p.ej. tras game over).
	process_mode = Node.PROCESS_MODE_ALWAYS
	debug_auto_upgrade = OS.get_environment("HORDAVIA_SMOKE") != ""
	_detect_device()
	# Diferido: SaveManager carga settings después de este _ready.
	call_deferred("apply_saved_display")


## Opciones de rendimiento (roadmap 5.4) guardadas: FPS y calidad Auto/Baja/Media/Alta.
func apply_saved_display() -> void:
	camera_mode = String(SaveManager.settings.get("camera_mode", "fija"))
	if camera_mode != "mouse":
		camera_mode = "fija"
	haptics_enabled = bool(SaveManager.settings.get("haptics", true))
	fps_limit = int(SaveManager.settings.get("fps_limit", 60))
	if not [0, 30, 60, 120].has(fps_limit):
		fps_limit = 60
	Engine.max_fps = fps_limit
	quality_mode = String(SaveManager.settings.get("quality", "auto"))
	if not ["auto", "bajo", "medio", "alto"].has(quality_mode):
		quality_mode = "auto"
	if quality_mode != "auto":
		_apply_tier(quality_mode)
	else:
		_apply_tier(hardware_tier)
	print("DISPLAY fps=%d quality=%s tier=%s" % [fps_limit, quality_mode, device_tier])
	var mn := get_tree().get_first_node_in_group("main")
	if mn != null:
		if mn.has_method("apply_quality_live"):
			mn.call("apply_quality_live")
		if camera_mode == "mouse" and mn.has_method("_apply_camera_mode"):
			mn.call("_apply_camera_mode")


func set_fps_limit(value: int) -> void:
	fps_limit = value
	Engine.max_fps = value


func set_quality_mode(mode: String) -> void:
	quality_mode = mode
	_apply_tier(hardware_tier if mode == "auto" else mode)
	print("QUALITY mode=%s tier=%s bullets=%d enemies=%d fx=%.2f" % [
		quality_mode, device_tier, max_bullets, enemy_cap, fx_mult,
	])
	var mn := get_tree().get_first_node_in_group("main")
	if mn != null and mn.has_method("apply_quality_live"):
		mn.call("apply_quality_live")


## Presupuestos por dispositivo (roadmap 5.1): RAM y GPU deciden límites duros.
func _detect_device() -> void:
	var mem := OS.get_memory_info()
	var phys := float(mem.get("physical", 0)) / 1073741824.0
	var gpu := String(RenderingServer.get_video_adapter_name())
	var g := gpu.to_lower()
	var mobile := g.contains("adreno") or g.contains("mali") or g.contains("powervr") or g.contains("apple")
	var integrated := g.contains("intel") or g.contains("radeon graphics") or g.contains("uhd")
	if mobile or (phys > 0.0 and phys < 3.2):
		hardware_tier = "bajo"
	elif (phys > 0.0 and phys < 6.5) or integrated:
		hardware_tier = "medio"
	else:
		hardware_tier = "alto"
	_apply_tier(hardware_tier)
	print("DEVICE tier=%s mem=%.1fGB gpu=%s bullets=%d enemies=%d fx=%.2f q=(shadows=%s scale=%.2f props=%.2f)" % [
		hardware_tier, phys, gpu, max_bullets, enemy_cap, fx_mult,
		str(shadows), render_scale, prop_mult,
	])


func _apply_tier(tier: String) -> void:
	device_tier = tier
	match tier:
		"bajo":
			max_bullets = 500
			enemy_cap = 110
			fx_mult = 0.5
			shadows = false
			render_scale = 0.72
			prop_mult = 0.45
			camera_far = 105.0
		"medio":
			max_bullets = 900
			enemy_cap = 170
			fx_mult = 0.75
			shadows = false
			render_scale = 0.9
			prop_mult = 0.75
			camera_far = 135.0
		_:
			max_bullets = 1500
			enemy_cap = 230
			fx_mult = 1.0
			shadows = true
			render_scale = 1.0
			prop_mult = 1.0
			camera_far = 170.0


func start_run() -> void:
	character_id = String(SaveManager.character)
	var ch: Dictionary = ContentDB.characters.get(character_id, {})
	move_speed = float(ch.get("speed", 6.0))
	max_hp = float(ch.get("hp", 100.0))
	dmg_mult = float(ch.get("dmg", 1.0))
	fire_mult = float(ch.get("fire", 1.0))
	magnet = float(ch.get("magnet", 3.0))
	var m: Dictionary = SaveManager.meta
	move_speed += 0.15 * float(m.get("meta_speed", 0))
	max_hp += 8.0 * float(m.get("meta_hp", 0))
	dmg_mult *= 1.0 + 0.05 * float(m.get("meta_dmg", 0))
	magnet += 0.6 * float(m.get("meta_magnet", 0))
	coin_mult = 1.0 + 0.10 * float(m.get("meta_coins", 0))
	curse_id = String(SaveManager.settings.get("curse", "ninguna"))
	if debug_auto_upgrade:
		curse_id = "sangre"
	enemy_hp_mult = 1.0
	spawn_mult = 1.0
	for c in ContentDB.curses:
		if String(c.get("id", "")) == curse_id:
			enemy_hp_mult = float(c.get("hp", 1.0))
			spawn_mult = float(c.get("spawn", 1.0))
			coin_mult *= 1.0 + float(c.get("coins", 0.0))
			break
	curse_spawn_mult = spawn_mult
	crit_chance = 0.0
	lifesteal = 0.0
	crit_dmg = 2.0
	execute_bonus = 0.0
	chill_chance = 0.0
	proj_speed_mult = 1.0
	weather_speed_mult = 1.0
	weather_name = "Despejado"
	weather_type = "clear"
	endless_loop = 0
	run_hp_scale = 1.0
	run_dmg_scale = 1.0
	hp = max_hp
	extra_proj = 0
	if debug_auto_upgrade:
		print("SMOKE_META char=%s curse=%s hp=%.0f speed=%.1f dmg=%.2f coin=%.2f ehp=%.2f spawn=%.2f" % [
			character_id, curse_id, max_hp, move_speed, dmg_mult, coin_mult,
			enemy_hp_mult, spawn_mult,
		])
	regen = 0.0
	area_mult = 1.0
	armor = 0.0
	slow_mult = 1.0
	magnet_bonus = 0.0
	magnet_t = 0.0
	_regen_emit_t = 0.0
	weapons = [WEAPON_START]
	weapon_levels = {WEAPON_START: 1}
	upgrade_counts = {}
	_smoke_evo_done = false
	_smoke_banish_done = false
	_smoke_passive_done = false
	_smoke_powers_done = false
	_smoke_definitive_done = false
	_smoke_display_done = false
	rerolls = 1
	banishes = 1
	banished = []
	luck = 0
	# Meta definitiva: la tienda del hub también altera stats de inicio.
	armor = minf(armor + 0.03 * float(m.get("meta_armor", 0)), 0.6)
	regen += 0.15 * float(m.get("meta_regen", 0))
	rerolls += int(m.get("meta_reroll", 0))
	luck += int(m.get("meta_luck", 0))
	bosses_killed = 0
	level = 1
	xp = 0
	run_time = 0.0
	kills = 0
	coins = 0
	# Modo smoke: gear sintético para aguantar las transiciones de bioma comprimidas
	if debug_auto_upgrade:
		dmg_mult = 8.0
		fire_mult = 3.5
		extra_proj = 4
		move_speed = 9.0
		magnet = 14.0
		max_hp = 300.0
		hp = max_hp
	run_active = true
	get_tree().paused = false
	run_reset.emit()
	upgrades_changed.emit()
	run_started.emit()
	xp_changed.emit(xp, xp_to_next(level))
	hp_changed.emit(hp, max_hp)


func add_xp(v: int) -> void:
	if not run_active:
		return
	xp += v
	while xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		haptic(0.55, 40)
		var choices := ContentDB.roll_upgrades(upgrade_counts)
		if choices.is_empty():
			continue
		if debug_auto_upgrade:
			apply_upgrade(choices[0])
			continue
		card_source = "nivel"
		AudioManager.play_sfx("levelup")
		leveled.emit(choices)
		return  # sin downgrade de xp mientras la UI elige
	xp_changed.emit(xp, xp_to_next(level))


func apply_upgrade(u: Dictionary) -> void:
	var id := String(u["id"])
	upgrade_counts[id] = int(upgrade_counts.get(id, 0)) + 1
	match String(u["effect"]):
		"dmg":
			dmg_mult *= 1.25
		"rate":
			fire_mult *= 1.15
		"hp":
			max_hp += 10.0
			hp = minf(hp + 10.0, max_hp)
			hp_changed.emit(hp, max_hp)
		"speed":
			move_speed += 0.8
		"magnet":
			magnet += 1.5
		"proj":
			extra_proj += 1
		"weapon":
			var w := String(u.get("weapon", ""))
			if w != "" and not weapons.has(w):
				weapons.append(w)
				weapon_levels[w] = 1
		"weapon_up":
			var wu := String(u.get("weapon", ""))
			if wu != "":
				weapon_levels[wu] = mini(int(weapon_levels.get(wu, 1)) + 1, ContentDB.MAX_WEAPON_LEVEL)
		"evolve":
			var base := String(u.get("base", ""))
			var result := String(u.get("result", ""))
			if base != "" and result != "" and weapons.has(base):
				weapons.erase(base)
				weapon_levels.erase(base)
				if not weapons.has(result):
					weapons.append(result)
					weapon_levels[result] = 1
		"luck":
			luck += 1
		"regen":
			regen += 0.6
		"area":
			area_mult += 0.12
		"armor":
			armor = minf(armor + 0.08, 0.6)
		"crit":
			crit_chance = minf(crit_chance + 0.08, 0.6)
		"crit_dmg":
			crit_dmg = minf(crit_dmg + 0.25, 4.0)
		"execute":
			execute_bonus += 0.2
		"chill":
			chill_chance = minf(chill_chance + 0.12, 0.6)
		"proj_speed":
			proj_speed_mult *= 1.12
		"lifesteal":
			lifesteal += 0.25
		"greed":
			coin_mult += 0.25
	upgrades_changed.emit()
	xp_changed.emit(xp, xp_to_next(level))


## Consumibles de cartas (roadmap 2.3).
func can_reroll() -> bool:
	return rerolls > 0


func can_banish() -> bool:
	return banishes > 0


func use_reroll() -> bool:
	if rerolls <= 0:
		return false
	rerolls -= 1
	return true


func banish_card(id: String) -> bool:
	if banishes <= 0 or id == "" or banished.has(id):
		return false
	banishes -= 1
	banished.append(id)
	return true


func hp_ratio() -> float:
	return hp / maxf(max_hp, 1.0)


func heal(v: float) -> void:
	if not run_active:
		return
	hp = minf(hp + v, max_hp)
	hp_changed.emit(hp, max_hp)


func magnet_boost(v: float, seconds: float) -> void:
	magnet_bonus = maxf(magnet_bonus, v)
	magnet_t = maxf(magnet_t, seconds)


func take_damage(d: float) -> void:
	if not run_active or d <= 0.0:
		return
	if damage_grace > 0.0:
		return
	damage_grace = 0.5
	hp = maxf(hp - d * (1.0 - armor), 0.0)
	haptic(0.85, 50)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		end_run(false)


## Daño continuo de hazards (roadmap 3.3): ignora el grace de contacto y no
## reinicia screen-shake; aplica armadura y puede matar.
func take_dot(d: float) -> void:
	if not run_active or d <= 0.0:
		return
	hp = maxf(hp - d * (1.0 - armor), 0.0)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		end_run(false)


func add_kill(xp_value: int) -> void:
	if not run_active:
		return
	kills += 1
	coins += maxi(1, int(round(coin_mult)))
	if lifesteal > 0.0 and hp < max_hp:
		hp = minf(hp + lifesteal, max_hp)
		hp_changed.emit(hp, max_hp)
	add_xp(xp_value)


func offer_chest_cards() -> void:
	## Recompensa de cofre procedural (roadmap 1.2): 3 cartas; si la UI de cartas
	## sigue abierta de un nivel, se convierte en monedas para no encadenar overlays.
	if not run_active:
		return
	if overlay_open:
		coins += 20
		return
	card_source = "cofre"
	var choices := ContentDB.roll_upgrades(upgrade_counts)
	if choices.is_empty():
		coins += 20
		return
	if debug_auto_upgrade:
		# Smoke: el cofre se abre solo (una UI de cartas pausaría el árbol headless)
		apply_upgrade(choices[0])
		return
	AudioManager.play_sfx("levelup")
	haptic(0.5, 40)
	leveled.emit(choices)


func end_run(victory: bool) -> void:
	if not run_active:
		return
	run_active = false
	last_result = {
		"victory": victory,
		"time": run_time,
		"level": level,
		"kills": kills,
		"coins": coins,
	}
	if not debug_auto_upgrade:
		SaveManager.register_run(coins, run_time, kills, victory, bosses_killed)
	else:
		# Smoke: valida logros en memoria pero no contamina el save real
		SaveManager.register_run(coins, run_time, kills, victory, bosses_killed, false)
	AudioManager.play_sfx("gameover" if not victory else "levelup")
	haptic(1.0, 140, true)
	get_tree().paused = true
	run_ended.emit(last_result)
