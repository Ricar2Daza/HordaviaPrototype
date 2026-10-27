## SaveManager — guardado portable con FileAccess (guía §3.6).
## Autoload. Guarda monedas meta y mejor tiempo; PlayerPrefs equivalentes.
extends Node

signal achievements_unlocked(list: Array)

const SAVE_PATH := "user://save.json"
const SAVE_BAK := "user://save.json.bak"

var total_coins := 0
var best_time := 0.0
var runs_played := 0
var total_kills := 0
var boss_kills := 0
var victories := 0
var coins_earned := 0
var settings := {}   # {"camera_mode": "fija"|"mouse"} — persistencia de opciones
var meta := {}       # niveles de tienda meta (roadmap 4.1)
var character := "vagabundo"  # personaje elegido (roadmap 4.2)
var achievements := {}  # id → true (roadmap 4.4)


func _ready() -> void:
	load_all()
	if OS.get_environment("HORDAVIA_SAVE_TEST") == "1":
		_atomic_self_test.call_deferred()


func register_run(coins: int, time: float, kills: int, victory: bool, bosses: int, persist := true) -> void:
	total_kills += kills
	boss_kills += bosses
	victories += 1 if victory else 0
	coins_earned += coins
	best_time = maxf(best_time, time)
	runs_played += 1
	if persist:
		total_coins += coins
	var new_ones := _unlock_check()
	if persist:
		save_all()
	if GameState.debug_auto_upgrade:
		var ids: Array[String] = []
		for a in new_ones:
			ids.append(String(a.get("id", "")))
		print("SMOKE_ACH kills=%d bosses=%d victories=%d new=%s" % [
			total_kills, boss_kills, victories, str(ids),
		])
	if not new_ones.is_empty():
		achievements_unlocked.emit(new_ones)


func _unlock_check() -> Array:
	var new_ones: Array = []
	for a in ContentDB.achievements:
		var id := String(a.get("id", ""))
		if id.is_empty() or bool(achievements.get(id, false)):
			continue
		var stat := String(a.get("stat", ""))
		var goal := float(a.get("goal", 1))
		var v := 0.0
		match stat:
			"total_kills": v = float(total_kills)
			"boss_kills": v = float(boss_kills)
			"victories": v = float(victories)
			"runs_played": v = float(runs_played)
			"best_time": v = best_time
			"coins_earned": v = float(coins_earned)
		if v >= goal:
			achievements[id] = true
			new_ones.append(a)
	return new_ones


func load_all() -> void:
	var data := _read_save(SAVE_PATH)
	if data.is_empty():
		data = _read_save(SAVE_BAK)
		if not data.is_empty():
			push_warning("SaveManager: save principal ilegible; usando copia .bak")
	if data.is_empty():
		return
	total_coins = int(data.get("total_coins", 0))
	best_time = float(data.get("best_time", 0.0))
	runs_played = int(data.get("runs_played", 0))
	total_kills = int(data.get("total_kills", 0))
	boss_kills = int(data.get("boss_kills", 0))
	victories = int(data.get("victories", 0))
	coins_earned = int(data.get("coins_earned", 0))
	settings = data.get("settings", {}) if data.get("settings", {}) is Dictionary else {}
	meta = data.get("meta", {}) if data.get("meta", {}) is Dictionary else {}
	achievements = data.get("achievements", {}) if data.get("achievements", {}) is Dictionary else {}
	var c := String(data.get("character", "vagabundo"))
	if ContentDB.characters.has(c):
		character = c


func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	# Un archivo truncado a NUL/solo espacios no debe ni intentar parsearse.
	if txt.length() < 8 or txt.unicode_at(0) == 0:
		return {}
	var data = JSON.parse_string(txt)
	return data if data is Dictionary else {}


func save_all() -> void:
	var d := {
		"version": 3,
		"total_coins": total_coins,
		"best_time": best_time,
		"runs_played": runs_played,
		"total_kills": total_kills,
		"boss_kills": boss_kills,
		"victories": victories,
		"coins_earned": coins_earned,
		"settings": settings,
		"meta": meta,
		"character": character,
		"achievements": achievements,
	}
	_write_atomic(SAVE_PATH, SAVE_BAK, JSON.stringify(d, "\t"))


## Escritura atómica dentro de user://: tmp -> rename, con copia .bak del save válido.
## Evita que un cierre forzado deje el JSON truncado a ceros (bug observado).
func _write_atomic(path: String, bak_path: String, text: String) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("SaveManager: no se pudo abrir user://")
		return
	var fname := path.get_file()
	var bname := bak_path.get_file()
	var tmp_name := fname + ".tmp"
	var f := FileAccess.open("user://" + tmp_name, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: no se pudo escribir %s" % tmp_name)
		return
	f.store_string(text)
	f.flush()
	f.close()
	f = null
	if not _read_save(path).is_empty():
		# Copia manual: DirAccess.copy() resolvía mal rutas user:// recién creadas.
		var prev := FileAccess.get_file_as_bytes(path)
		if not prev.is_empty():
			var bf := FileAccess.open(bak_path, FileAccess.WRITE)
			if bf != null:
				bf.store_buffer(prev)
				bf.flush()
				bf.close()
			else:
				push_warning("SaveManager: no se pudo crear %s" % bname)
	if dir.file_exists(fname):
		dir.remove(fname)
	var err := dir.rename(tmp_name, fname)
	if err != OK:
		push_error("SaveManager: rename falló (%d); queda %s" % [err, tmp_name])


func _atomic_self_test() -> void:
	## QA opcional: HORDAVIA_SAVE_TEST=1 valida escritura + .bak + limpieza de tmp.
	var t := "user://save_test.json"
	var b := "user://save_test.json.bak"
	_write_atomic(t, b, "{\"v\":111}")
	var ok1 := not _read_save(t).is_empty()
	_write_atomic(t, b, "{\"v\":222}")
	var bak_txt := FileAccess.get_file_as_string(b)
	var ok2 := bak_txt.contains("\"v\":111")
	var ok3 := not FileAccess.file_exists("user://save_test.json.tmp")
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("save_test.json")
		dir.remove("save_test.json.bak")
	print("SAVE_TEST write=%s bak=%s clean=%s" % [str(ok1), str(ok2), str(ok3)])
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


func save_settings(patch: Dictionary) -> void:
	for k in patch:
		settings[k] = patch[k]
	save_all()
