## Validador de contenido data-driven (CI / local).
## Uso:
##   godot --headless --path . --script res://tools/validate_content.gd
## Sale con código 0 si todo está bien; 1 si hay errores de referencias/formato.
extends SceneTree

const PATHS := {
	"weapons": "res://data/weapons.json",
	"enemies": "res://data/enemies.json",
	"spawn": "res://data/spawn_table.json",
	"upgrades": "res://data/upgrades.json",
	"evolutions": "res://data/evolutions.json",
	"characters": "res://data/characters.json",
	"meta": "res://data/meta.json",
	"curses": "res://data/curses.json",
	"achievements": "res://data/achievements.json",
	"biomes": "res://data/biomes.json",
}

const RARITIES := ["comun", "raro", "epico", "legendario"]
const BOSS_ATTACKS := ["slam", "charge", "volley"]
const ACHIEVEMENT_STATS := [
	"total_kills", "boss_kills", "victories", "runs_played", "best_time", "coins_earned",
]

var _errors: Array[String] = []
var _warns: Array[String] = []


func _initialize() -> void:
	var weapons := _dict(PATHS["weapons"])
	var enemies := _dict(PATHS["enemies"])
	var spawn := _dict(PATHS["spawn"])
	var upgrades := _array(PATHS["upgrades"])
	var evolutions := _array(PATHS["evolutions"])
	var characters := _dict(PATHS["characters"])
	var meta := _array(PATHS["meta"])
	var curses := _array(PATHS["curses"])
	var achievements := _array(PATHS["achievements"])
	var biomes := _biomes()

	_validate_weapons(weapons)
	_validate_enemies(enemies)
	_validate_upgrades(upgrades, weapons)
	_validate_evolutions(evolutions, weapons, upgrades)
	_validate_biomes(biomes, enemies)
	_validate_spawn(spawn, enemies)
	_validate_characters(characters)
	_validate_meta(meta)
	_validate_curses(curses)
	_validate_achievements(achievements)

	if _errors.is_empty():
		print("CONTENT_OK warnings=%d" % _warns.size())
		for w in _warns:
			print("CONTENT_WARN " + w)
		quit(0)
	else:
		for e in _errors:
			printerr("CONTENT_ERROR " + e)
		print("CONTENT_FAIL errors=%d warnings=%d" % [_errors.size(), _warns.size()])
		quit(1)


# ---------------------------------------------------------------- validaciones --
func _validate_weapons(weapons: Dictionary) -> void:
	_unique_keys("weapons", weapons.keys())
	if not weapons.has("wand"):
		_error("weapons: falta el arma inicial 'wand'")
	for id in weapons:
		var def: Dictionary = weapons[id]
		_need(def, ["display", "pattern", "dmg"], "weapons.%s" % id)
		if float(def.get("dmg", 0.0)) <= 0.0:
			_error("weapons.%s: dmg debe ser > 0" % id)
		if not (def.has("interval") or def.has("ticks") or def.has("duration")):
			_error("weapons.%s: falta interval/ticks/duration" % id)


func _validate_enemies(enemies: Dictionary) -> void:
	_unique_keys("enemies", enemies.keys())
	for id in enemies:
		var def: Dictionary = enemies[id]
		_need(def, ["hp", "speed", "dmg", "radius"], "enemies.%s" % id)
		if float(def.get("hp", 0.0)) <= 0.0:
			_error("enemies.%s: hp debe ser > 0" % id)
		if float(def.get("radius", 0.0)) <= 0.0:
			_error("enemies.%s: radius debe ser > 0" % id)
		if bool(def.get("ranged", false)):
			for key in ["attack_range", "attack_interval", "projectile_speed", "projectile_dmg"]:
				if float(def.get(key, 0.0)) <= 0.0:
					_error("enemies.%s: %s debe ser > 0 para enemigo a distancia" % [id, key])
			if float(def.get("keep_range", 0.0)) < 0.0:
				_error("enemies.%s: keep_range no puede ser negativo" % id)
			var pc: Variant = def.get("projectile_color", [])
			if not pc is Array or (pc as Array).size() < 3:
				_error("enemies.%s: projectile_color debe tener 3 componentes" % id)
		if bool(def.get("boss", false)):
			var atk := String(def.get("boss_attack", ""))
			if not BOSS_ATTACKS.has(atk):
				_error("enemies.%s: boss_attack '%s' inválido" % [id, atk])
			if atk == "volley":
				for key in ["volley_count", "volley_speed", "volley_dmg"]:
					if float(def.get(key, 0.0)) <= 0.0:
						_error("enemies.%s: %s debe ser > 0 para jefe volley" % [id, key])


func _validate_upgrades(upgrades: Array, weapons: Dictionary) -> void:
	var ids: Array = []
	for item in upgrades:
		if not item is Dictionary:
			_error("upgrades: entrada no es objeto")
			continue
		var def: Dictionary = item
		var id := String(def.get("id", ""))
		ids.append(id)
		_need(def, ["name", "desc", "effect", "weight", "max", "rarity"], "upgrades.%s" % id)
		if int(def.get("max", 0)) <= 0:
			_error("upgrades.%s: max debe ser > 0" % id)
		if float(def.get("weight", 0.0)) <= 0.0:
			_error("upgrades.%s: weight debe ser > 0" % id)
		if not RARITIES.has(String(def.get("rarity", ""))):
			_error("upgrades.%s: rareza '%s' inválida" % [id, String(def.get("rarity", ""))])
		if String(def.get("effect", "")) == "weapon":
			var wid := String(def.get("weapon", ""))
			if not weapons.has(wid):
				_error("upgrades.%s: arma '%s' no existe" % [id, wid])
	_unique_keys("upgrades", ids)


func _validate_evolutions(evolutions: Array, weapons: Dictionary, upgrades: Array) -> void:
	var upgrade_ids := {}
	for u in upgrades:
		if u is Dictionary:
			upgrade_ids[String(u.get("id", ""))] = true
	var ids: Array = []
	for item in evolutions:
		if not item is Dictionary:
			_error("evolutions: entrada no es objeto")
			continue
		var def: Dictionary = item
		var id := String(def.get("id", ""))
		ids.append(id)
		_need(def, ["base", "passive", "result", "weapon_level", "passive_levels"], "evolutions.%s" % id)
		var base := String(def.get("base", ""))
		var result := String(def.get("result", ""))
		var passive := String(def.get("passive", ""))
		if not weapons.has(base):
			_error("evolutions.%s: arma base '%s' no existe" % [id, base])
		if not weapons.has(result):
			_error("evolutions.%s: arma resultado '%s' no existe" % [id, result])
		if not upgrade_ids.has(passive):
			_error("evolutions.%s: pasiva '%s' no existe" % [id, passive])
		if base == result:
			_error("evolutions.%s: base y resultado son iguales" % id)
		var wl := int(def.get("weapon_level", 0))
		if wl < 1 or wl > 8:
			_error("evolutions.%s: weapon_level %d fuera de 1..8" % [id, wl])
		if int(def.get("passive_levels", 0)) < 1:
			_error("evolutions.%s: passive_levels debe ser >= 1" % id)
	_unique_keys("evolutions", ids)


func _validate_biomes(biomes: Array, enemies: Dictionary) -> void:
	var ids: Array = []
	var boss_seen := {}
	var last_t := -1.0
	for item in biomes:
		if not item is Dictionary:
			_error("biomes: entrada no es objeto")
			continue
		var b: Dictionary = item
		var id := String(b.get("id", ""))
		ids.append(id)
		_need(b, ["name", "t_start", "boss_key", "tiers"], "biomes.%s" % id)
		var boss := String(b.get("boss_key", ""))
		if not enemies.has(boss):
			_error("biomes.%s: boss_key '%s' no existe" % [id, boss])
		elif not bool(enemies[boss].get("boss", false)):
			_error("biomes.%s: '%s' no está marcado como boss" % [id, boss])
		if boss_seen.has(boss):
			_error("biomes.%s: boss_key '%s' repetido; cada bioma necesita un jefe propio" % [id, boss])
		boss_seen[boss] = true
		var t := float(b.get("t_start", 0.0))
		if t < last_t:
			_error("biomes.%s: t_start no es creciente" % id)
		last_t = t
		var tiers: Array = b.get("tiers", [])
		if tiers.is_empty():
			_error("biomes.%s: tiers vacío" % id)
		for tier in tiers:
			if not tier is Dictionary:
				_error("biomes.%s: tier no es objeto" % id)
				continue
			_validate_pools(tier.get("pools", {}), enemies, "biomes.%s.tier" % id)
		for ev in b.get("events", []):
			if ev is Dictionary and not enemies.has(String(ev.get("enemy", ""))):
				_error("biomes.%s.events: enemigo '%s' no existe" % [id, String(ev.get("enemy", ""))])
	_unique_keys("biomes", ids)


func _validate_spawn(spawn: Dictionary, enemies: Dictionary) -> void:
	if int(spawn.get("cap", 0)) <= 0:
		_error("spawn_table: cap debe ser > 0")
	var by_minute: Array = spawn.get("by_minute", [])
	if by_minute.is_empty():
		_error("spawn_table: by_minute vacío")
	for tier in by_minute:
		if tier is Dictionary:
			_validate_pools(tier.get("pools", {}), enemies, "spawn_table.by_minute")
	for ev in spawn.get("ring_events", []):
		if ev is Dictionary and not enemies.has(String(ev.get("enemy", ""))):
			_error("spawn_table.ring_events: enemigo '%s' no existe" % String(ev.get("enemy", "")))


func _validate_characters(characters: Dictionary) -> void:
	_unique_keys("characters", characters.keys())
	if characters.is_empty():
		_error("characters: no hay personajes")
	for id in characters:
		var def: Dictionary = characters[id]
		_need(def, ["name", "hp", "speed"], "characters.%s" % id)
		if float(def.get("hp", 0.0)) <= 0.0:
			_error("characters.%s: hp debe ser > 0" % id)
		if float(def.get("speed", 0.0)) <= 0.0:
			_error("characters.%s: speed debe ser > 0" % id)


func _validate_meta(meta: Array) -> void:
	var ids: Array = []
	for item in meta:
		if not item is Dictionary:
			_error("meta: entrada no es objeto")
			continue
		var def: Dictionary = item
		var id := String(def.get("id", ""))
		ids.append(id)
		_need(def, ["name", "max", "cost", "step"], "meta.%s" % id)
		if int(def.get("max", 0)) <= 0:
			_error("meta.%s: max debe ser > 0" % id)
		if int(def.get("cost", 0)) <= 0:
			_error("meta.%s: cost debe ser > 0" % id)
		if int(def.get("step", 0)) < 0:
			_error("meta.%s: step no puede ser negativo" % id)
	_unique_keys("meta", ids)


func _validate_curses(curses: Array) -> void:
	var ids: Array = []
	for item in curses:
		if not item is Dictionary:
			_error("curses: entrada no es objeto")
			continue
		var def: Dictionary = item
		var id := String(def.get("id", ""))
		ids.append(id)
		_need(def, ["name", "hp", "spawn", "coins"], "curses.%s" % id)
		if float(def.get("hp", 0.0)) <= 0.0:
			_error("curses.%s: hp debe ser > 0" % id)
		if float(def.get("spawn", 0.0)) <= 0.0:
			_error("curses.%s: spawn debe ser > 0" % id)
		if float(def.get("coins", 0.0)) < 0.0:
			_error("curses.%s: coins no puede ser negativo" % id)
	_unique_keys("curses", ids)
	if not ids.has("ninguna"):
		_error("curses: falta la maldición por defecto 'ninguna'")


func _validate_achievements(achievements: Array) -> void:
	var ids: Array = []
	for item in achievements:
		if not item is Dictionary:
			_error("achievements: entrada no es objeto")
			continue
		var def: Dictionary = item
		var id := String(def.get("id", ""))
		ids.append(id)
		_need(def, ["name", "desc", "stat", "goal"], "achievements.%s" % id)
		var stat := String(def.get("stat", ""))
		if not ACHIEVEMENT_STATS.has(stat):
			_error("achievements.%s: stat '%s' inválido" % [id, stat])
		if float(def.get("goal", 0.0)) <= 0.0:
			_error("achievements.%s: goal debe ser > 0" % id)
	_unique_keys("achievements", ids)


func _validate_pools(pools: Variant, enemies: Dictionary, where: String) -> void:
	if not pools is Dictionary:
		_error("%s: pools no es objeto" % where)
		return
	if (pools as Dictionary).is_empty():
		_error("%s: pools vacío" % where)
	for eid in pools:
		if not enemies.has(String(eid)):
			_error("%s: enemigo '%s' no existe" % [where, String(eid)])


# --------------------------------------------------------------------- helpers --
func _biomes() -> Array:
	var wrapper := _dict(PATHS["biomes"])
	if wrapper.has("biomes") and wrapper["biomes"] is Array:
		return wrapper["biomes"]
	_error("biomes.json: falta la lista 'biomes'")
	return []


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_error("%s: no se pudo abrir" % path)
		return null
	var parser := JSON.new()
	var err := parser.parse(f.get_as_text())
	if err != OK:
		_error("%s:%d: JSON inválido: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data


func _dict(path: String) -> Dictionary:
	var data: Variant = _read_json(path)
	if data is Dictionary:
		return data
	if data != null:
		_error("%s: se esperaba un objeto JSON" % path)
	return {}


func _array(path: String) -> Array:
	var data: Variant = _read_json(path)
	if data is Array:
		return data
	if data != null:
		_error("%s: se esperaba una lista JSON" % path)
	return []


func _need(obj: Dictionary, keys: Array, where: String) -> void:
	for k in keys:
		if not obj.has(k):
			_error("%s: falta '%s'" % [where, String(k)])


func _unique_keys(label: String, keys: Array) -> void:
	var seen := {}
	for raw in keys:
		var id := String(raw)
		if id.is_empty():
			_error("%s: id vacío" % label)
		elif seen.has(id):
			_error("%s: id duplicado '%s'" % [label, id])
		else:
			seen[id] = true


func _error(msg: String) -> void:
	_errors.append(msg)


func _warn(msg: String) -> void:
	_warns.append(msg)
