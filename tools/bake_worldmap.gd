extends Node
## Подробная карта мира (v0.5.1): assets/world/worldmap.png, 2048×2048 (1 пиксель ≈ 1 м).
## Цвет — настоящие слои ландшафта (как в игре), рельеф — отмывка по высотам с северо-запада + горизонтали каждые 8 м,
## вода, дороги с обочиной, границы зон, деревья и камни — по тем же чанкам, что строит игра (кроны, валуны).
## godot --headless --path . res://tools/bake_worldmap.tscn
const S := 2048

func _ready() -> void:
	await get_tree().process_frame
	WorldData.init()
	var t0 := Time.get_ticks_msec()
	var step := WorldData.HALF * 2 / S
	var hs := PackedFloat32Array(); hs.resize(S * S)
	for y in S:
		for x in S:
			var wx := -WorldData.HALF + (x + 0.5) * step; var wz := -WorldData.HALF + (y + 0.5) * step
			hs[y * S + x] = WorldData.height(wx, wz)
	print("heights ", Time.get_ticks_msec() - t0, " ms")
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.6, 0.75, -0.45).normalized()
	var biome := PackedByteArray(); biome.resize(S * S)
	var segs = null
	for y in S:
		for x in S:
			var i := y * S + x
			var wx := -WorldData.HALF + (x + 0.5) * step; var wz := -WorldData.HALF + (y + 0.5) * step
			var h := hs[i]
			var hl := hs[y * S + maxi(x - 1, 0)]; var hr := hs[y * S + mini(x + 1, S - 1)]
			var hd := hs[maxi(y - 1, 0) * S + x]; var hu := hs[mini(y + 1, S - 1) * S + x]
			var n := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			var w := WorldData.biome_weights(wx, wz)
			var bi := 0
			for q in w.size(): if w[q] > w[bi]: bi = q
			biome[i] = bi
			var lw := WorldData.layer_weights(wx, wz, 1.0 - n.y, w, segs)
			var c := Color(0, 0, 0)
			for q in 7: c += WorldData.LAYER_AVG[q] * lw[q]
			c = c * lw[7]
			# отмывка рельефа + лёгкая высотная тонировка
			var shade := clampf(0.35 + n.dot(light) * 0.85, 0.4, 1.3)
			c = c * shade
			# горизонтали
			var hb := floorf(h / 8.0)
			if floorf(hl / 8.0) != hb or floorf(hd / 8.0) != hb: c = c.darkened(0.12)
			# вода топей/озёр
			if w[3] > 0.45 and h < -0.25:
				var dep := clampf((-0.25 - h) / 1.2, 0, 1)
				c = Color(0.30, 0.42, 0.40).lerp(Color(0.14, 0.24, 0.26), dep)
				if h > -0.45: c = c.lerp(Color(0.75, 0.8, 0.72), 0.35)   # кромка
			var e := maxf(absf(wx), absf(wz))
			if e > WorldData.EDGE: c = c.lerp(Color(0.33, 0.30, 0.29), clampf((e - WorldData.EDGE) / 50.0, 0, 1))
			c.a = 1
			img.set_pixel(x, y, c)
	print("colors ", Time.get_ticks_msec() - t0, " ms")
	# границы зон: пунктир
	for y in range(1, S - 1):
		for x in range(1, S - 1):
			var i := y * S + x
			if biome[i] != biome[i + 1] or biome[i] != biome[i + S]:
				if ((x + y) / 6) % 2 == 0:
					img.set_pixel(x, y, Color(0.12, 0.09, 0.07))
					img.set_pixel(x + 1, y, Color(0.95, 0.85, 0.6))
	# деревья и камни — из тех же чанков, что строит игра
	var n := int(WorldData.HALF * 2 / WorldData.CHUNK)
	for cz in n:
		for cx in n:
			var k := Vector2i(cx - n / 2, cz - n / 2)
			var d := WorldBuilder.gen_chunk(k, 0, 0)
			var o := Vector2(k.x * WorldData.CHUNK, k.y * WorldData.CHUNK)
			for key in d.props:
				var tree := String(key).contains("tree") or String(key).contains("pine") or String(key).contains("cactus_tall")
				var rock := String(key).contains("rock_large") or String(key).contains("rock_tall") or String(key).contains("stone_tall") or String(key).contains("rocks-tall")
				if not tree and not rock: continue
				for t in d.props[key]:
					var tr: Transform3D = t
					var p := o + Vector2(tr.origin.x, tr.origin.z)
					var px := (p + Vector2.ONE * WorldData.HALF) / step
					if tree:
						var dark := String(key).contains("dark") or String(key).contains("pine")
						var cc := Color(0.13, 0.25, 0.12) if dark else Color(0.2, 0.36, 0.15)
						if String(key).contains("cactus"): cc = Color(0.3, 0.45, 0.22)
						if String(key).contains("fall"): cc = Color(0.55, 0.35, 0.12)
						var sn := WorldData.biome_at(p.x, p.y) == 4
						if sn: cc = Color(0.18, 0.3, 0.24)
						_disc(img, px + Vector2(0.8, 0.8), 2.6, Color(0, 0, 0), 0.25)
						_disc(img, px, 2.2, cc, 0.95)
						_disc(img, px - Vector2(0.6, 0.6), 1.0, cc.lightened(0.25), 0.8)
					else:
						_disc(img, px, 1.6, Color(0.5, 0.48, 0.45), 0.9)
		if cz % 4 == 0: print("chunks row ", cz, " ", Time.get_ticks_msec() - t0, " ms")
	# дороги: обочина + полотно — по тем же сглаженным отрезкам, что и в игре
	for sg in WorldData._roads:
		_line(img, (sg[0] + Vector2.ONE * WorldData.HALF) / step, (sg[1] + Vector2.ONE * WorldData.HALF) / step, 6.0, Color(0.30, 0.22, 0.15), 0.75)
	for sg in WorldData._roads:
		_line(img, (sg[0] + Vector2.ONE * WorldData.HALF) / step, (sg[1] + Vector2.ONE * WorldData.HALF) / step, 3.4, Color(0.74, 0.62, 0.43), 1.0)
	img.save_png(ProjectSettings.globalize_path("res://assets/world/worldmap.png"))
	print("worldmap baked ", Time.get_ticks_msec() - t0, " ms")
	get_tree().quit()

func _disc(img: Image, c: Vector2, r: float, col: Color, a: float) -> void:
	for y in range(int(c.y - r - 1), int(c.y + r + 2)):
		for x in range(int(c.x - r - 1), int(c.x + r + 2)):
			if x < 0 or y < 0 or x >= S or y >= S: continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var k := clampf(r - d + 0.5, 0, 1) * a
			if k > 0: img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, k))

func _line(img: Image, a: Vector2, b: Vector2, w: float, col: Color, al: float) -> void:
	var len := a.distance_to(b)
	var steps := int(len / 0.7) + 1
	var mn := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * (w + 1)
	var mx := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * (w + 1)
	var ab := b - a
	for y in range(maxi(0, int(mn.y)), mini(S, int(mx.y) + 1)):
		for x in range(maxi(0, int(mn.x)), mini(S, int(mx.x) + 1)):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0, 1)
			var d := p.distance_to(a + ab * t)
			var k := clampf(w * 0.5 - d + 0.5, 0, 1) * al
			if k > 0: img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, k))
