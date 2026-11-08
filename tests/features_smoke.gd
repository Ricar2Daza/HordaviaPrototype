extends SceneTree

var failed := false


func _initialize() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	await process_frame
	var content: Node = root.get_node("ContentDB")
	var game: Node = root.get_node("GameState")
	var save: Node = root.get_node("SaveManager")
	var contracts: Array = content.get("contracts")
	var relics: Array = content.get("relics")
	_check(contracts.size() == 4, "Se cargan los contratos")
	_check(relics.size() == 5, "Se cargan las reliquias")
	_check(content.call("validate").is_empty(), "El contenido pasa la validación")

	save.call("configure_telemetry", {"enabled": true, "max_entries": 10})
	for i in range(12):
		save.call("log_event", "smoke", {"index": i})
	var telemetry: Array = save.get("telemetry_events")
	_check(telemetry.size() == 10, "La telemetría respeta su límite")
	_check(int(telemetry[0]["payload"]["index"]) == 2, "La telemetría conserva los eventos recientes")
	save.call("configure_telemetry", {"enabled": false, "max_entries": 10})
	save.call("log_event", "disabled", {})
	_check(telemetry.size() == 10, "La telemetría desactivada no registra eventos")

	for contract in contracts:
		game.set("run_active", true)
		game.set("contract_id", String(contract["id"]))
		game.set("contract_progress", 0)
		game.set("contract_is_complete", false)
		game.set("coins", 0)
		var stat := String(contract["stat"])
		var goal := int(contract["goal"])
		game.call("update_contract_progress", stat, goal)
		_check(bool(game.get("contract_is_complete")), "Se completa el contrato %s" % contract["id"])
		_check(int(game.get("coins")) == int(contract["reward"]), "Se paga el contrato %s una vez" % contract["id"])
		game.call("update_contract_progress", stat, goal)
		_check(int(game.get("coins")) == int(contract["reward"]), "No se duplica la recompensa de %s" % contract["id"])

	game.set("run_active", true)
	game.set("contract_id", "")
	game.set("contract_is_complete", false)
	var owned_relics: Array = game.get("relic_ids")
	owned_relics.clear()
	game.set("dmg_mult", 1.0)
	game.set("max_hp", 100.0)
	game.set("hp", 100.0)
	game.call("apply_upgrade", {"id": "brasa_eterna", "effect": "relic"})
	_check(owned_relics.has("brasa_eterna"), "Se registra la reliquia")
	_check(is_equal_approx(float(game.get("dmg_mult")), 1.3), "Se aplica el beneficio de daño")
	_check(is_equal_approx(float(game.get("max_hp")), 80.0), "Se aplica la penalización de vida")
	game.call("apply_upgrade", {"id": "brasa_eterna", "effect": "relic"})
	_check(owned_relics.size() == 1, "La reliquia no se acumula")
	var choices: Array = content.call("roll_relics", 3)
	_check(choices.size() == 3, "Se ofrecen tres reliquias no obtenidas")
	for choice in choices:
		_check(String(choice["id"]) != "brasa_eterna", "No se ofrece una reliquia ya obtenida")

	game.set("run_active", false)
	print("FEATURES_SMOKE result=%s" % ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FEATURES_SMOKE: " + message)
