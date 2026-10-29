extends Node
## v0.9.3: проверка формулы опыта и кривой
var fails := 0
func ok(c: bool, s: String) -> void:
	print(("  OK  " if c else "  FAIL ") + s)
	if not c: fails += 1
func _ready() -> void:
	print("XP: множитель уровня (игрок 20):")
	var row := ""
	for d in [-12, -9, -8, -7, -6, -5, -4, -3, -2, 0, 1, 3, 5, 8]: row += " %+d:%.2f" % [d, Xp.level_mult(20, 20 + d)]
	print(row)
	ok(Xp.level_mult(20, 22) > Xp.level_mult(20, 20), "выше уровнем — больше")
	ok(Xp.level_mult(20, 13) <= 0.15 and Xp.is_grey(20, 14), "серые резко падают")
	var solo: float = Xp.shares(30, 20, "normal", [20])[0]
	var eli: float = Xp.shares(30, 20, "elite", [20])[0]
	var champ: float = Xp.shares(30, 20, "rare", [20])[0]
	print("XP: моб 30 ур.20: обычный %.0f, элита %.0f, чемпион %.0f" % [solo, eli, champ])
	ok(eli == solo * 2.5 and champ == solo * 4.0, "элита ×2.5, чемпион ×4")
	var g: Array = Xp.shares(30, 20, "normal", [20, 20])
	var g3: Array = Xp.shares(30, 20, "normal", [20, 18, 16])
	print("XP: группа 2×20: %s; группа 20/18/16: %s" % [str(g), str(g3)])
	ok(absf(g[0] - solo * 1.1 / 2) < 0.01, "группа 2: каждому 55% (бонус +10%)")
	ok(g[0] + g[1] > solo, "в сумме группа получает больше соло")
	var st := {}
	var a := Xp.personal(100, st, "wolf", 0.0, 1)
	var b := Xp.personal(100, st, "wolf", 5.0, 1)
	var c := Xp.personal(100, st, "wolf", 10.0, 1)
	var d := Xp.personal(100, st, "wolf", 100.0, 1)
	var e := Xp.personal(100, st, "wolf", 101.0, 2)
	print("XP: бонусы: первое за день %d, серия 1: %d, серия 2: %d, после паузы %d, новый день %d" % [a, b, c, d, e])
	ok(a == 150 and b == 103 and c == 106 and d == 100 and e == 153, "день +50%, серия +3%/убийство, сброс")
	var s := ""
	for L in [1, 2, 5, 10, 15, 20, 25, 30, 40]:
		s += " L%d:%d(%.0f уб.)" % [L, Xp.to_next(L), Xp.to_next(L) / Xp.base(30, L)]
	print("XP: кривая (до след. ур., убийств обычного моба 30 своего ур.):" + s)
	var prev := 0.0
	var mono := true
	for L in range(1, 50):
		var k := Xp.to_next(L) / Xp.base(30, L)
		if k < prev: mono = false
		prev = k
	ok(mono and Xp.to_next(10) / Xp.base(30, 10) < 25, "темп ровный и растёт плавно")
	ok(DB.xp_to_next(10) == Xp.to_next(10), "DB использует новую кривую")
	print("XP_TEST %s (%d ошибок)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit()
