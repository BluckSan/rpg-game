extends SceneTree
## Карта мира для окна «Карта» и мини-карты: assets/world/worldmap.png (512×512, цвета биомов + рельеф)
func _init() -> void:
	WorldData.init()
	var S := 512
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var step := WorldData.HALF * 2 / S
	var hs := PackedFloat32Array(); hs.resize(S * S)
	for y in S:
		for x in S:
			var wx := -WorldData.HALF + (x + 0.5) * step; var wz := -WorldData.HALF + (y + 0.5) * step
			hs[y * S + x] = WorldData._raw_height(wx, wz)
	for y in S:
		for x in S:
			var wx := -WorldData.HALF + (x + 0.5) * step; var wz := -WorldData.HALF + (y + 0.5) * step
			var w := WorldData.biome_weights(wx, wz)
			var c := Color(0, 0, 0)
			for i in w.size(): c += (WorldData.BIOMES[i].color as Color) * w[i]
			var h := hs[y * S + x]
			var hx := hs[y * S + mini(x + 1, S - 1)] - hs[y * S + maxi(x - 1, 0)]
			var hz := hs[mini(y + 1, S - 1) * S + x] - hs[maxi(y - 1, 0) * S + x]
			var shade := clampf(0.9 - (hx + hz) * 0.06 + h * 0.006, 0.55, 1.25)
			c = c * shade
			if w[3] > 0.45 and h < -0.25: c = c.lerp(Color(0.2, 0.28, 0.22), 0.6)
			var e := maxf(absf(wx), absf(wz))
			if e > WorldData.EDGE: c = c.lerp(Color(0.35, 0.32, 0.3), clampf((e - WorldData.EDGE) / 50.0, 0, 1))
			c.a = 1
			img.set_pixel(x, y, c)
	img.save_png(ProjectSettings.globalize_path("res://assets/world/worldmap.png"))
	print("worldmap baked")
	quit()
