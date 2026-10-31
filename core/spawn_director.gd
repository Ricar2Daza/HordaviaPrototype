## SpawnDirector — pacing de hordas data-driven (guía §3.3).
## Autoload. Lee spawn_table.json: budget/seg por minuto, pool ponderado, hp_mult y eventos.
extends Node

var _budget_accum := 0.0
var _events_done := {}
var _last_tier_idx := -1
var _spawned_total := 0
var _next_print := 10
var _next_elite_t := 90.0   # segundos de run del próximo élite
var _biome_idx := -1
var _boss_spawned := false
var _last_loop := -1
const BIOME_MINUTES := 6.0   # duración de cada bioma antes de repetir el ciclo


func _ready() -> void:
	GameState.run_reset.connect(reset)
	GameState.run_started.connect(reset)


func _physics_process(dt: float) -> void:
	if not GameState.run_active:
		return
	var biomes: Array = ContentDB.biomes
	if biomes.is_empty():
		return
	var t := GameState.run_time
	# Bioma activo por tiempo; al acabar el último, el mapa vuelve a empezar
	# con enemigos más fuertes (supervivencia sin fin).
	var idx := 0
	var cycle_len := float(biomes.size()) * BIOME_MINUTES * 60.0
	var local_t := t
	if GameState.debug_auto_upgrade:
		idx = 0 if t < 25.0 else (1 if t < 50.0 else 2)
		GameState.endless_loop = 0
	else:
		GameState.endless_loop = int(t / cycle_len)
		local_t = t - float(GameState.endless_loop) * cycle_len
		for i in biomes.size():
			if float(biomes[i].get("t_start", 0)) * 60.0 <= local_t:
				idx = i
	idx = clampi(idx, 0, biomes.size() - 1)
	# Escalado continuo: vida/daño/presión suben con los minutos y cada ciclo.
	var mins := t / 60.0
	GameState.run_hp_scale = 1.0 + 0.16 * mins + 0.06 * pow(mins, 1.5)
	GameState.run_dmg_scale = minf(1.0 + 0.045 * mins, 2.6)
	GameState.spawn_mult = GameState.curse_spawn_mult * (1.0 + 0.22 * float(GameState.endless_loop) + 0.012 * mins)
	if idx != _biome_idx or GameState.endless_loop != _last_loop:
		_biome_idx = idx
		_last_loop = GameState.endless_loop
		_events_done.clear()
		_boss_spawned = false
		GameState.biome_changed.emit(biomes[idx])
	var biome: Dictionary = biomes[_biome_idx]
	var t_start := float(biome.get("t_start", 0)) * 60.0
	if GameState.debug_auto_upgrade:
		t_start = [0.0, 25.0, 50.0][mini(_biome_idx, 2)]
	var t_local_min := ((local_t if not GameState.debug_auto_upgrade else t) - t_start) / 60.0

	var tiers: Array = biome.get("tiers", [])
	if tiers.is_empty():
		return
	var tier: Dictionary = tiers[0]
	for cand in tiers:
		if float(cand.get("t", 0)) <= t_local_min:
			tier = cand

	_budget_accum += float(tier.get("budget", 6)) * dt * GameState.spawn_mult
	_tick_elite(tier)
	var cap := mini(int(ContentDB.spawn_table.get("cap", 220)), GameState.enemy_cap)
	while _budget_accum >= 1.0:
		_budget_accum -= 1.0
		if EnemyManager.active_count() >= cap:
			break
		_spawn_one(tier)
		_spawned_total += 1
	if _spawned_total > 0 and GameState.debug_auto_upgrade and int(GameState.run_time) >= _next_print:
		_next_print = int(GameState.run_time) + 10
		print("SMOKE_TICK t=%d spawned=%d active=%d kills=%d biome=%s" % [
			int(GameState.run_time), _spawned_total, EnemyManager.active_count(),
			GameState.kills, String(biome.get("id", "?")),
		])

	# Eventos ring relativos al bioma activo
	var events: Array = biome.get("events", [])
	for ev in events:
		var key := str(ev.get("t", 0.0)) + "ring" + str(ev.get("count", 0)) + str(ev.get("radius", 0.0))
		if t_local_min >= float(ev.get("t", -1.0)) and not _events_done.has(key):
			_events_done[key] = true
			var hp_mult := float(tier.get("hp_mult", 1.0))
			EnemyManager.spawn_ring(
				String(ev.get("enemy", "goblin")),
				EnemyManager.player.position if EnemyManager.player != null else Vector3.ZERO,
				int(ev.get("count", 20)),
				float(ev.get("radius", 20.0)),
				hp_mult
			)

	# Jefe del bioma (roadmap 3.4): entra tras boss_t segundos locales
	var boss_t := float(biome.get("boss_t", -1.0))
	if boss_t >= 0.0 and not _boss_spawned and not EnemyManager.boss_active():
		var boss_at := boss_t if not GameState.debug_auto_upgrade else 12.0
		if local_t - t_start >= boss_at:
			_boss_spawned = true
			var bk := String(biome.get("boss_key", "boss_final"))
			print("SMOKE_BOSS spawn (bio=%s key=%s)" % [String(biome.get("id", "?")), bk])
			var center: Vector3 = EnemyManager.player.position if EnemyManager.player != null else Vector3.ZERO
			var ang := randf() * TAU
			EnemyManager.spawn(
				bk,
				center + Vector3(cos(ang), 0.0, sin(ang)) * 9.0,
				float(tier.get("hp_mult", 1.0)),
				false
			)


func _spawn_one(tier: Dictionary) -> void:
	var pools: Dictionary = tier.get("pools", {"goblin": 100})
	if pools.is_empty():
		return
	var total := 0.0
	for k in pools:
		total += float(pools[k])
	var roll := randf() * maxf(total, 0.001)
	var kind := "goblin"
	for k in pools:
		roll -= float(pools[k])
		if roll <= 0.0:
			kind = k
			break
	var center: Vector3 = EnemyManager.player.position if EnemyManager.player != null else Vector3.ZERO
	var a := randf() * TAU
	var r := randf_range(18.0, 28.0)
	EnemyManager.spawn(kind, center + Vector3(cos(a), 0.0, sin(a)) * r, float(tier.get("hp_mult", 1.0)))


func reset() -> void:
	_budget_accum = 0.0
	_events_done = {}
	_last_tier_idx = -1
	_next_elite_t = 90.0
	_biome_idx = -1
	_boss_spawned = false


## Élite cada 90 s: escoge un kind del tier actual (prefiere brute) y lo suelta en ring.
func _tick_elite(tier: Dictionary) -> void:
	if GameState.run_time < _next_elite_t:
		return
	_next_elite_t = GameState.run_time + 90.0
	var pools: Dictionary = tier.get("pools", {})
	var kind := ""
	if pools.has("brute"):
		kind = "brute"
	elif not pools.is_empty():
		kind = String(pools.keys()[0])
	if kind == "":
		kind = "goblin"
	var center: Vector3 = EnemyManager.player.position if EnemyManager.player != null else Vector3.ZERO
	EnemyManager.spawn_ring(kind, center, 1, 22.0, float(tier.get("hp_mult", 1.0)), true)
