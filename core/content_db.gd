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
var synergies: Array = []         # sinergias por etiquetas (combate)
var contracts: Array = []
var relics: Array = []
var balance: Dictionary = {}      # curva de XP, furia y telemetría
var tag_pool := {}                # etiqueta → true (para validar sinergias)

const MAX_WEAPON_LEVEL := 8
const KNOWN_PATTERNS := ["nearest", "orbit", "aura", "boomerang", "mine", "chain",
	"spiral", "slam", "meteor", "drone", "void"]


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
	synergies = _load_array("res://data/synergies.json")
	contracts = _load_array("res://data/contracts.json")
	relics = _load_array("res://data/relics.json")
	balance = _load_dict("res://data/balance.json")
	_load_biomes()
	_index_tags()
	var errs := validate()
	for e in errs:
		push_warning("ContentDB: " + e)
	if GameState != null and GameState.debug_auto_upgrade:
		print("CONTENT_OK weapons=%d enemies=%d upgrades=%d evolutions=%d synergies=%d tags=%d errors=%d" % [
			weapons.size(), enemies.size(), upgrades.size(), evolutions.size(),
			synergies.size(), tag_pool.size(), errs.size(),
		])


func _index_tags() -> void:
	tag_pool = {}
	for id in weapons:
		for t in tags_of(weapons[id]):
			tag_pool[t] = true
	for u in upgrades:
		for t in tags_of(u):
			tag_pool[t] = true


func tags_of(def: Dictionary) -> Array:
	var raw = def.get("tags", [])
	return raw if raw is Array else []


func upgrade_def(id: String) -> Dictionary:
	for u in upgrades:
		if String(u.get("id", "")) == id:
			return u
	return {}


func contract_def(id: String) -> Dictionary:
	for contract in contracts:
		if String(contract.get("id", "")) == id:
			return contract
	return {}


func relic_def(id: String) -> Dictionary:
	for relic in relics:
		if String(relic.get("id", "")) == id:
			return relic
	return {}


func roll_relics(count: int) -> Array:
	var pool: Array = []
	for relic in relics:
		var id := String(relic.get("id", ""))
		if not GameState.relic_ids.has(id) and not GameState.banished.has(id):
			pool.append(relic)
	pool.shuffle()
	var choices: Array = []
	for relic in pool.slice(0, mini(count, pool.size())):
		var card: Dictionary = relic.duplicate(true)
		card["effect"] = "relic"
		card["rarity"] = "legendario"
		choices.append(card)
	return choices


## Validador de contenido data-driven: devuelve una lista de errores legibles.
## Se ejecuta al cargar para detectar JSON incoherente sin abrir la escena.
func validate() -> Array:
	var errs: Array = []
	if weapons.is_empty():
		errs.append("weapons.json vacío")
	for id in weapons:
		var w: Dictionary = weapons[id]
		var pattern := String(w.get("pattern", ""))
		if pattern.is_empty() or not KNOWN_PATTERNS.has(pattern):
			errs.append("arma %s: pattern inválido '%s'" % [id, pattern])
		if String(w.get("display", "")).is_empty():
			errs.append("arma %s: falta display" % id)
		if float(w.get("dmg", -1.0)) < 0.0:
			errs.append("arma %s: dmg inválido" % id)
	var up_ids := {}
	for u in upgrades:
		var uid := String(u.get("id", ""))
		if uid.is_empty():
			errs.append("upgrade sin id")
			continue
		up_ids[uid] = true
		if String(u.get("name", "")).is_empty():
			errs.append("upgrade %s: falta name" % uid)
		if String(u.get("effect", "")).is_empty():
			errs.append("upgrade %s: falta effect" % uid)
		if float(u.get("weight", 0.0)) <= 0.0:
			errs.append("upgrade %s: weight debe ser > 0" % uid)
		if int(u.get("max", 0)) < 1:
			errs.append("upgrade %s: max debe ser >= 1" % uid)
		if String(u.get("effect", "")) == "weapon":
			var wid := String(u.get("weapon", ""))
			if not weapons.has(wid):
				errs.append("upgrade %s: arma inexistente '%s'" % [uid, wid])
	for ev in evolutions:
		var eid := String(ev.get("id", "?"))
		if not weapons.has(String(ev.get("base", ""))):
			errs.append("evolución %s: base inexistente" % eid)
		if not weapons.has(String(ev.get("result", ""))):
			errs.append("evolución %s: result inexistente" % eid)
		var passive := String(ev.get("passive", ""))
		if not passive.is_empty() and not up_ids.has(passive):
			errs.append("evolución %s: pasiva inexistente '%s'" % [eid, passive])
	for s in synergies:
		var sid := String(s.get("id", "?"))
		var tags = s.get("tags", [])
		if not (tags is Array) or tags.is_empty():
			errs.append("sinergia %s: tags vacío" % sid)
			continue
		for t in tags:
			if not tag_pool.has(String(t)):
				errs.append("sinergia %s: etiqueta desconocida '%s'" % [sid, t])
		if int(s.get("need", 0)) < 1:
			errs.append("sinergia %s: need debe ser >= 1" % sid)
		if int(s.get("max_stacks", 0)) < int(s.get("need", 1)):
			errs.append("sinergia %s: max_stacks < need" % sid)
	var contract_ids := {}
	for c in contracts:
		if not (c is Dictionary):
			errs.append("contrato con formato inválido")
			continue
		var cid := String(c.get("id", ""))
		if cid.is_empty() or contract_ids.has(cid):
			errs.append("contrato sin id o id duplicado '%s'" % cid)
		contract_ids[cid] = true
		if String(c.get("name", "")).is_empty():
			errs.append("contrato %s: falta name" % cid)
		if not ["kills", "bosses", "time", "relics"].has(String(c.get("stat", ""))):
			errs.append("contrato %s: stat inválido" % cid)
		if int(c.get("goal", 0)) < 1 or int(c.get("reward", 0)) < 0:
			errs.append("contrato %s: goal o reward inválido" % cid)
	var relic_ids := {}
	for r in relics:
		if not (r is Dictionary):
			errs.append("reliquia con formato inválido")
			continue
		var rid := String(r.get("id", ""))
		if rid.is_empty() or relic_ids.has(rid):
			errs.append("reliquia sin id o id duplicado '%s'" % rid)
		relic_ids[rid] = true
		var effects = r.get("effects", [])
		if String(r.get("name", "")).is_empty() or not (effects is Array) or effects.is_empty():
			errs.append("reliquia %s: falta name o effects" % rid)
			continue
		for effect in effects:
			if not (effect is Dictionary):
				errs.append("reliquia %s: efecto con formato inválido" % rid)
				continue
			if not ["dmg_mult", "fire_mult", "max_hp", "move_speed", "armor", "coin_mult"].has(
					String(effect.get("stat", ""))):
				errs.append("reliquia %s: stat inválido" % rid)
			if not ["add", "multiply"].has(String(effect.get("operation", ""))):
				errs.append("reliquia %s: operation inválida" % rid)
	for id in enemies:
		var e: Dictionary = enemies[id]
		if float(e.get("hp", 0.0)) <= 0.0:
			errs.append("enemigo %s: hp inválido" % id)
		if float(e.get("speed", 0.0)) < 0.0:
			errs.append("enemigo %s: speed inválido" % id)
	var fury: Dictionary = balance.get("fury", {}) if balance.get("fury", {}) is Dictionary else {}
	if float(fury.get("max", 0.0)) <= 0.0:
		errs.append("balance.fury.max debe ser > 0")
	if float(fury.get("duration", 0.0)) <= 0.0:
		errs.append("balance.fury.duration debe ser > 0")
	if float(fury.get("dmg_mult", 0.0)) < 1.0:
		errs.append("balance.fury.dmg_mult debe ser >= 1")
	if float(fury.get("fire_mult", 0.0)) < 1.0:
		errs.append("balance.fury.fire_mult debe ser >= 1")
	var tel: Dictionary = balance.get("telemetry", {}) if balance.get("telemetry", {}) is Dictionary else {}
	if int(tel.get("max_entries", 0)) < 10:
		errs.append("balance.telemetry.max_entries debe ser >= 10")
	if biomes.is_empty():
		errs.append("biomes.json vacío")
	return errs



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
