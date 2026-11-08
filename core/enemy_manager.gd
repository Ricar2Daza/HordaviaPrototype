## EnemyManager — pools de enemigos + grilla espacial (guía §3.3).
## Autoload. Crea por tipo según data/enemies.json, evita spawns de nodos nuevos en carrera.
extends Node3D

const CELL := 2.0
const ARENA := 35.5

var player: Node3D = null
var boss_ref = null                # jefe activo actual (roadmap 3.4) o null

var _pools := {}                 # kind -> Array[Enemy]
var _free_pool := {}             # kind -> Array[Enemy] libres (spawn O(1))
var _active: Array[Enemy] = []
var _active_pos := {}            # instance_id -> índice en _active (baja O(1))
var _grid := {}                  # cell_key -> Array[Enemy]
var _grid_keys: Array = []       # celdas usadas en el último build (se reutilizan)


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
	# jefe (roadmap 3.4): telegrafiado + invocación
	var pat_t := 0.0
	var sum_t := 0.0
	var tele_t := -1.0          # -1 = sin telegraph en curso
	var tele_disc: MeshInstance3D = null
	var atk_kind := "slam"      # "slam" | "charge"
	var tele_dur := 0.9
	var tele_radius := 5.5
	var slam_interval := 6.0
	var summon_kind := "goblin"
	var summon_count := 8
	var summon_hp := 2.0
	var charge_t := -1.0        # -1 = sin carga en curso
	var charge_v := Vector3.ZERO


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
	if bool(def.get("boss", false)):
		size = mini(size, 2)   # solo hay un jefe activo por bioma
	var radius := float(def.get("radius", 0.45))
	var col_arr: Array = def.get("color", [0.6, 0.7, 0.4])
	var base_color := Color(float(col_arr[0]), float(col_arr[1]), float(col_arr[2]))
	# Malla y material compartidos por tipo: antes cada enemigo del pool creaba
	# su propio CapsuleMesh + ShaderMaterial (60 materiales por tipo).
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = radius * 4.0 + 0.4
	var mat := ShaderMaterial.new()
	mat.shader = load("res://fx/toon.gdshader")
	mat.set_shader_parameter("base_color", base_color)
	mesh.material = mat
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
		e.radius = radius
		e.explode_radius = float(def.get("explode_radius", 0.0))
		e.explode_dmg = float(def.get("explode_dmg", 0.0))
		e.summon_kind = String(def.get("summon", ""))
		e.summon_count = int(def.get("summon_count", 0))
		e.summon_hp = float(def.get("summon_hp", 1.0))
		e.summon_interval = float(def.get("summon_interval", 0.0))
		e.xp_value = int(def.get("xp", 1))
		e.base_color = base_color
		e.visual = _make_visual(mesh, radius)
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
			# disco de telegrafiado del slam (radio visible durante el aviso)
			var disc := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = e.tele_radius
			cyl.bottom_radius = e.tele_radius
			cyl.height = 0.06
			var dmat := StandardMaterial3D.new()
			dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			dmat.albedo_color = Color(1.0, 0.15, 0.1, 0.0)
			cyl.material = dmat
			disc.mesh = cyl
			disc.position.y = 0.08
			disc.visible = false
			e.visual.add_child(disc)
			e.tele_disc = disc
		e.visible = false
		add_child(e)
		arr.append(e)
	_pools[kind] = arr
	_free_pool[kind] = arr.duplicate()


func _make_visual(mesh: CapsuleMesh, radius: float) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = mesh.height * 0.5 - radius * 0.5
	root.add_child(mi)
	return root


func spawn(kind: String, pos: Vector3, hp_mult: float = 1.0, elite: bool = false) -> void:
	ensure_pool(kind, 60)
	var free = _free_pool.get(kind)
	if free == null or free.is_empty():
		return  # presupuesto alcanzado: se ignora el spawn
	var e: Enemy = free.pop_back()
	e.visible = true
	e.elite = elite
	e.dmg = e.base_dmg * GameState.run_dmg_scale
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
	var terr := GameState.terrain
	if terr != null:
		gy = terr.height_at(pos.x, pos.z)
	e.position = Vector3(pos.x, gy, pos.z)
	e.attack_cd = 0.0
	e.bob_t = randf() * TAU
	e.pat_t = 0.0
	e.sum_t = 0.0
	e.tele_t = -1.0
	e.charge_t = -1.0
	e.hit_flash = 0.0
	e.visual.scale = Vector3.ONE
	if e.tele_disc != null:
		((e.tele_disc.mesh as CylinderMesh).material as StandardMaterial3D).albedo_color.a = 0.0
		e.tele_disc.visible = false
	_add_active(e)
	if e.boss:
		boss_ref = e


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
	var terr := GameState.terrain
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
		else:
			var seek := Vector3.ZERO
			if dist > 0.001:
				seek = (to_p / dist) * e.speed
			var sep := _separation(e)
			var vel := (seek * 0.9 + sep) * dt * e.slow_mult
			e.position += vel
			if e.summon_kind != "" and e.summon_count > 0 and e.summon_interval > 0.0:
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
		if terr != null:
			e.position.y = terr.height_at(e.position.x, e.position.z)
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


## IA del jefe (roadmap 3.4): arquetipos data-driven.
## - "slam": telegrafía un disco y golpea AoE (Coloso, Reina).
## - "charge": aviso corto y embestida a 16 m/s (Guardián del bosque).
func _boss_think(e: Enemy, dt: float, ppos: Vector3) -> void:
	e.sum_t += dt
	if e.atk_kind == "charge":
		_boss_charge(e, dt, ppos)
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
	_remove_active(e)
	var free = _free_pool.get(e.kind)
	if free != null:
		free.append(e)
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
		GameState.hitstop(110)
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
	if e.elite:
		GameState.hitstop(35)
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
	GameState.damage_dealt += final_dmg
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


func _add_active(e: Enemy) -> void:
	_active_pos[e.get_instance_id()] = _active.size()
	_active.append(e)


## Baja O(1): intercambia con el último en vez de desplazar todo el array.
func _remove_active(e: Enemy) -> void:
	var id := e.get_instance_id()
	var idx = _active_pos.get(id)
	if idx == null:
		return
	var last: Enemy = _active[_active.size() - 1]
	_active[idx] = last
	_active_pos[last.get_instance_id()] = idx
	_active.pop_back()
	_active_pos.erase(id)


## Reutiliza los arrays de celda entre ticks: antes se creaba uno nuevo por celda
## con enemigos, 30 veces por segundo (churn de allocator en móvil).
func _build_grid() -> void:
	for key in _grid_keys:
		(_grid[key] as Array).clear()
	_grid_keys.clear()
	for e in _active:
		if not is_instance_valid(e) or not e.visible:
			continue
		var key := _cell_key(e.position.x, e.position.z)
		var arr = _grid.get(key)
		if arr == null:
			arr = []
			_grid[key] = arr
		if arr.is_empty():
			_grid_keys.append(key)
		arr.append(e)


func _separation(e: Enemy) -> Vector3:
	var push := Vector3.ZERO
	var cx := int(floor(e.position.x / CELL))
	var cz := int(floor(e.position.z / CELL))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr = _grid.get((cx + dx) * 4093 + (cz + dz))
			if arr == null:
				continue
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
			var arr = _grid.get((cx + dx) * 4093 + (cz + dz))
			if arr == null:
				continue
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
			var arr = _grid.get(gx * 4093 + gz)
			if arr == null:
				continue
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
			var arr = _grid.get(gx * 4093 + gz)
			if arr == null:
				continue
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
			var arr = _grid.get(gx * 4093 + gz)
			if arr == null:
				continue
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
## Radios cortos (cuchillas, cadena, mazo) usan la grilla en vez de recorrer toda
## la horda; los radios largos (auto-aim) siguen con el barrido lineal, que es más
## barato que abrir cientos de celdas.
func nearest(pos: Vector3, radius: float, excluded: Dictionary = {}):
	var best = null
	var best_d := radius
	if radius <= 12.0:
		var cx0 := int(floor((pos.x - radius) / CELL)) - 1
		var cx1 := int(floor((pos.x + radius) / CELL)) + 1
		var cz0 := int(floor((pos.z - radius) / CELL)) - 1
		var cz1 := int(floor((pos.z + radius) / CELL)) + 1
		for gx in range(cx0, cx1 + 1):
			for gz in range(cz0, cz1 + 1):
				var arr = _grid.get(gx * 4093 + gz)
				if arr == null:
					continue
				for e in arr:
					if not e.visible or excluded.has(e.get_instance_id()):
						continue
					var dx: float = e.position.x - pos.x
					var dz: float = e.position.z - pos.z
					var d := sqrt(dx * dx + dz * dz)
					if d < best_d:
						best_d = d
						best = e
		return best
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
	# _active solo contiene enemigos vivos (se da de baja O(1) en _kill).
	return _active.size()


func _respawn_edge(ppos: Vector3) -> Vector3:
	var a := randf() * TAU
	return ppos + Vector3(cos(a), 0.0, sin(a)) * 34.0


func reset() -> void:
	_active.clear()
	_active_pos.clear()
	_grid.clear()
	_grid_keys.clear()
	boss_ref = null
	for kind in _pools:
		var free = _free_pool.get(kind)
		if free == null:
			free = []
			_free_pool[kind] = free
		free.clear()
		for e in (_pools[kind] as Array):
			e.visible = false
			e.position = Vector3(0, -50, 0)
			free.append(e)
