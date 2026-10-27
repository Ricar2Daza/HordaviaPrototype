## WeaponInstance — armas automáticas data-driven (guía §3.4 / roadmap 2.1).
## Arquetipos: nearest (auto-aim), orbit, aura, boomerang, mine, chain.
## Todos leen su definición de ContentDB.weapons (data/weapons.json).
extends Node3D

var weapon_id := ""
var _t := 0.0
var _hit_cd := {}   # instance_id del enemigo -> cooldown restante (para daño persistente)

# --- estado por arquetipo ---
var _blades: Array[Node3D] = []
var _blade_angle := 0.0
var _aura_ring: MeshInstance3D = null
var _mines: Array = []      # {node, pos, t}
var _booms: Array = []      # {node, dir, t, returning}
var _chain_lines: Array[MeshInstance3D] = []
var _chain_life := 0.0
var _spiral_angle := 0.0
var _shocks: Array = []     # {node, t, radius}
var _meteors: Array = []    # {node, marker, target, t, delay, radius, dmg}
var _drones: Array[Node3D] = []
var _drone_angle := 0.0
var _voids: Array = []      # {node, pos, t, duration, radius, dmg, ticks}


## Escalado por nivel de arma (roadmap 2.6): +12 % daño y -6 % intervalo por nivel.
func _wlvl() -> int:
	return int(GameState.weapon_levels.get(weapon_id, 1))


func _wdmg(def: Dictionary, key: String = "dmg", fallback: float = 6.0) -> float:
	var lvl_bonus := 1.0 + 0.12 * float(_wlvl() - 1)
	return float(def.get(key, fallback)) * lvl_bonus * GameState.dmg_mult


func _winterval(def: Dictionary, key: String = "interval", fallback: float = 1.0) -> float:
	var lvl_bonus := 1.0 - 0.06 * float(_wlvl() - 1)
	return maxf(float(def.get(key, fallback)) * lvl_bonus / GameState.fire_mult, 0.05)


func setup(id: String) -> void:
	weapon_id = id


func _ready() -> void:
	var def: Dictionary = ContentDB.weapons.get(weapon_id, {})
	match String(def.get("pattern", "")):
		"orbit":
			_spawn_blades(int(def.get("blades", 2)))
		"aura":
			var col_arr: Array = def.get("color", [0.9, 0.4, 1.0]) if def.get("color", []) is Array else [0.9, 0.4, 1.0]
			_aura_ring = _make_ring(
				float(def.get("radius", 3.0)),
				Color(float(col_arr[0]), float(col_arr[1]), float(col_arr[2]))
			)
		"boomerang":
			pass
		"mine":
			pass
		"chain":
			_make_chain_lines(6)
		"drone":
			_spawn_drones(int(def.get("drones", 1)))
		"slam", "meteor", "void":
			pass


func _physics_process(dt: float) -> void:
	if not GameState.run_active:
		return
	var def: Dictionary = ContentDB.weapons.get(weapon_id, {})
	if def.is_empty():
		return
	match String(def.get("pattern", "")):
		"nearest":
			_fire_nearest(def, dt)
		"orbit":
			_tick_orbit(def, dt)
		"aura":
			_tick_aura(def, dt)
		"boomerang":
			_tick_boomerang(def, dt)
		"mine":
			_tick_mine(def, dt)
		"chain":
			_tick_chain(def, dt)
		"spiral":
			_tick_spiral(def, dt)
		"slam":
			_tick_slam(def, dt)
		"meteor":
			_tick_meteor(def, dt)
		"drone":
			_tick_drone(def, dt)
		"void":
			_tick_void(def, dt)
	for key in _hit_cd.keys():
		_hit_cd[key] = maxf(float(_hit_cd[key]) - dt, 0.0)
	# limpieza barata de cooldowns muertos
	if Engine.get_physics_frames() % 60 == 0:
		for key in _hit_cd.keys():
			if float(_hit_cd[key]) <= 0.0:
				_hit_cd.erase(key)


# =============== aimed (auto-aim con predicción) ===============

func _fire_nearest(def: Dictionary, dt: float) -> void:
	_t += dt
	var interval := _winterval(def, "interval", 1.0)
	if _t < interval:
		return
	_t = 0.0
	var dmg := _wdmg(def, "dmg", 6.0)
	var speed := float(def.get("speed", 14.0)) * GameState.proj_speed_mult
	var life := float(def.get("life", 2.0))
	var pierce := int(def.get("pierce", 0))
	var targets := 1 + GameState.extra_proj
	var fired := 0
	for shot in targets:
		var aim = EnemyManager.nearest(global_position, 22.0)
		if aim == null:
			break
		var spread := (float(fired) - (targets - 1) * 0.5) * 0.08
		var dir3 := Vector3(aim.position.x - global_position.x, 0.0, aim.position.z - global_position.z)
		if dir3.length() < 0.01:
			continue
		dir3 = dir3.normalized()
		var flight_t: float = dir3.length() / maxf(speed, 0.1)
		var target_vel: Vector3 = Vector3.ZERO
		if aim.position.distance_to(global_position) > 0.01:
			target_vel = (global_position - aim.position).normalized() * aim.speed
		var predicted: Vector3 = aim.position + target_vel * flight_t - global_position
		if predicted.length() > 0.01:
			dir3 = Vector3(predicted.x, 0.0, predicted.z).normalized()
		var dir := Basis(Vector3.UP, spread) * dir3
		BulletSwarm.spawn(global_position + Vector3(0, 0.9, 0), dir, speed, dmg, life, pierce)
		AudioManager.play_sfx("shoot", randf_range(0.92, 1.08))
		fired += 1


# =============== orbit (cuchillas meridianas) ===============

func _spawn_blades(n: int) -> void:
	for i in n:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5, 0.12, 0.16)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.75, 0.9, 1.0)
		mesh.material = mat
		mi.mesh = mesh
		mi.position.y = 0.9
		add_child(mi)
		_blades.append(mi)


func _tick_orbit(def: Dictionary, dt: float) -> void:
	var ticks := float(def.get("ticks", 0.15))
	_blade_angle += dt * 2.6
	var radius := float(def.get("radius", 2.2)) * GameState.area_mult
	var dmg := _wdmg(def, "dmg", 5.0)
	for i in _blades.size():
		var a := _blade_angle + TAU * float(i) / float(_blades.size())
		var offset := Vector3(cos(a), 0.0, sin(a)) * radius
		_blades[i].position = offset
		var probe := global_position + offset
		var hit = EnemyManager.nearest(probe, 0.8)
		if hit != null:
			var id: int = hit.get_instance_id()
			if float(_hit_cd.get(id, 0.0)) <= 0.0:
				_hit_cd[id] = ticks
				EnemyManager.damage(hit, dmg)


# =============== aura (anillo de daño continuo) ===============

func _make_ring(radius: float, color: Color = Color(0.9, 0.4, 1.0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.06
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.16)
	cyl.material = mat
	mi.mesh = cyl
	mi.position.y = 0.06
	add_child(mi)
	return mi


func _tick_aura(def: Dictionary, dt: float) -> void:
	var radius := float(def.get("radius", 3.0)) * GameState.area_mult
	_t += dt
	var pulse := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.008)
	if _aura_ring != null:
		_aura_ring.scale = Vector3(pulse * GameState.area_mult, 1.0, pulse * GameState.area_mult)
	var ticks := float(def.get("ticks", 0.5))
	if _t < ticks:
		return
	_t = 0.0
	var dmg := _wdmg(def, "dmg", 4.0)
	for e in EnemyManager.enemies_in_radius(global_position, radius):
		EnemyManager.damage(e, dmg)
		if def.has("slow"):
			e.slow_t = float(def.get("slow_t", 1.0))
			e.slow_mult = float(def.get("slow", 0.6))


# =============== boomerang (disco que va y vuelve) ===============

func _tick_boomerang(def: Dictionary, dt: float) -> void:
	var interval := _winterval(def, "interval", 2.4)
	_t += dt
	if _t >= interval:
		_t = 0.0
		var aim = EnemyManager.nearest(global_position, 24.0)
		if aim != null:
			var discs := int(def.get("discs", 1))
			for d in discs:
				var mi := MeshInstance3D.new()
				var mesh := BoxMesh.new()
				mesh.size = Vector3(0.5, 0.1, 0.14)
				var mat := StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.albedo_color = Color(0.5, 1.0, 0.95)
				mesh.material = mat
				mi.mesh = mesh
				mi.top_level = true
				add_child(mi)
				mi.global_position = global_position + Vector3(0.0, 1.0, 0.0)
				var dir3 := Vector3(aim.position.x - global_position.x, 0.0, aim.position.z - global_position.z)
				if dir3.length() < 0.01:
					var fwd: float = EnemyManager.player.rotation.y if EnemyManager.player != null else 0.0
					dir3 = Vector3(sin(fwd), 0.0, cos(fwd)).normalized()
				var spread := (float(d) - (float(discs) - 1.0) * 0.5) * 0.25
				_booms.append({
					"node": mi,
					"dir": Basis(Vector3.UP, spread) * dir3.normalized(),
					"t": 0.0,
					"returning": false,
				})
			AudioManager.play_sfx("shoot", 0.75)

	var speed := float(def.get("speed", 12.0)) * GameState.proj_speed_mult
	var range_dist := float(def.get("range", 8.0))
	var dmg := _wdmg(def, "dmg", 10.0)
	var done: Array = []
	for b in _booms:
		var node: MeshInstance3D = b["node"]
		var dir: Vector3 = b["dir"]
		node.rotation.y += 14.0 * dt
		if not bool(b["returning"]):
			node.global_position += dir * speed * dt
			b["t"] = float(b["t"]) + dt
			if float(b["t"]) * speed >= range_dist:
				b["returning"] = true
		else:
			var home: Vector3 = global_position + Vector3(0.0, 1.0, 0.0)
			if EnemyManager.player != null:
				home = EnemyManager.player.global_position + Vector3(0.0, 1.0, 0.0)
			var to_home := home - node.global_position
			if to_home.length() < 0.7:
				done.append(b)
				continue
			node.global_position += to_home.normalized() * speed * dt
		# daño por solape con cooldown por enemigo (puede pegar de ida y de vuelta)
		for e in EnemyManager.enemies_in_radius(node.global_position, 0.8):
			var id: int = e.get_instance_id()
			if float(_hit_cd.get(id, 0.0)) <= 0.0:
				_hit_cd[id] = 0.35
				EnemyManager.damage(e, dmg)
	for b in done:
		(b["node"] as MeshInstance3D).queue_free()
		_booms.erase(b)


# =============== mine (cargas de proximidad) ===============

func _tick_mine(def: Dictionary, dt: float) -> void:
	var interval := _winterval(def, "interval", 3.0)
	var cap := int(def.get("capacity", 3))
	_t += dt
	if _t >= interval and _mines.size() < cap:
		_t = 0.0
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.18
		mesh.height = 0.36
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.6, 0.2)
		mesh.material = mat
		mi.mesh = mesh
		mi.top_level = true
		var center: Vector3 = EnemyManager.player.global_position if EnemyManager.player != null else global_position
		var mpos := center + Vector3(randf_range(-1.2, 1.2), 0.25, randf_range(-1.2, 1.2))
		add_child(mi)
		mi.global_position = mpos
		_mines.append({"node": mi, "pos": mpos, "t": 0.0})

	var trigger := float(def.get("radius", 1.7)) * GameState.area_mult
	var dmg := _wdmg(def, "dmg", 18.0)
	var exploded: Array = []
	for m in _mines:
		m["t"] = float(m["t"]) + dt
		var node: MeshInstance3D = m["node"]
		node.rotation.y += 3.0 * dt
		var armed := float(m["t"]) > 0.45
		node.scale = Vector3.ONE * (1.0 + 0.15 * sin(float(m["t"]) * 6.0)) if armed else Vector3.ONE * 0.6
		if not armed:
			continue
		var near_hits := EnemyManager.enemies_in_radius(m["pos"], trigger)
		if not near_hits.is_empty():
			for e in near_hits:
				EnemyManager.damage(e, dmg)
			DeathFx.spawn(node.global_position, Color(1.0, 0.55, 0.2), true)
			AudioManager.play_sfx("boom")
			exploded.append(m)
	for m in exploded:
		(m["node"] as MeshInstance3D).queue_free()
		_mines.erase(m)


# =============== spiral (abanico giratorio) ===============

func _tick_spiral(def: Dictionary, dt: float) -> void:
	_t += dt
	var interval := _winterval(def, "interval", 0.34)
	if _t < interval:
		return
	_t = 0.0
	var shots := int(def.get("shots", 3))
	var dmg := _wdmg(def, "dmg", 7.0)
	var speed := float(def.get("speed", 14.0)) * GameState.proj_speed_mult
	var life := float(def.get("life", 1.9))
	_spiral_angle += float(def.get("spin", 0.55))
	for i in shots:
		var a := _spiral_angle + TAU * float(i) / float(maxi(shots, 1))
		BulletSwarm.spawn(
			global_position + Vector3(0.0, 0.9, 0.0),
			Vector3(cos(a), 0.0, sin(a)), speed, dmg, life, 0
		)
	AudioManager.play_sfx("shoot", randf_range(1.1, 1.25))


# =============== slam (mazo sísmico) ===============

func _tick_slam(def: Dictionary, dt: float) -> void:
	_t += dt
	var done: Array = []
	for s in _shocks:
		var node: MeshInstance3D = s.get("node")
		if not is_instance_valid(node):
			done.append(s)
			continue
		s["t"] = float(s["t"]) + dt
		var k: float = clampf(float(s["t"]) / 0.5, 0.0, 1.0)
		var sc: float = lerpf(0.6, float(s["radius"]), k)
		node.scale = Vector3(sc, 1.0, sc)
		var mat := (node.mesh as CylinderMesh).material as StandardMaterial3D
		mat.albedo_color.a = 0.45 * (1.0 - k)
		if k >= 1.0:
			done.append(s)
			node.queue_free()
	for s in done:
		_shocks.erase(s)
	var interval := _winterval(def, "interval", 2.7)
	if _t < interval:
		return
	_t = 0.0
	var radius := float(def.get("radius", 3.8)) * GameState.area_mult
	var hit = EnemyManager.nearest(global_position, radius + 1.5)
	var center: Vector3 = global_position
	if hit != null:
		center = hit.position
	var dmg := _wdmg(def, "dmg", 24.0)
	for e in EnemyManager.enemies_in_radius(center, radius):
		EnemyManager.damage(e, dmg)
	_spawn_shock(center, radius, Color(1.0, 0.58, 0.18))
	AudioManager.play_sfx("boom", 0.55)


func _spawn_shock(pos: Vector3, radius: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.08
	cyl.radial_segments = 24
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.45)
	cyl.material = mat
	mi.mesh = cyl
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(pos.x, pos.y + 0.09, pos.z)
	mi.scale = Vector3(0.6, 1.0, 0.6)
	_shocks.append({"node": mi, "t": 0.0, "radius": radius})


# =============== meteor (caída orbital) ===============

func _tick_meteor(def: Dictionary, dt: float) -> void:
	var done: Array = []
	for m in _meteors:
		var node: MeshInstance3D = m.get("node")
		var marker: MeshInstance3D = m.get("marker")
		if not is_instance_valid(node):
			done.append(m)
			continue
		m["t"] = float(m["t"]) + dt
		var delay := maxf(float(m["delay"]), 0.05)
		var k: float = clampf(float(m["t"]) / delay, 0.0, 1.0)
		var target: Vector3 = m["target"]
		node.global_position.y = lerpf(float(m["start_y"]), target.y + 0.55, k)
		if is_instance_valid(marker):
			var mm := (marker.mesh as CylinderMesh).material as StandardMaterial3D
			mm.albedo_color.a = 0.18 + 0.42 * k
			marker.scale = Vector3.ONE * (0.55 + 0.45 * k)
		if k >= 1.0:
			var radius := float(m["radius"])
			for e in EnemyManager.enemies_in_radius(target, radius):
				EnemyManager.damage(e, float(m["dmg"]))
			_spawn_shock(target, radius, Color(1.0, 0.45, 0.12))
			DeathFx.spawn(target, Color(1.0, 0.45, 0.12), true)
			AudioManager.play_sfx("boom", 0.7)
			node.queue_free()
			if is_instance_valid(marker):
				marker.queue_free()
			done.append(m)
	for m in done:
		_meteors.erase(m)
	var interval := _winterval(def, "interval", 3.3)
	_t += dt
	if _t < interval:
		return
	_t = 0.0
	var aim = EnemyManager.nearest(global_position, 27.0)
	if aim == null:
		return
	var count := int(def.get("count", 1))
	var dmg := _wdmg(def, "dmg", 30.0)
	var radius := float(def.get("radius", 3.2)) * GameState.area_mult
	var delay := float(def.get("delay", 0.72))
	for i in count:
		var target: Vector3 = aim.position
		if count > 1:
			target += Vector3(randf_range(-2.6, 2.6), 0.0, randf_range(-2.6, 2.6))
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.55
		sph.height = 1.1
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.albedo_color = Color(1.0, 0.45, 0.12)
		fmat.emission_enabled = true
		fmat.emission = Color(1.0, 0.3, 0.05)
		fmat.emission_energy_multiplier = 1.6
		sph.material = fmat
		mi.mesh = sph
		mi.top_level = true
		add_child(mi)
		mi.global_position = Vector3(target.x, target.y + 14.0, target.z)
		var marker := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = radius
		disc.bottom_radius = radius
		disc.height = 0.06
		var mmat := StandardMaterial3D.new()
		mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mmat.albedo_color = Color(1.0, 0.25, 0.08, 0.18)
		disc.material = mmat
		marker.mesh = disc
		marker.top_level = true
		add_child(marker)
		marker.global_position = Vector3(target.x, target.y + 0.06, target.z)
		_meteors.append({
			"node": mi, "marker": marker, "target": target, "t": 0.0,
			"delay": delay, "radius": radius, "dmg": dmg, "start_y": target.y + 14.0,
		})
	AudioManager.play_sfx("dash", 0.55)


# =============== drone (compañero orbital) ===============

func _spawn_drones(n: int) -> void:
	for i in n:
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.44
		mesh.radial_segments = 8
		mesh.rings = 4
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.35, 1.0, 0.95)
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.8, 0.75)
		mat.emission_energy_multiplier = 1.2
		mesh.material = mat
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_drones.append(mi)


func _tick_drone(def: Dictionary, dt: float) -> void:
	_drone_angle += dt * 2.0
	var n := maxi(_drones.size(), 1)
	for i in _drones.size():
		var a := _drone_angle + TAU * float(i) / float(n)
		_drones[i].position = Vector3(cos(a) * 1.8, 1.15 + sin(a * 2.0) * 0.12, sin(a) * 1.8)
	var interval := _winterval(def, "interval", 0.72)
	_t += dt
	if _t < interval:
		return
	_t = 0.0
	var dmg := _wdmg(def, "dmg", 8.0)
	var speed := float(def.get("speed", 17.0)) * GameState.proj_speed_mult
	var life := float(def.get("life", 1.8))
	for d in _drones:
		var aim = EnemyManager.nearest(d.global_position, 19.0)
		if aim == null:
			continue
		var dir := Vector3(aim.position.x - d.global_position.x, 0.0, aim.position.z - d.global_position.z)
		if dir.length() < 0.01:
			continue
		BulletSwarm.spawn(d.global_position, dir.normalized(), speed, dmg, life, 0)
	if not _drones.is_empty():
		AudioManager.play_sfx("shoot", 1.15)


# =============== void (singularidad) ===============

func _tick_void(def: Dictionary, dt: float) -> void:
	var done: Array = []
	for v in _voids:
		var node: MeshInstance3D = v.get("node")
		if not is_instance_valid(node):
			done.append(v)
			continue
		v["t"] = float(v["t"]) + dt
		var radius := float(v["radius"])
		var center: Vector3 = v["pos"]
		node.scale = Vector3.ONE * (1.0 + 0.15 * sin(float(v["t"]) * 8.0))
		node.rotation.y += dt * 2.5
		for e in EnemyManager.enemies_in_radius(center, radius):
			var to: Vector3 = center - e.position
			to.y = 0.0
			var d: float = to.length()
			if d > 0.2:
				e.position += (to / d) * minf(d, 4.5) * dt * 2.2
			var id: int = e.get_instance_id()
			if float(_hit_cd.get(id, 0.0)) <= 0.0:
				_hit_cd[id] = float(v.get("ticks", 0.45))
				EnemyManager.damage(e, float(v["dmg"]))
		if float(v["t"]) >= float(v["duration"]):
			DeathFx.spawn(center, Color(0.55, 0.25, 0.95), true)
			node.queue_free()
			done.append(v)
	for v in done:
		_voids.erase(v)
	var interval := _winterval(def, "interval", 6.0)
	_t += dt
	if _t < interval:
		return
	_t = 0.0
	var aim = EnemyManager.nearest(global_position, 26.0)
	var center: Vector3 = global_position
	if aim != null:
		center = aim.position
	else:
		center = global_position + Vector3(0.0, 0.0, -3.0)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.55
	mesh.height = 1.1
	mesh.radial_segments = 10
	mesh.rings = 5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.22, 0.06, 0.42, 0.82)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.05, 0.8)
	mat.emission_energy_multiplier = 1.4
	mesh.material = mat
	mi.mesh = mesh
	mi.top_level = true
	add_child(mi)
	mi.global_position = center + Vector3(0.0, 1.0, 0.0)
	_voids.append({
		"node": mi, "pos": center, "t": 0.0,
		"duration": float(def.get("duration", 2.5)),
		"radius": float(def.get("radius", 4.2)) * GameState.area_mult,
		"dmg": _wdmg(def, "dmg", 10.0),
		"ticks": float(def.get("ticks", 0.45)),
	})
	AudioManager.play_sfx("zap", 0.65)


# =============== chain (rayo que salta entre enemigos) ===============

func _make_chain_lines(n: int) -> void:
	for i in n:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.07, 0.07, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.85, 0.95, 1.0)
		mesh.material = mat
		mi.mesh = mesh
		mi.top_level = true
		mi.visible = false
		add_child(mi)
		_chain_lines.append(mi)


func _tick_chain(def: Dictionary, dt: float) -> void:
	_chain_life = maxf(_chain_life - dt, 0.0)
	if _chain_life <= 0.0:
		for l in _chain_lines:
			l.visible = false
	_t += dt
	var interval := _winterval(def, "interval", 2.0)
	if _t < interval:
		return
	_t = 0.0
	var jumps := int(def.get("jumps", 3))
	var jump_radius := float(def.get("jump_radius", 6.5)) * GameState.area_mult
	var dmg := _wdmg(def, "dmg", 9.0)
	var struck := {}
	var first = EnemyManager.nearest(global_position, 18.0)
	if first == null:
		return
	AudioManager.play_sfx("zap", randf_range(0.95, 1.1))
	var points := []
	var prev := global_position + Vector3(0.0, 1.0, 0.0)
	var cur = first
	for j in jumps:
		if cur == null:
			break
		var cpos: Vector3 = Vector3(cur.position.x, 1.0, cur.position.z)
		points.append([prev, cpos])
		prev = cpos
		EnemyManager.damage(cur, dmg)
		struck[cur.get_instance_id()] = true
		cur = EnemyManager.nearest(cpos, jump_radius, struck)
	_chain_flash(0.12, points)


## Dibujar los segmentos del rayo por un instante.
func _chain_flash(life: float, points: Array) -> void:
	_chain_life = life
	for i in _chain_lines.size():
		var l := _chain_lines[i]
		if i >= points.size():
			l.visible = false
			continue
		var seg = points[i]
		var p0: Vector3 = seg[0]
		var p1: Vector3 = seg[1]
		var mid := (p0 + p1) * 0.5
		var len := (p1 - p0).length()
		l.visible = len > 0.05
		l.global_position = mid
		l.rotation = Vector3.ZERO
		l.look_at(p1, Vector3.UP)
		l.scale = Vector3(1.0, 1.0, len)
