## EnemyManager — pools de enemigos + grilla espacial (guía §3.3).
## Autoload. Crea por tipo según data/enemies.json, evita spawns de nodos nuevos en carrera.
extends Node3D

const CELL := 2.0
const ARENA := 30.0

var player: Node3D = null
var boss_ref = null                # jefe activo actual (roadmap 3.4) o null

var _pools := {}                 # kind -> Array[Enemy]
var _active: Array[Enemy] = []
var _grid := {}                  # cell_key -> Array[Enemy]


class Enemy extends Node3D:
	var kind := ""
	var base_color := Color(0.6, 0.7, 0.4)
	var elite := false
	var boss := false
	var base_hp := 10.0
	var hp := 10.0
	var max_hp := 10.0
	var speed := 3.0
	var dmg := 5.0
	var radius := 0.45
	var xp_value := 1
	var bob_t := 0.0
	var attack_cd := 0.0
	var hit_flash := 0.0
	var visual: Node3D = null
	var base_dmg := 5.0
	var slow_t := 0.0            # ralentización por arma de escarcha
	var slow_mult := 1.0
	var explode_radius := 0.0    # bomber: daño al morir
	var explode_dmg := 0.0
	var summon_interval := 0.0   # shaman: invoca cada X s
	# enemigos a distancia (archers, spitters, sandcasters)
	var ranged := false
	var attack_range := 12.0
	var keep_range := 7.0
	var ranged_interval := 2.0
	var base_projectile_dmg := 5.0
	var projectile_dmg := 5.0
	var projectile_speed := 11.0
	var projectile_color := Color(1.0, 0.55, 0.2)
	var projectile_count := 1
	var projectile_spread := 0.0
	var aim_time := 0.4
	var aim_t := -1.0
	# jefe (roadmap 3.4): telegrafiado + invocación
	var pat_t := 0.0
	var sum_t := 0.0
	var tele_t := -1.0          # -1 = sin telegraph en curso
	var tele_disc: MeshInstance3D = null
	var atk_kind := "slam"      # "slam" | "charge" | "volley"
	var tele_dur := 0.9
	var tele_radius := 5.5
	var slam_interval := 6.0
	var summon_kind := "goblin"
	var summon_count := 8
	var summon_hp := 2.0
	var charge_t := -1.0        # -1 = sin carga en curso
	var charge_v := Vector3.ZERO
	# jefes con ataque a distancia (volley)
	var volley_count := 8
	var volley_speed := 9.0
	var base_volley_dmg := 12.0
	var volley_dmg := 12.0
	var volley_radial := true
	var volley_spread := 55.0
	var volley_color := Color(0.8, 0.45, 1.0)


func _ready() -> void:
	GameState.run_reset.connect(reset)
	GameState.run_started.connect(reset)


func ensure_pool(kind: String, size: int) -> void:
	if _pools.has(kind):
		return
	var def: Dictionary = ContentDB.enemies.get(kind, {})
	if def.is_empty():
		push_error("EnemyManager: tipo desconocido '%s'" % kind)
		return
	var arr: Array = []
	for i in size:
		var e := Enemy.new()
		e.kind = kind
		e.base_hp = float(def.get("hp", 10))
		e.max_hp = e.base_hp
		e.hp = e.max_hp
		e.speed = float(def.get("speed", 3))
		e.base_dmg = float(def.get("dmg", 5))
		e.dmg = e.base_dmg
		e.radius = float(def.get("radius", 0.45))
		e.explode_radius = float(def.get("explode_radius", 0.0))
		e.explode_dmg = float(def.get("explode_dmg", 0.0))
		e.summon_kind = String(def.get("summon", ""))
		e.summon_count = int(def.get("summon_count", 0))
		e.summon_hp = float(def.get("summon_hp", 1.0))
		e.summon_interval = float(def.get("summon_interval", 0.0))
		e.xp_value = int(def.get("xp", 1))
		var col_arr: Array = def.get("color", [0.6, 0.7, 0.4])
		e.base_color = Color(col_arr[0], col_arr[1], col_arr[2])
		# Enemigos a distancia: mantienen distancia y disparan proyectiles.
		e.ranged = bool(def.get("ranged", false))
		e.attack_range = float(def.get("attack_range", 12.0))
		e.keep_range = float(def.get("keep_range", 7.0))
		e.ranged_interval = float(def.get("attack_interval", 2.0))
		e.base_projectile_dmg = float(def.get("projectile_dmg", def.get("dmg", 5)))
		e.projectile_dmg = e.base_projectile_dmg
		e.projectile_speed = float(def.get("projectile_speed", 11.0))
		e.projectile_count = maxi(int(def.get("projectile_count", 1)), 1)
		e.projectile_spread = float(def.get("projectile_spread", 0.0))
		e.aim_time = float(def.get("aim_time", 0.4))
		var pc_arr: Array = def.get("projectile_color", [1.0, 0.55, 0.2])
		e.projectile_color = Color(pc_arr[0], pc_arr[1], pc_arr[2])
		e.visual = _make_visual(e.base_color, e.radius, kind, bool(def.get("boss", false)), e.ranged)
		e.add_child(e.visual)
		if bool(def.get("boss", false)):
			e.boss = true
			e.atk_kind = String(def.get("boss_attack", "slam"))
			e.tele_dur = float(def.get("tele_dur", 0.9))
			e.tele_radius = float(def.get("tele_radius", 5.5))
			e.slam_interval = float(def.get("slam_interval", 6.0))
			e.summon_kind = String(def.get("summon", "goblin"))
			e.summon_count = int(def.get("summon_count", 8))
			e.summon_hp = float(def.get("summon_hp", 2.0))
			e.volley_count = maxi(int(def.get("volley_count", 8)), 3)
			e.volley_speed = float(def.get("volley_speed", 9.0))
			e.base_volley_dmg = float(def.get("volley_dmg", e.base_dmg))
			e.volley_dmg = e.base_volley_dmg
			e.volley_radial = bool(def.get("volley_radial", true))
			e.volley_spread = float(def.get("volley_spread", 55.0))
			var vc_arr: Array = def.get("volley_color", [0.8, 0.45, 1.0])
			e.volley_color = Color(vc_arr[0], vc_arr[1], vc_arr[2])
			# disco de telegrafiado del slam (radio visible durante el aviso)
			var disc := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = e.tele_radius
			cyl.bottom_radius = e.tele_radius
			cyl.height = 0.06
			var dmat := StandardMaterial3D.new()
			dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var disc_col := e.volley_color if e.atk_kind == "volley" else Color(1.0, 0.15, 0.1)
			dmat.albedo_color = Color(disc_col.r, disc_col.g, disc_col.b, 0.0)
			cyl.material = dmat
			disc.mesh = cyl
			disc.position.y = 0.08
			disc.visible = false
			e.visual.add_child(disc)
			e.tele_disc = disc
		e.visible = false
		e.set_meta("hit_cd", {})
		add_child(e)
		arr.append(e)
	_pools[kind] = arr


func _make_visual(c: Color, radius: float, kind: String, boss: bool, ranged: bool) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = radius * 4.0 + 0.4
	var mat := ShaderMaterial.new()
	mat.shader = load("res://fx/toon.gdshader")
	mat.set_shader_parameter("base_color", c)
	mesh.material = mat
	mi.mesh = mesh
	mi.position.y = mesh.height * 0.5 - mesh.radius * 0.5
	root.add_child(mi)
	if ranged and not boss:
		# Orbe flotante: lectura rápida de "este enemigo dispara".
		var orb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius * 0.32
		sphere.height = radius * 0.64
		sphere.radial_segments = 8
		sphere.rings = 4
		sphere.material = _flat_mat(c.lightened(0.38))
		orb.mesh = sphere
		orb.position = Vector3(0.0, mesh.height + radius * 0.35, 0.0)
		root.add_child(orb)
	if boss:
		_add_boss_decor(root, kind, c, radius, mesh.height)
	return root


func _flat_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _toon_mat(c: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://fx/toon.gdshader")
	m.set_shader_parameter("base_color", c)
	return m


func _add_spike(root: Node3D, pos: Vector3, rot_deg: Vector3, height: float, width: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.015
	cone.bottom_radius = width
	cone.height = height
	cone.radial_segments = 5
	cone.rings = 2
	cone.material = mat
	mi.mesh = cone
	mi.position = pos
	mi.rotation_degrees = rot_deg
	root.add_child(mi)


## Decoración única por jefe para que cada bioma se lea de un vistazo.
func _add_boss_decor(root: Node3D, kind: String, c: Color, radius: float, body_h: float) -> void:
	var accent := c.lightened(0.34)
	var accent_mat := _toon_mat(accent)
	var dark_mat := _toon_mat(c.darkened(0.22))
	match kind:
		"boss_forest":
			# Astas de niebla.
			_add_spike(root, Vector3(-radius * 0.65, body_h * 0.92, 0.0), Vector3(0, 0, -28), radius * 2.2, radius * 0.16, accent_mat)
			_add_spike(root, Vector3(radius * 0.65, body_h * 0.92, 0.0), Vector3(0, 0, 28), radius * 2.2, radius * 0.16, accent_mat)
			_add_spike(root, Vector3(0.0, body_h * 0.98, -radius * 0.5), Vector3(-20, 0, 0), radius * 1.6, radius * 0.13, dark_mat)
		"boss_caves":
			# Corona de cristales de las profundidades.
			for i in 7:
				var a := TAU * float(i) / 7.0
				_add_spike(root, Vector3(cos(a) * radius * 0.82, body_h * 0.78, sin(a) * radius * 0.82), Vector3(0, rad_to_deg(a), 0), radius * (1.3 + 0.25 * float(i % 3)), radius * 0.12, accent_mat)
		"boss_final":
			# Obeliscos del coloso de dunas.
			for i in 4:
				var a := TAU * float(i) / 4.0 + 0.4
				_add_spike(root, Vector3(cos(a) * radius * 0.72, body_h * 0.86, sin(a) * radius * 0.72), Vector3(0, rad_to_deg(a), 0), radius * 1.9, radius * 0.20, _toon_mat(Color(0.95, 0.72, 0.20)))
			var core := MeshInstance3D.new()
			var orb := SphereMesh.new()
			orb.radius = radius * 0.34
			orb.height = radius * 0.68
			orb.material = _flat_mat(Color(1.0, 0.55, 0.16))
			core.mesh = orb
			core.position = Vector3(0.0, body_h * 0.55, -radius * 0.75)
			root.add_child(core)
		"boss_swamp":
			# Sombrero de esporas.
			var cap := MeshInstance3D.new()
			var cap_mesh := SphereMesh.new()
			cap_mesh.radius = radius * 1.75
			cap_mesh.height = radius * 0.95
			cap_mesh.radial_segments = 12
			cap_mesh.rings = 5
			cap_mesh.material = _toon_mat(c.lightened(0.18))
			cap.mesh = cap_mesh
			cap.position = Vector3(0.0, body_h * 0.88, 0.0)
			root.add_child(cap)
			for i in 4:
				var a := TAU * float(i) / 4.0
				var spot := MeshInstance3D.new()
				var s := SphereMesh.new()
				s.radius = radius * 0.20
				s.height = radius * 0.18
				s.material = _flat_mat(Color(0.78, 1.0, 0.55))
				spot.mesh = s
				spot.position = Vector3(cos(a) * radius * 0.95, body_h * 0.98, sin(a) * radius * 0.95)
				root.add_child(spot)
		"boss_tundra":
			# Corona de escarcha.
			for i in 6:
				var a := TAU * float(i) / 6.0
				_add_spike(root, Vector3(cos(a) * radius * 0.80, body_h * 0.80, sin(a) * radius * 0.80), Vector3(0, rad_to_deg(a), 0), radius * (1.6 + 0.2 * float(i % 2)), radius * 0.11, _toon_mat(Color(0.72, 0.94, 1.0)))
		"boss_volcano":
			# Cuernos y núcleo de magma.
			_add_spike(root, Vector3(-radius * 0.62, body_h * 0.90, 0.0), Vector3(0, 0, -42), radius * 1.8, radius * 0.22, dark_mat)
			_add_spike(root, Vector3(radius * 0.62, body_h * 0.90, 0.0), Vector3(0, 0, 42), radius * 1.8, radius * 0.22, dark_mat)
			var core := MeshInstance3D.new()
			var orb := SphereMesh.new()
			orb.radius = radius * 0.40
			orb.height = radius * 0.80
			orb.material = _flat_mat(Color(1.0, 0.34, 0.08))
			core.mesh = orb
			core.position = Vector3(0.0, body_h * 0.52, -radius * 0.72)
			root.add_child(core)
		"boss_ruins":
			# Anillos y esquirlas del eclipse.
			for i in 3:
				var ring := MeshInstance3D.new()
				var torus := TorusMesh.new()
				torus.inner_radius = radius * (1.1 + 0.22 * float(i))
				torus.outer_radius = radius * (1.22 + 0.22 * float(i))
				torus.material = _flat_mat(Color(0.72, 0.58, 1.0, 0.75))
				ring.mesh = torus
				ring.position = Vector3(0.0, body_h * (0.40 + 0.18 * float(i)), 0.0)
				ring.rotation_degrees = Vector3(72.0 + 12.0 * float(i), 18.0 * float(i), 0.0)
				root.add_child(ring)
		_:
			for i in 5:
				var a := TAU * float(i) / 5.0
				_add_spike(root, Vector3(cos(a) * radius * 0.70, body_h * 0.92, sin(a) * radius * 0.70), Vector3(0, rad_to_deg(a), 0), radius * 1.4, radius * 0.14, accent_mat)


func spawn(kind: String, pos: Vector3, hp_mult: float = 1.0, elite: bool = false) -> void:
	ensure_pool(kind, 60)
	var arr: Array = _pools.get(kind, [])
	var e = null
	for cand in arr:
		if not cand.visible:
			e = cand
			break
	if e == null:
		return  # presupuesto alcanzado: se ignora el spawn
	e.visible = true
	e.elite = elite
	e.dmg = e.base_dmg * GameState.run_dmg_scale
	e.projectile_dmg = e.base_projectile_dmg * GameState.run_dmg_scale
	e.volley_dmg = e.base_volley_dmg * GameState.run_dmg_scale
	e.slow_t = 0.0
	e.slow_mult = 1.0
	if elite:
		e.max_hp = e.base_hp * hp_mult * 8.0 * GameState.enemy_hp_mult * GameState.run_hp_scale
		e.scale = Vector3.ONE * 1.5
	else:
		e.max_hp = e.base_hp * hp_mult * GameState.enemy_hp_mult * GameState.run_hp_scale
		e.scale = Vector3.ONE
	e.hp = e.max_hp
	var gy := 0.0
	if GameState.terrain != null:
		gy = float(GameState.terrain.call("height_at", pos.x, pos.z))
	e.position = Vector3(pos.x, gy, pos.z)
	e.attack_cd = 0.0
	e.bob_t = randf() * TAU
	e.pat_t = 0.0
	e.sum_t = 0.0
	e.tele_t = -1.0
	e.charge_t = -1.0
	e.aim_t = -1.0
	e.hit_flash = 0.0
	if e.visual != null:
		e.visual.scale = Vector3.ONE
	if e.tele_disc != null:
		((e.tele_disc.mesh as CylinderMesh).material as StandardMaterial3D).albedo_color.a = 0.0
		e.tele_disc.visible = false
	(e.get_meta("hit_cd") as Dictionary).clear()
	_active.append(e)
	if e.boss:
		boss_ref = e
		GameState.haptic(0.8, 90)
		DeathFx.spawn(e.position, e.base_color, true)
		AudioManager.play_sfx("boom", 0.72)


func spawn_ring(kind: String, center: Vector3, count: int, radius: float, hp_mult: float, elite: bool = false) -> void:
	for i in count:
		var a := TAU * float(i) / float(count)
		var pos := center + Vector3(cos(a), 0.0, sin(a)) * radius
		spawn(kind, pos, hp_mult, elite)


func _physics_process(dt: float) -> void:
	if not GameState.run_active or player == null:
		return
	_build_grid()
	var ppos := player.position
	var doomed: Array[Enemy] = []
	var summons: Array = []
	for e in _active:
		if not e.visible:
			continue
		var to_p := ppos - e.position
		to_p.y = 0.0
		var dist := to_p.length()
		if dist > 60.0:
			e.position = _respawn_edge(ppos)
			continue
		if e.slow_t > 0.0:
			e.slow_t = maxf(e.slow_t - dt, 0.0)
		else:
			e.slow_mult = 1.0
		if e.boss:
			_boss_think(e, dt, ppos)
		elif e.ranged:
			_ranged_think(e, dt, to_p, dist)
		else:
			var seek := Vector3.ZERO
			if dist > 0.001:
				seek = (to_p / dist) * e.speed
			var sep := _separation(e)
			var vel := (seek * 0.9 + sep) * dt * e.slow_mult
			e.position += vel
		# Invocadores (chamán y jefes de área) comparten el mismo reloj.
		if not e.boss and e.summon_kind != "" and e.summon_count > 0 and e.summon_interval > 0.0:
			e.sum_t += dt
			if e.sum_t >= e.summon_interval:
				e.sum_t = 0.0
				summons.append({
					"kind": e.summon_kind, "pos": e.position,
					"count": e.summon_count, "hp": e.summon_hp,
				})
		e.position.x = clampf(e.position.x, -ARENA, ARENA)
		e.position.z = clampf(e.position.z, -ARENA, ARENA)
		# seguir el relieve procedural
		if GameState.terrain != null:
			e.position.y = float(GameState.terrain.call("height_at", e.position.x, e.position.z))
		e.bob_t += dt * e.speed * 1.5
		e.visual.position.y = absf(sin(e.bob_t)) * 0.15
		if e.hit_flash > 0.0:
			e.hit_flash -= dt
			e.visual.scale = Vector3.ONE * (1.25 if e.hit_flash > 0.0 else 1.0)
		e.attack_cd = maxf(e.attack_cd - dt, 0.0)
		if dist < e.radius + 0.5 and e.attack_cd <= 0.0:
			e.attack_cd = 1.0
			GameState.take_damage(e.dmg)
		if e.hp <= 0.0:
			doomed.append(e)
	for s in summons:
		spawn_ring(String(s["kind"]), s["pos"], int(s["count"]), 3.0, float(s["hp"]))
	for e in doomed:
		_kill(e)


## Enemigos a distancia: se acercan si están lejos, retroceden si están encima,
## hacen strafe en su rango cómodo y disparan tras un breve aviso.
func _ranged_think(e: Enemy, dt: float, to_p: Vector3, dist: float) -> void:
	var move := Vector3.ZERO
	if dist > e.attack_range * 0.92:
		if dist > 0.001:
			move = to_p / dist
	elif dist < e.keep_range * 0.72:
		if dist > 0.001:
			move = -to_p / dist
	else:
		var strafe := Vector3(-to_p.z, 0.0, to_p.x)
		if strafe.length() > 0.001:
			strafe = strafe.normalized() * (1.0 if sin(e.bob_t * 0.8) >= 0.0 else -1.0)
		move = strafe * 0.55
	var sep := _separation(e)
	e.position += (move * e.speed * 0.78 + sep) * dt * e.slow_mult

	if e.aim_t >= 0.0:
		e.aim_t -= dt
		# Pequeño pulso visual durante el aviso (sin tapar el hit flash).
		if e.hit_flash <= 0.0:
			var pulse := 1.0 + 0.10 * sin(e.aim_t * 40.0)
			e.visual.scale = Vector3.ONE * pulse
		if e.aim_t <= 0.0:
			_fire_ranged(e, to_p, dist)
			e.aim_t = -1.0
			e.attack_cd = e.ranged_interval
			if e.hit_flash <= 0.0:
				e.visual.scale = Vector3.ONE
	elif e.attack_cd <= 0.0 and dist <= e.attack_range:
		e.aim_t = e.aim_time
		AudioManager.play_sfx("hit", 1.25)


func _fire_ranged(e: Enemy, to_p: Vector3, _dist: float) -> void:
	var dir := Vector3(to_p.x, 0.0, to_p.z)
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var base_angle := atan2(dir.x, dir.z)
	var count := maxi(e.projectile_count, 1)
	var spread := deg_to_rad(e.projectile_spread)
	var start := e.position + dir * (e.radius + 0.45)
	for i in count:
		var offset := 0.0
		if count > 1:
			offset = spread * (float(i) / float(count - 1) - 0.5)
		var a := base_angle + offset
		var shot_dir := Vector3(sin(a), 0.0, cos(a))
		HostileProjectiles.fire(start, shot_dir, e.projectile_speed, e.projectile_dmg, 4.5, e.projectile_color)
	AudioManager.play_sfx("zap", 0.92)
	DeathFx.spawn(start, e.projectile_color, false)


## IA del jefe (roadmap 3.4): arquetipos data-driven.
## - "slam": telegrafía un disco y golpea AoE (Coloso, Reina).
## - "charge": aviso corto y embestida a 16 m/s (Guardián del bosque).
## - "volley": abanico/anillo de proyectiles (Madre de Esporas, Heraldo).
func _boss_think(e: Enemy, dt: float, ppos: Vector3) -> void:
	e.sum_t += dt
	if e.atk_kind == "charge":
		_boss_charge(e, dt, ppos)
		return
	if e.atk_kind == "volley":
		_boss_volley(e, dt, ppos)
		return
	if e.tele_t >= 0.0:
		# telegrafiado: quieto, disco rojo crece
		e.tele_t += dt
		var k: float = clampf(e.tele_t / maxf(e.tele_dur, 0.05), 0.0, 1.0)
		if e.tele_disc != null:
			e.tele_disc.visible = true
			((e.tele_disc.mesh as CylinderMesh).material as StandardMaterial3D).albedo_color.a = 0.15 + 0.45 * k
			e.tele_disc.scale = Vector3.ONE * (0.6 + 0.4 * k)
		if e.tele_t >= e.tele_dur:
			# SLAM
			if e.tele_disc != null:
				e.tele_disc.visible = false
			if dist_to_player_e(e, ppos) < e.tele_radius + 0.5:
				GameState.damage_grace = 0.0   # el slam ignora i-frames de contacto
				GameState.take_damage(e.dmg * 1.5)
			DeathFx.spawn(e.position, Color(0.9, 0.35, 0.15), true)
			AudioManager.play_sfx("boom", 0.55)
			e.tele_t = -1.0
			e.pat_t = 0.0
		return
	e.pat_t += dt
	if e.pat_t >= e.slam_interval:
		e.tele_t = 0.0
		AudioManager.play_sfx("hit", 0.6)
		return
	_chase_boss(e, dt, ppos)
	if e.sum_t >= 12.0:
		e.sum_t = 0.0
		spawn_ring(e.summon_kind, e.position, e.summon_count, 4.5, e.summon_hp)


## Jefes de proyectiles: telegrafían y luego lanzan un anillo o un abanico.
func _boss_volley(e: Enemy, dt: float, ppos: Vector3) -> void:
	if e.tele_t >= 0.0:
		e.tele_t += dt
		var k: float = clampf(e.tele_t / maxf(e.tele_dur, 0.05), 0.0, 1.0)
		if e.tele_disc != null:
			e.tele_disc.visible = true
			((e.tele_disc.mesh as CylinderMesh).material as StandardMaterial3D).albedo_color.a = 0.12 + 0.40 * k
			e.tele_disc.scale = Vector3.ONE * (0.7 + 0.3 * k)
		if e.tele_t >= e.tele_dur:
			if e.tele_disc != null:
				e.tele_disc.visible = false
			_fire_boss_volley(e, ppos)
			e.tele_t = -1.0
			e.pat_t = 0.0
		return
	e.pat_t += dt
	if e.pat_t >= e.slam_interval:
		e.tele_t = 0.0
		AudioManager.play_sfx("hit", 0.58)
		return
	_chase_boss(e, dt, ppos)
	if e.sum_t >= 12.0:
		e.sum_t = 0.0
		spawn_ring(e.summon_kind, e.position, e.summon_count, 4.5, e.summon_hp)


func _fire_boss_volley(e: Enemy, ppos: Vector3) -> void:
	var dir := Vector3(ppos.x - e.position.x, 0.0, ppos.z - e.position.z)
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var base_angle := atan2(dir.x, dir.z)
	var count := maxi(e.volley_count, 3)
	var spread := deg_to_rad(e.volley_spread)
	var origin := e.position + Vector3(0.0, 0.9, 0.0)
	for i in count:
		var a := base_angle
		if e.volley_radial:
			a = TAU * float(i) / float(count)
		elif count > 1:
			a += spread * (float(i) / float(count - 1) - 0.5)
		var shot_dir := Vector3(sin(a), 0.0, cos(a))
		HostileProjectiles.fire(
			origin + shot_dir * 1.15, shot_dir, e.volley_speed,
			e.volley_dmg, 6.0, e.volley_color, 0.24
		)
	DeathFx.spawn(origin, e.volley_color, true)
	AudioManager.play_sfx("boom", 0.62)


## Embestida del Guardián: aviso 0.55 s, luego lunge recto con daño de contacto.
func _boss_charge(e: Enemy, dt: float, ppos: Vector3) -> void:
	if e.charge_t >= 0.0:
		e.charge_t += dt
		var k: float = clampf(e.charge_t / 0.55, 0.0, 1.0)
		if e.tele_disc != null:
			e.tele_disc.visible = true
			((e.tele_disc.mesh as CylinderMesh).material as StandardMaterial3D).albedo_color.a = 0.20 + 0.5 * k
			e.tele_disc.scale = Vector3.ONE * (0.5 + 0.5 * k)
		if e.charge_t < 0.55:
			var seek := ppos - e.position
			seek.y = 0.0
			if seek.length() > 0.01:
				e.charge_v = seek.normalized()
			return
		e.position += e.charge_v * 16.0 * dt
		if dist_to_player_e(e, ppos) < e.radius + 1.1:
			GameState.damage_grace = 0.0
			GameState.take_damage(e.dmg * 1.2)
		if e.charge_t >= 1.05:
			if e.tele_disc != null:
				e.tele_disc.visible = false
			e.charge_t = -1.0
			e.pat_t = 0.0
		return
	e.pat_t += dt
	if e.pat_t >= 4.5:
		e.charge_t = 0.0
		AudioManager.play_sfx("dash", 0.6)
		return
	_chase_boss(e, dt, ppos)
	if e.sum_t >= 13.0:
		e.sum_t = 0.0
		spawn_ring(e.summon_kind, e.position, e.summon_count, 4.5, e.summon_hp)


func _chase_boss(e: Enemy, dt: float, ppos: Vector3) -> void:
	if dist_to_player_e(e, ppos) <= 0.001:
		return
	var seek := ppos - e.position
	seek.y = 0.0
	e.position += seek.normalized() * e.speed * 0.85 * dt


func dist_to_player_e(e: Enemy, ppos: Vector3) -> float:
	var d := ppos - e.position
	d.y = 0.0
	return d.length()


func _kill(e: Enemy) -> void:
	if e == null or not e.visible:
		return  # guardia: evitar doble conteo por entradas duplicadas en _active
	var pos := e.position
	e.visible = false
	e.position = Vector3(0, -50, 0)
	_active.erase(e)
	DeathFx.spawn(pos, e.base_color, e.elite or e.boss)
	if e.explode_radius > 0.0:
		# Bomber: estalla al morir (telegrafiado por su color naranja)
		DeathFx.spawn(pos, Color(1.0, 0.55, 0.15), true)
		AudioManager.play_sfx("boom", 0.8)
		var pl = player
		if pl != null and Vector3(pl.position.x - pos.x, 0.0, pl.position.z - pos.z).length() <= e.explode_radius:
			GameState.take_damage(e.explode_dmg)
	if e.boss:
		boss_ref = null
		GameState.bosses_killed += 1
		var is_final := e.kind == "boss_final"
		if GameState.debug_auto_upgrade:
			print("SMOKE_BOSS killed kind=%s final=%s" % [e.kind, str(is_final)])
		# Todos los jefes dan recompensa y la run continúa (sin fin).
		GameState.coins += 150 if is_final else 60
		GameState.hp = minf(GameState.hp + GameState.max_hp * 0.3, GameState.max_hp)
		GameState.hp_changed.emit(GameState.hp, GameState.max_hp)
		AudioManager.play_sfx("levelup", 0.8)
		GameState.offer_chest_cards()
		return
	var xp_val := e.xp_value * (4 if e.elite else 1)
	GameState.add_kill(xp_val)
	XPManager.spawn_orb(pos, xp_val)
	GameState.kill_event.emit(pos, e.elite)


func boss_active() -> bool:
	return boss_ref != null and is_instance_valid(boss_ref) and boss_ref.visible


func damage(e: Enemy, dmg: float) -> void:
	var final_dmg := dmg
	# Siega: remate contra enemigos por debajo del 35% de vida
	if GameState.execute_bonus > 0.0 and e.hp <= e.max_hp * 0.35:
		final_dmg *= 1.0 + GameState.execute_bonus
	var crit := GameState.crit_chance > 0.0 and randf() < GameState.crit_chance
	if crit:
		final_dmg *= GameState.crit_dmg
	# Aliento gélido: probabilidad de ralentizar con cualquier golpe
	if GameState.chill_chance > 0.0 and randf() < GameState.chill_chance:
		e.slow_t = maxf(e.slow_t, 1.4)
		e.slow_mult = minf(e.slow_mult, 0.65)
	e.hp -= final_dmg
	e.hit_flash = 0.06
	FloatingNumbers.spawn(e.position + Vector3(0.0, e.radius * 2.0 + 0.6, 0.0), final_dmg, e.elite or crit)
	AudioManager.play_sfx("hit", randf_range(0.9, 1.15))


## Daño en área total (bomba de pickup, roadmap 2.7).
func damage_all(dmg: float) -> void:
	for e in _active:
		if e.visible:
			damage(e, dmg)


# ---------- Grilla espacial ----------

func _cell_key(x: float, z: float) -> int:
	return int(floor(x / CELL)) * 4093 + int(floor(z / CELL))


func _build_grid() -> void:
	_grid.clear()
	for e in _active:
		if not is_instance_valid(e) or not e.visible:
			continue
		var key := _cell_key(e.position.x, e.position.z)
		if not _grid.has(key):
			_grid[key] = []
		(_grid[key] as Array).append(e)


func _separation(e: Enemy) -> Vector3:
	var push := Vector3.ZERO
	var cx := int(floor(e.position.x / CELL))
	var cz := int(floor(e.position.z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr: Array = _grid.get((cx + dx) * 4093 + (cz + dz), [])
			for o in arr:
				if o == e:
					continue
				var d3: Vector3 = e.position - o.position
				d3.y = 0.0
				var d: float = d3.length()
				var min_d: float = e.radius + o.radius + 0.05
				if d < min_d and d > 0.0001:
					push += (d3 / d) * (min_d - d) * 3.0
	return push


## Consulta radial de bala (da compa: pto más cercano); devuelve si hubo impacto.
func hit_query(pos: Vector3, radius: float, dmg: float) -> bool:
	var best: Enemy = null
	var best_d := radius
	var cx := int(floor(pos.x / CELL))
	var cz := int(floor(pos.z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr: Array = _grid.get((cx + dx) * 4093 + (cz + dz), [])
			for o in arr:
				if not o.visible:
					continue
				var d3 := Vector3(o.position.x - pos.x, 0.0, o.position.z - pos.z)
				var d := d3.length()
				if d < best_d:
					best_d = d
					best = o
	if best != null:
		damage(best, dmg)
		return true
	return false


## Barrido por segmento: distancia mínima del centro (en plano XZ) del enemigo
## al segmento [prev, cur] recorrido por la bala en este tick de física.
## Evita el "tunneling" cuando la bala avanza más que el radio entre frames.
func hit_sweep(prev: Vector3, cur: Vector3, radius: float, dmg: float) -> bool:
	var seg := cur - prev
	seg.y = 0.0
	var seg_len := seg.length()
	var best: Enemy = null
	var best_d := radius
	if seg_len < 0.0001:
		return hit_query(cur, radius, dmg)
	var min_x := minf(prev.x, cur.x) - radius
	var max_x := maxf(prev.x, cur.x) + radius
	var min_z := minf(prev.z, cur.z) - radius
	var max_z := maxf(prev.z, cur.z) + radius
	var cx0 := int(floor(min_x / CELL)) - 1
	var cx1 := int(floor(max_x / CELL)) + 1
	var cz0 := int(floor(min_z / CELL)) - 1
	var cz1 := int(floor(max_z / CELL)) + 1
	var seg2 := seg.dot(seg)
	for gx in range(cx0, cx1 + 1):
		for gz in range(cz0, cz1 + 1):
			var arr: Array = _grid.get(gx * 4093 + gz, [])
			for o in arr:
				if not o.visible:
					continue
				var ex: float = o.position.x
				var ez: float = o.position.z
				if ex < min_x or ex > max_x or ez < min_z or ez > max_z:
					continue
				var t: float = ((ex - prev.x) * seg.x + (ez - prev.z) * seg.z) / seg2
				t = clampf(t, 0.0, 1.0)
				var px := prev.x + seg.x * t - ex
				var pz := prev.z + seg.z * t - ez
				var d := sqrt(px * px + pz * pz)
				# radio combinado: bala + enemigo
				var reach: float = radius + float(o.radius)
				if d < reach and d < best_d + float(o.radius):
					best_d = d
					best = o
	if best != null:
		damage(best, dmg)
		return true
	return false


## Igual que hit_sweep pero ignorando enemigos ya golpeados por esta bala
## (armas perforantes, roadmap 2.2). Devuelve {"id": instance_id} o {}.
func hit_sweep_ex(prev: Vector3, cur: Vector3, radius: float, dmg: float, ignore: Dictionary) -> Dictionary:
	var seg := cur - prev
	seg.y = 0.0
	var seg_len := seg.length()
	if seg_len < 0.0001:
		var candidate = nearest(cur, radius, ignore)
		if candidate != null:
			damage(candidate, dmg)
			return {"id": candidate.get_instance_id()}
		return {}
	var best: Enemy = null
	var best_d := radius
	var min_x := minf(prev.x, cur.x) - radius
	var max_x := maxf(prev.x, cur.x) + radius
	var min_z := minf(prev.z, cur.z) - radius
	var max_z := maxf(prev.z, cur.z) + radius
	var cx0 := int(floor(min_x / CELL)) - 1
	var cx1 := int(floor(max_x / CELL)) + 1
	var cz0 := int(floor(min_z / CELL)) - 1
	var cz1 := int(floor(max_z / CELL)) + 1
	var seg2 := seg.dot(seg)
	for gx in range(cx0, cx1 + 1):
		for gz in range(cz0, cz1 + 1):
			var arr: Array = _grid.get(gx * 4093 + gz, [])
			for o in arr:
				if not o.visible or ignore.has(o.get_instance_id()):
					continue
				var ex: float = o.position.x
				var ez: float = o.position.z
				if ex < min_x or ex > max_x or ez < min_z or ez > max_z:
					continue
				var t: float = ((ex - prev.x) * seg.x + (ez - prev.z) * seg.z) / seg2
				t = clampf(t, 0.0, 1.0)
				var px := prev.x + seg.x * t - ex
				var pz := prev.z + seg.z * t - ez
				var d := sqrt(px * px + pz * pz)
				if d < radius + float(o.radius) and d < best_d + float(o.radius):
					best_d = d
					best = o
	if best != null:
		damage(best, dmg)
		return {"id": best.get_instance_id()}
	return {}


## Enemigos activos dentro del radio (plano XZ). Dedup: cada enemigo vive en una celda.
func enemies_in_radius(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var r2 := radius * radius
	var cx0 := int(floor((pos.x - radius) / CELL))
	var cx1 := int(floor((pos.x + radius) / CELL))
	var cz0 := int(floor((pos.z - radius) / CELL))
	var cz1 := int(floor((pos.z + radius) / CELL))
	for gx in range(cx0, cx1 + 1):
		for gz in range(cz0, cz1 + 1):
			var arr: Array = _grid.get(gx * 4093 + gz, [])
			for o in arr:
				if not o.visible:
					continue
				var dx: float = o.position.x - pos.x
				var dz: float = o.position.z - pos.z
				if dx * dx + dz * dz <= r2:
					out.append(o)
	return out


## Enemigo más cercano a pos dentro del radio (para auto-aim), sin dañar.
## `excluded` = diccionario de instancia_id -> true, para cadenas que no repiten blanco.
func nearest(pos: Vector3, radius: float, excluded: Dictionary = {}):
	var best = null
	var best_d := radius
	for e in _active:
		if not e.visible:
			continue
		if excluded.has(e.get_instance_id()):
			continue
		var d3 := Vector3(e.position.x - pos.x, 0.0, e.position.z - pos.z)
		var d := d3.length()
		if d < best_d:
			best_d = d
			best = e
	return best


func active_count() -> int:
	var n := 0
	for e in _active:
		if e.visible:
			n += 1
	return n


func _respawn_edge(ppos: Vector3) -> Vector3:
	var a := randf() * TAU
	return ppos + Vector3(cos(a), 0.0, sin(a)) * 28.0


func reset() -> void:
	_active.clear()
	_grid.clear()
	boss_ref = null
	for kind in _pools:
		for e in ( _pools[kind] as Array):
			e.visible = false
			e.position = Vector3(0, -50, 0)
