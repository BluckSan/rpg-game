extends RefCounted
class_name ServerNav
## v0.9.2: навигация и описания логов для серверной симуляции врагов.
## Долина и Склеп: уровень строится один раз на сервере (без графики), с его коллизий печётся навмеш,
## снимаются логова (спавнеры) — клиенту больше не доверяем описания. Открытый мир: логова считаются
## тем же детерминированным кодом, навмеш — участок 120×120 м вокруг логова (по стволам и камням чанков),
## печётся в фоне при первом приближении игрока.

const AREA := 60.0
var zone_id := ""
var spawners := {}          # key -> def
var map := RID()            # общий навмеш зоны (долина, склеп)
var area_maps := {}         # открытый мир: key спавнера -> RID карты (или null — печётся)
var pillars: Array = []
var pillar_r := 1.4
var arena_center := Vector3.ZERO
var ok := false
var bake_ms := 0.0

static func spawner_def(zone_id: String, s) -> Dictionary:
	var pos: Vector3 = s.position if not s.is_inside_tree() else s.global_position
	var d := {"key": Net.wm_skey(zone_id, pos), "kind": s.kind, "lo": s.min_level, "hi": s.max_level, "n": s.count, "r": s.radius,
		"pos": Vector3(pos.x, 0, pos.z), "respawn": s.respawn_time, "kflag": s.kill_flag, "cflag": s.clear_flag, "rank": "normal", "rname": "", "elite": 0.0}
	if s is WorldSpawner:
		d.rank = s.rank; d.rname = s.rare_name; d.elite = s.elite_chance
	return d

func build(root: Node, zid: String) -> void:
	zone_id = zid
	var t0 := Time.get_ticks_msec()
	var stub = load("res://scripts/net/server_zone_stub.gd").new()
	stub.data = {"zone": zid, "zones": {}, "level": 1, "class": "warrior", "has_pos": true, "world": {}, "inventory": [], "equipped": []}
	root.add_child(stub)
	if zid == "global":
		var wb := WorldBuilder.new()
		wb.zone = stub
		wb.enemies_root = Node3D.new(); stub.add_child(wb.enemies_root)
		wb._world_spawners()
		for s in wb.spawners:
			var d := spawner_def(zid, s); spawners[d.key] = d
		wb.free()
	else:
		var b = DungeonBuilder.new() if zid == "dungeon" else StarterZoneBuilder.new()
		b.name = "World"
		stub.add_child(b)
		b.build(stub)
		for s in b.enemies_root.get_children():
			if s is Spawner:
				var d := spawner_def(zid, s); spawners[d.key] = d
		if b is DungeonBuilder:
			pillars = b.pillars.duplicate(); pillar_r = b.pillar_r; arena_center = b.arena_center
		var nm := NavigationMesh.new()
		nm.agent_radius = 0.6; nm.agent_height = 2.0; nm.agent_max_climb = 0.6; nm.agent_max_slope = 45.0
		nm.cell_size = 0.3; nm.cell_height = 0.25
		nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		nm.geometry_collision_mask = 1
		nm.filter_baking_aabb = AABB(Vector3(-30, -1, -8), Vector3(60, 8, 136)) if zid == "dungeon" else AABB(Vector3(-110, -2, -110), Vector3(220, 12, 220))
		var src := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(nm, src, b)
		NavigationServer3D.bake_from_source_geometry_data(nm, src)
		map = _make_map(nm)
		ok = nm.get_polygon_count() > 0
		print("server: навмеш «%s»: %d полигонов, логов %d" % [zid, nm.get_polygon_count(), spawners.size()])
	stub.free()
	bake_ms = Time.get_ticks_msec() - t0

static func _make_map(nm: NavigationMesh) -> RID:
	var m := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(m, nm.cell_size)
	NavigationServer3D.map_set_cell_height(m, nm.cell_height)
	NavigationServer3D.map_set_active(m, true)
	var r := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(r, m)
	NavigationServer3D.region_set_navigation_mesh(r, nm)
	return m

## Карта для логова (открытый мир — участок, печётся в фоне; пока нет — RID())
func map_for(key: String) -> RID:
	if zone_id != "global": return map
	var m = area_maps.get(key)
	if m is RID: return m
	if m == null and not area_maps.has(key):
		area_maps[key] = false
		_bake_area(key)
	return RID()

func _bake_area(key: String) -> void:
	var d: Dictionary = spawners.get(key, {})
	if d.is_empty(): return
	var c: Vector3 = d.pos
	var src := NavigationMeshSourceGeometryData3D.new()
	var x0 := c.x - AREA; var x1 := c.x + AREA; var z0 := c.z - AREA; var z1 := c.z + AREA
	src.add_faces(PackedVector3Array([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]), Transform3D.IDENTITY)
	var cs := WorldData.CHUNK
	var n_obs := 0
	for kx in range(floori(x0 / cs), floori(x1 / cs) + 1):
		for kz in range(floori(z0 / cs), floori(z1 / cs) + 1):
			var ch := WorldBuilder.gen_chunk(Vector2i(kx, kz), 0, -1)
			for s in ch.get("solid", []):
				var lp: Vector3 = s[0]; var rad := float(s[1])
				if rad < 0.25: continue
				var wp := Vector3(lp.x + kx * cs, 0, lp.z + kz * cs)
				if wp.x < x0 or wp.x > x1 or wp.z < z0 or wp.z > z1: continue
				var poly := PackedVector3Array()
				for i in 8:
					var a := i * TAU / 8.0
					poly.append(Vector3(wp.x + cos(a) * rad, 0, wp.z + sin(a) * rad))
				src.add_projected_obstruction(poly, -1.0, 4.0, true)
				n_obs += 1
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4; nm.agent_height = 2.0; nm.cell_size = 0.4; nm.cell_height = 0.25
	nm.filter_baking_aabb = AABB(Vector3(x0, -1, z0), Vector3(x1 - x0, 6, z1 - z0))
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func(): _area_done.call_deferred(key, nm, n_obs))

func _area_done(key: String, nm: NavigationMesh, n_obs: int) -> void:
	area_maps[key] = _make_map(nm)
	Net.nav_stats.areas += 1; Net.nav_stats.obstacles += n_obs

## Путь по навмешу (2D); пусто — идти напрямую
func path(key: String, from: Vector3, to: Vector3) -> PackedVector3Array:
	var m := map_for(key)
	if not m.is_valid(): return PackedVector3Array()
	if NavigationServer3D.map_get_iteration_id(m) == 0: return PackedVector3Array()
	return NavigationServer3D.map_get_path(m, from, to, true)

## Ближайшая проходимая точка (чтобы враг не застревал в стене)
func snap(key: String, p: Vector3) -> Vector3:
	var m := map_for(key)
	if not m.is_valid() or NavigationServer3D.map_get_iteration_id(m) == 0: return p
	var q := NavigationServer3D.map_get_closest_point(m, Vector3(p.x, p.y, p.z))
	if not q.is_finite(): return p
	q.y = 0.0
	return q if U.flat_dist(q, p) < 3.0 else p
