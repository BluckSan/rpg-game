extends Node
## v0.9.4.2: цветная подложка мини-карты — assets/world/minimap.png, 1024×1024 (1 пиксель = 2 м).
## Плоские различимые цвета: зоны (цвет биома из WorldData), рельеф — лёгкая отмывка, вода — яркая синяя,
## дороги — светлый песок с тёмной обочиной, города и лагеря — каменные круги. Всё — из тех же данных, что строит игра.
## godot --headless --path . res://tools/bake_minimap.tscn
const S := 1024
const WATER := Color(0.2, 0.5, 0.85)
const ROAD := Color(0.96, 0.84, 0.55)
const ROAD_EDGE := Color(0.28, 0.2, 0.12)
const TOWN := Color(0.78, 0.7, 0.6)
const CAMP := Color(0.72, 0.52, 0.32)

func _ready() -> void:
	await get_tree().process_frame
	WorldData.init()
	var t0 := Time.get_ticks_msec()
	var step := WorldData.HALF * 2 / S
	var hs := PackedFloat32Array(); hs.resize(S * S)
	for y in S:
		for x in S:
			hs[y * S + x] = WorldData.height(-WorldData.HALF + (x + 0.5) * step, -WorldData.HALF + (y + 0.5) * step)
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.6, 0.75, -0.45).normalized()
	for y in S:
		for x in S:
			var wx := -WorldData.HALF + (x + 0.5) * step; var wz := -WorldData.HALF + (y + 0.5) * step
			var h := hs[y * S + x]
			var hl := hs[y * S + maxi(x - 1, 0)]; var hr := hs[y * S + mini(x + 1, S - 1)]
			var hd := hs[maxi(y - 1, 0) * S + x]; var hu := hs[mini(y + 1, S - 1) * S + x]
			var n := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			var w := WorldData.biome_weights(wx, wz)
			var c := Color(0, 0, 0)
			var tot := 0.0
			for q in w.size():
				c += (WorldData.BIOMES[q].color as Color) * w[q]; tot += w[q]
			if tot > 0: c = c / tot
			c = c * clampf(0.55 + n.dot(light) * 0.55, 0.6, 1.2)
			if w[3] > 0.45 and h < -0.25: c = WATER.darkened(clampf((-0.25 - h) / 2.0, 0, 0.35))
			var e := maxf(absf(wx), absf(wz))
			if e > WorldData.EDGE: c = c.lerp(Color(0.3, 0.28, 0.27), clampf((e - WorldData.EDGE) / 40.0, 0, 1))
			c.a = 1
			img.set_pixel(x, y, c)
	for t in WorldData.TOWNS:
		var px: Vector2 = ((t.pos as Vector2) + Vector2.ONE * WorldData.HALF) / step
		_disc(img, px, WorldData.TOWN_R / step + 1.0, Color(0.15, 0.12, 0.1), 1.0)
		_disc(img, px, WorldData.TOWN_R / step, TOWN if t.kind == "town" else CAMP, 1.0)
	for sg in WorldData._roads:
		_line(img, (sg[0] + Vector2.ONE * WorldData.HALF) / step, (sg[1] + Vector2.ONE * WorldData.HALF) / step, 4.2, ROAD_EDGE, 0.9)
	for sg in WorldData._roads:
		_line(img, (sg[0] + Vector2.ONE * WorldData.HALF) / step, (sg[1] + Vector2.ONE * WorldData.HALF) / step, 2.4, ROAD, 1.0)
	img.save_png(ProjectSettings.globalize_path("res://assets/world/minimap.png"))
	print("minimap baked ", Time.get_ticks_msec() - t0, " ms")
	get_tree().quit()

func _disc(img: Image, c: Vector2, r: float, col: Color, a: float) -> void:
	for y in range(int(c.y - r - 1), int(c.y + r + 2)):
		for x in range(int(c.x - r - 1), int(c.x + r + 2)):
			if x < 0 or y < 0 or x >= S or y >= S: continue
			var k := clampf(r - Vector2(x + 0.5, y + 0.5).distance_to(c) + 0.5, 0, 1) * a
			if k > 0: img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, k))

func _line(img: Image, a: Vector2, b: Vector2, w: float, col: Color, al: float) -> void:
	var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (w + 1)
	var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (w + 1)
	var ab := b - a
	for y in range(maxi(0, int(mn.y)), mini(S, int(mx.y) + 1)):
		for x in range(maxi(0, int(mn.x)), mini(S, int(mx.x) + 1)):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0, 1)
			var k := clampf(w * 0.5 - p.distance_to(a + ab * t) + 0.5, 0, 1) * al
			if k > 0: img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, k))
