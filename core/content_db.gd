## ContentDB — tablas data-driven (guía §3.3/§3.4).
## Carga weapons.json / enemies.json / spawn_table.json / upgrades.json.
extends Node


var weapons: Dictionary = {}
var enemies: Dictionary = {}
var spawn_table: Dictionary = {}
var upgrades: Array = []
var biomes: Array = []   # data-driven (roadmap 3.1); fallback sintetizado si falta
var evolutions: Array = []  # recetas arma L8 + pasiva → arma evolucionada (roadmap 2.2)
var characters: Dictionary = {}   # personajes jugables (roadmap 4.2)
var meta_upgrades: Array = []     # tienda meta (roadmap 4.1)
var curses: Array = []            # maldiciones de dificultad (roadmap 4.3)
var achievements: Array = []      # logros locales (roadmap 4.4)

const MAX_WEAPON_LEVEL := 8


func _ready() -> void:
	weapons = _load_dict("res://data/weapons.json")
	enemies = _load_dict("res://data/enemies.json")
	spawn_table = _load_dict("res://data/spawn_table.json")
	upgrades = _load_array("res://data/upgrades.json")
	evolutions = _load_array("res://data/evolutions.json")
	characters = _load_dict("res://data/characters.json")
	meta_upgrades = _load_array("res://data/meta.json")
	curses = _load_array("res://data/curses.json")
	achievements = _load_array("res://data/achievements.json")
	_load_biomes()


func weapon_display(id: String) -> String:
	var def: Dictionary = weapons.get(id, {})
	return String(def.get("display", id))


func _load_biomes() -> void:
	var wrapper := _load_dict("res://data/biomes.json")
	if not wrapper.is_empty() and wrapper.has("biomes") and wrapper["biomes"] is Array:
		biomes = wrapper["biomes"]
		return
	# Fallback: un bioma único heredando spawn_table.json ( compatibilidad )
	var tiers: Array = spawn_table.get("by_minute", [])
	biomes = [{
		"id": "bosque", "name": "Claro", "t_start": 0,
		"ground": [0.24, 0.33, 0.30], "bg": [0.09, 0.08, 0.14],
		"ambient": [0.55, 0.55, 0.75], "light": [1.0, 0.95, 0.85], "light_energy": 1.1,
		"props": { "kind": "rock", "count": 40, "color": [0.45, 0.42, 0.5] },
		"tiers": tiers,
		"events": spawn_table.get("ring_events", []),
	}]


func _load_dict(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ContentDB: no se pudo abrir %s" % path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_error("ContentDB: formato inválido en %s" % path)
		return {}
	return data


func _load_array(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("ContentDB: no se pudo abrir %s" % path)
		return []
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Array):
		push_error("ContentDB: formato inválido en %s" % path)
		return []
	return data


## Rueda 3 mejoras distintas, ponderadas por rareza, excluyendo las al tope.
## Incluye cartas dinámicas de nivel de arma (2.6) y evoluciones (2.2).
func roll_upgrades(counts: Dictionary) -> Array:
	var pool: Array = []
	for u in upgrades:
		var stack: int = int(counts.get(String(u["id"]), 0))
		if stack < int(u["max"]) and not GameState.banished.has(String(u["id"])):
			pool.append(u)
	var evo_cards: Array = []
	for e in _evolution_cards(counts):
		if not GameState.banished.has(String(e.get("id", ""))):
			evo_cards.append(e)
	pool.append_array(evo_cards)
	for c in _weapon_level_cards():
		if not GameState.banished.has(String(c.get("id", ""))):
			pool.append(c)
	var picked: Array = []
	while picked.size() < 3 and pool.size() > 0:
		var total := 0.0
		for u in pool:
			total += _eff_weight(u)
		var roll := randf() * maxf(total, 0.001)
		var chosen: Dictionary = {}
		for u in pool:
			roll -= _eff_weight(u)
			if roll <= 0.0:
				chosen = u
				break
		if chosen.is_empty():
			chosen = pool[0]
		picked.append(chosen)
		pool.erase(chosen)
	# Garantía: si una evolución está disponible, aparece siempre entre las 3
	if not evo_cards.is_empty():
		var has_evo := false
		for p in picked:
			if String(p.get("effect", "")) == "evolve":
				has_evo = true
		if not has_evo:
			picked[picked.size() - 1] = evo_cards[0]
	return picked


## Peso efectivo de una carta: la pasiva suerte (roadmap 2.4) amplifica las rarezas.
func _eff_weight(u: Dictionary) -> float:
	var w := float(u.get("weight", 1.0))
	if String(u.get("rarity", "comun")) != "comun":
		w *= 1.0 + 0.3 * float(GameState.luck)
	return w


## Cartas "mejorar arma X" para las armas en propiedad por debajo del tope.
func _weapon_level_cards() -> Array:
	var out: Array = []
	for w in GameState.weapons:
		var lvl := int(GameState.weapon_levels.get(w, 1))
		if lvl >= MAX_WEAPON_LEVEL:
			continue
		out.append({
			"id": "wlv_" + w,
			"name": "Mejorar %s (Nv %d)" % [weapon_display(w), lvl],
			"desc": "Nivel %d → %d: +12%% daño y +6%% cadencia" % [lvl, lvl + 1],
			"effect": "weapon_up",
			"weapon": w,
			"weight": 72,
			"max": 99,
			"rarity": "comun",
		})
	return out


## Recetas disponibles: arma base owned + nivel requerido + pasiva con stacks.
func _evolution_cards(counts: Dictionary) -> Array:
	var out: Array = []
	for ev in evolutions:
		var base := String(ev.get("base", ""))
		var result := String(ev.get("result", ""))
		if base == "" or result == "":
			continue
		if not GameState.weapons.has(base) or GameState.weapons.has(result):
			continue
		if int(GameState.weapon_levels.get(base, 1)) < int(ev.get("weapon_level", MAX_WEAPON_LEVEL)):
			continue
		var passive := String(ev.get("passive", ""))
		if passive != "" and int(counts.get(passive, 0)) < int(ev.get("passive_levels", 1)):
			continue
		out.append({
			"id": String(ev.get("id", "evo_" + result)),
			"name": String(ev.get("name", result)),
			"desc": String(ev.get("desc", "")),
			"effect": "evolve",
			"base": base,
			"result": result,
			"weight": 9999,
			"max": 1,
			"rarity": "legendario",
		})
	return out
