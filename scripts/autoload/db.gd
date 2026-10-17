extends Node
## Игровые данные: классы, умения, враги, пути превращения, дерево талантов, добыча, расчёт характеристик.

const SKIN_COLORS := [Color(1,0.87,0.77), Color(0.96,0.78,0.62), Color(0.85,0.65,0.47), Color(0.66,0.46,0.32),
	Color(0.45,0.3,0.2), Color(0.3,0.2,0.14), Color(0.6,0.75,0.6), Color(0.7,0.72,0.85)]
const HAIR_COLORS := [Color(0.08,0.06,0.05), Color(0.35,0.2,0.1), Color(0.6,0.4,0.2), Color(0.95,0.85,0.55),
	Color(0.75,0.25,0.1), Color(0.9,0.9,0.92), Color(0.3,0.4,0.9), Color(0.8,0.3,0.6)]
const EYE_COLORS := [Color(0.3,0.2,0.1), Color(0.2,0.45,0.9), Color(0.25,0.65,0.3), Color(0.5,0.5,0.5), Color(0.85,0.65,0.1), Color(0.8,0.1,0.1)]
const HAIR_STYLES := ["Короткая", "Ёжик", "Длинная", "Хвост", "Ирокез", "Лысый"]
const FACES := ["Обычное", "Острое", "Борода", "Шрам"]

const RARITY_NAMES := ["Обычный", "Магический", "Редкий", "Уникальный", "Комплект"]
const RARITY_COLORS := [Color(0.9,0.9,0.9), Color(0.4,0.6,1), Color(1,0.9,0.3), Color(1,0.5,0.1), Color(0.3,0.95,0.45)]
const SLOT_NAMES := ["Оружие", "Броня", "Шлем", "Кольцо", "Перчатки", "Сапоги", "Амулет", "Пояс"]
const MAX_SLOTS := 6
const INVENTORY_SIZE := 40
const ASC_LEVEL := 8
const ASC_REGION_POINTS := 6

const STAT_NAMES := {
	"hp": "к здоровью", "hp%": "% к здоровью", "mp": "к мане", "mp%": "% к мане",
	"dmg": "к урону", "dmg%": "% к урону", "spell%": "% к урону чар", "as%": "% к скорости атаки",
	"ms%": "% к скорости бега", "crit": "% шанс крит. удара", "critdmg%": "% к силе крит. удара",
	"armor": "к броне", "armor%": "% к броне", "regen": "здоровья в сек.", "mpregen": "маны в сек.",
	"leech%": "% похищения жизни", "cdr%": "% сокращения перезарядки", "dr%": "% снижения получаемого урона",
	"pen%": "% пробивания брони", "resred": "% снижения сопротивлений цели",
}
## Пассивы и модификаторы умений из талантов (значение — за ранг; %s — число)
const FX_NAMES := {
	"aoe%": "+%s%% к области умений", "combo_wave": "3-й удар серии — ударная волна", "thorns": "Отражение %s%% урона",
	"proc_bleed": "%s%% шанс кровотечения", "proc_poison": "%s%% шанс отравления", "proc_burn": "%s%% шанс поджога",
	"proc_bolt": "%s%% шанс молнии при ударе", "leech_x": "Похищение жизни ×2", "no_regen": "Нет регенерации здоровья",
	"low_hp_dmg": "+%s%% урона при здоровье < 35%%", "chain_plus": "+%s отскок(а) цепных умений", "mana_cost": "+%s%% к стоимости умений",
	"elem_ice": "Огненные снаряды → ледяные (замедление)", "aura_dmg": "Аура: %s%% урона/с врагам рядом", "aura_frost": "Аура замедляет врагов",
	"mana_guard": "%s%% урона снимается с маны", "crit_mark": "Крит проклинает цель (+30% урона по ней)", "far_dmg": "+%s%% урона по дальним целям",
	"extra_proj": "+%s снаряд(а)", "proj_dmg": "%s%% урона снарядов", "roll_stealth": "После кувырка — гарантированный крит",
	"kill_explode": "%s%% шанс взрыва трупа", "kill_heal": "Убийство лечит %s%% здоровья", "kill_mana": "Убийство даёт %s%% маны",
	"crit_heal": "Крит лечит %s%% здоровья",
}
const TREE_VERSION := 2

var CLASSES := {
	"warrior": {
		"name": "Воин", "weapon": "Ржавый меч", "color": Color(0.85,0.3,0.2),
		"desc": "Мастер ближнего боя. Много здоровья и брони.\nПути развития: Берсерк, Паладин, Друид.",
		"hp": 140.0, "hp_lvl": 14.0, "mp": 40.0, "mp_lvl": 3.0, "dmg": 12.0, "dmg_lvl": 2.2,
		"range": 2.6, "interval": 0.75, "ranged": false, "spell": false, "pen": 15.0,
		"skills": [
			{"id": "w_attack", "name": "Удар", "kind": "melee", "mult": 1.0, "cd": 0.0, "mana": 0.0, "radius": 2.6, "range": 2.6, "color": Color.WHITE, "unlock": 1},
			{"id": "w_spin", "name": "Вихрь", "desc": "Круговой удар по всем врагам рядом", "kind": "spin", "mult": 1.6, "cd": 6.0, "mana": 15.0, "radius": 4.2, "range": 4.0, "color": Color(1,0.6,0.3), "unlock": 1},
			{"id": "w_dash", "name": "Рывок", "desc": "Рывок вперёд, ранит врагов на пути", "kind": "dash", "mult": 2.2, "cd": 8.0, "mana": 15.0, "radius": 2.0, "range": 8.0, "color": Color(1,0.85,0.4), "unlock": 3},
			{"id": "w_slam", "name": "Раскол земли", "desc": "Удар по земле перед собой: урон конусом и оглушение на 1.5 с", "kind": "ground_slam", "mult": 2.0, "cd": 9.0, "mana": 18.0, "radius": 5.5, "range": 5.5, "color": Color(0.85,0.6,0.35), "lvl": 4},
			{"id": "w_cry", "name": "Боевой клич", "desc": "8 с: +30% урона и +40% брони, враги рядом замедлены", "kind": "warcry", "mult": 0.0, "cd": 20.0, "mana": 20.0, "radius": 6.0, "range": 0.0, "color": Color(1,0.75,0.3), "lvl": 6},
			{"id": "w_leap", "name": "Прыжок героя", "desc": "Прыжок к цели, удар по области при приземлении", "kind": "leap", "mult": 2.4, "cd": 11.0, "mana": 20.0, "radius": 3.5, "range": 11.0, "color": Color(1,0.9,0.5), "lvl": 8},
			{"id": "w_iron", "name": "Железная кожа", "desc": "5 с: урон по вам снижен на 50%, восстанавливает 10% здоровья", "kind": "iron_skin", "mult": 0.0, "cd": 18.0, "mana": 15.0, "radius": 0.0, "range": 0.0, "color": Color(0.75,0.8,0.9), "lvl": 10},
			{"id": "w_exec", "name": "Казнь", "desc": "Мощный удар; втрое сильнее по цели с запасом здоровья ниже 30%", "kind": "execute", "mult": 3.0, "cd": 12.0, "mana": 22.0, "radius": 0.0, "range": 3.2, "color": Color(1,0.3,0.2), "lvl": 12},
		]},
	"archer": {
		"name": "Лучник", "weapon": "Кривой лук", "color": Color(0.3,0.7,0.3),
		"desc": "Стреляет издалека, быстрый и ловкий. Высокий шанс крита.\nПути развития: Тень, Друид, Берсерк.",
		"hp": 100.0, "hp_lvl": 10.0, "mp": 60.0, "mp_lvl": 4.0, "dmg": 10.0, "dmg_lvl": 2.0,
		"range": 14.0, "interval": 0.6, "ranged": true, "spell": false,
		"skills": [
			{"id": "a_attack", "name": "Выстрел", "kind": "projectile", "mult": 1.0, "cd": 0.0, "mana": 0.0, "radius": 0.0, "range": 16.0, "color": Color(0.9,0.8,0.5), "unlock": 1},
			{"id": "a_volley", "name": "Залп", "desc": "Веер из пяти стрел", "kind": "volley", "mult": 0.9, "cd": 5.0, "mana": 14.0, "radius": 0.0, "range": 16.0, "color": Color(0.6,1,0.6), "unlock": 1},
			{"id": "a_rain", "name": "Град стрел", "desc": "Дождь стрел по области у цели", "kind": "arrow_rain", "mult": 2.4, "cd": 9.0, "mana": 22.0, "radius": 4.5, "range": 14.0, "color": Color(0.8,1,0.4), "unlock": 3},
			{"id": "a_pierce", "name": "Пронзающая стрела", "desc": "Стрела пробивает всех врагов на линии", "kind": "pierce", "mult": 2.2, "cd": 6.0, "mana": 14.0, "radius": 0.0, "range": 22.0, "color": Color(0.9,0.95,1.0), "lvl": 4},
			{"id": "a_leap", "name": "Отскок", "desc": "Прыжок назад; на прежнем месте — ледяная вспышка, замедляющая врагов", "kind": "disengage", "mult": 1.0, "cd": 9.0, "mana": 12.0, "radius": 3.5, "range": 7.0, "color": Color(0.6,0.9,1.0), "lvl": 6},
			{"id": "a_trap", "name": "Капкан", "desc": "Ставит капкан: взрыв обездвиживает и ранит врагов", "kind": "trap", "mult": 2.0, "cd": 12.0, "mana": 16.0, "radius": 3.0, "range": 0.0, "color": Color(0.9,0.7,0.3), "lvl": 8},
			{"id": "a_snipe", "name": "Меткий выстрел", "desc": "Прицеливание 0.5 с — гарантированный критический выстрел", "kind": "snipe", "mult": 3.6, "cd": 11.0, "mana": 20.0, "radius": 0.0, "range": 24.0, "color": Color(1,0.9,0.4), "lvl": 10},
			{"id": "a_poison", "name": "Ядовитая стрела", "desc": "Яд: урон в течение 6 с по цели и врагам рядом", "kind": "poison", "mult": 0.5, "cd": 8.0, "mana": 15.0, "radius": 2.5, "range": 18.0, "color": Color(0.5,1,0.3), "lvl": 12},
		]},
	"mage": {
		"name": "Маг", "weapon": "Посох ученика", "color": Color(0.3,0.45,0.95),
		"desc": "Повелевает стихиями и тьмой. Мощные заклинания, мало здоровья.\nПути развития: Стихийник, Некромант, Паладин.",
		"hp": 85.0, "hp_lvl": 8.0, "mp": 120.0, "mp_lvl": 8.0, "dmg": 11.0, "dmg_lvl": 2.4,
		"range": 13.0, "interval": 0.8, "ranged": true, "spell": true,
		"skills": [
			{"id": "m_bolt", "name": "Искра", "kind": "projectile", "mult": 1.0, "cd": 0.0, "mana": 0.0, "radius": 0.0, "range": 15.0, "color": Color(0.5,0.7,1), "unlock": 1},
			{"id": "m_fireball", "name": "Огненный шар", "desc": "Взрывается и поджигает область", "kind": "fireball", "mult": 2.6, "cd": 5.0, "mana": 20.0, "radius": 3.2, "range": 15.0, "color": Color(1,0.45,0.1), "unlock": 1},
			{"id": "m_nova", "name": "Ледяная нова", "desc": "Замораживает и ранит врагов вокруг", "kind": "frost_nova", "mult": 1.5, "cd": 8.0, "mana": 25.0, "radius": 5.0, "range": 5.0, "color": Color(0.6,0.9,1), "unlock": 3},
			{"id": "m_chain", "name": "Цепная молния", "desc": "Молния перескакивает между 5 врагами", "kind": "chain", "mult": 1.6, "cd": 6.0, "mana": 18.0, "radius": 7.0, "range": 15.0, "color": Color(0.7,0.8,1.0), "lvl": 4},
			{"id": "m_blink", "name": "Скачок", "desc": "Мгновенный перенос на 8 м вперёд", "kind": "blink", "mult": 0.0, "cd": 8.0, "mana": 12.0, "radius": 0.0, "range": 8.0, "color": Color(0.6,0.5,1.0), "lvl": 6},
			{"id": "m_wall", "name": "Огненная полоса", "desc": "Полоса огня перед магом жжёт врагов 4 с", "kind": "fire_wall", "mult": 0.6, "cd": 12.0, "mana": 24.0, "radius": 1.6, "range": 9.0, "color": Color(1,0.5,0.15), "lvl": 8},
			{"id": "m_shield", "name": "Щит маны", "desc": "6 с: урон по вам снижен на 50%, восстанавливает ману", "kind": "mana_shield", "mult": 0.0, "cd": 20.0, "mana": 0.0, "radius": 0.0, "range": 0.0, "color": Color(0.5,0.7,1.0), "lvl": 10},
			{"id": "m_lance", "name": "Ледяное копьё", "desc": "Пробивающее копьё льда, сильно замедляет", "kind": "ice_lance", "mult": 2.6, "cd": 7.0, "mana": 20.0, "radius": 0.0, "range": 20.0, "color": Color(0.7,0.95,1.0), "lvl": 12},
		]},
}
const CLASS_ORDER := ["warrior", "archer", "mage"]

var ASCENDANCIES := [
	{"id": "berserker", "name": "Берсерк", "color": Color(0.9,0.2,0.1),
	 "desc": "Багровая ярость: тело растёт, глаза горят.\n+25% урона, +10% скорости атаки.",
	 "mods": [["dmg%", 25], ["as%", 10]],
	 "skill": {"id": "asc_rage", "name": "Ярость", "desc": "8 сек: +50% урона и скорости атаки", "kind": "rage", "mult": 0.0, "cd": 20.0, "mana": 20.0, "radius": 0.0, "range": 0.0, "color": Color(1,0.2,0.1)}, "skills_extra": [{"id": "asc_bloodspin", "name": "Кровавый вихрь", "desc": "Широкий вихрь, лечит 3% здоровья за каждого задетого врага", "kind": "blood_spin", "mult": 2.2, "cd": 9.0, "mana": 18.0, "radius": 5.0, "range": 5.0, "color": Color(0.9,0.1,0.1), "lvl": 10},
		{"id": "asc_quake", "name": "Землетрясение", "desc": "Три волны толчков вокруг героя", "kind": "quake", "mult": 1.4, "cd": 14.0, "mana": 25.0, "radius": 6.5, "range": 0.0, "color": Color(0.8,0.45,0.25), "lvl": 12}]},
	{"id": "paladin", "name": "Паладин", "color": Color(1,0.85,0.3),
	 "desc": "Золотые латы и нимб света.\n+30% брони, +15% здоровья.",
	 "mods": [["armor%", 30], ["hp%", 15]],
	 "skill": {"id": "asc_shield", "name": "Священный щит", "desc": "Лечит 35% здоровья и снижает урон на 6 сек", "kind": "holy_shield", "mult": 0.0, "cd": 22.0, "mana": 25.0, "radius": 0.0, "range": 0.0, "color": Color(1,0.9,0.4)}, "skills_extra": [{"id": "asc_hammer", "name": "Молот света", "desc": "Летящий молот: взрыв света оглушает врагов", "kind": "holy_hammer", "mult": 2.6, "cd": 9.0, "mana": 20.0, "radius": 3.0, "range": 16.0, "color": Color(1,0.9,0.5), "lvl": 10},
		{"id": "asc_consecrate", "name": "Освящение", "desc": "Святая земля 6 с: жжёт врагов и лечит героя", "kind": "consecrate", "mult": 0.5, "cd": 16.0, "mana": 25.0, "radius": 5.0, "range": 0.0, "color": Color(1,0.85,0.4), "lvl": 12}]},
	{"id": "elementalist", "name": "Стихийник", "color": Color(0.3,0.7,1),
	 "desc": "Вокруг кружат сферы огня, льда и молний.\n+30% урона чар, +10% сокращения перезарядки.",
	 "mods": [["spell%", 30], ["cdr%", 10], ["dmg%", 10]],
	 "skill": {"id": "asc_meteor", "name": "Метеор", "desc": "Огромный метеор по области", "kind": "meteor", "mult": 5.0, "cd": 16.0, "mana": 40.0, "radius": 6.0, "range": 15.0, "color": Color(1,0.4,0.1)}, "skills_extra": [{"id": "asc_storm", "name": "Буря", "desc": "8 ударов молний по врагам вокруг", "kind": "storm", "mult": 1.3, "cd": 13.0, "mana": 30.0, "radius": 10.0, "range": 0.0, "color": Color(0.7,0.85,1), "lvl": 10},
		{"id": "asc_prison", "name": "Ледяная тюрьма", "desc": "Сковывает льдом врагов в области на 3 с", "kind": "ice_prison", "mult": 1.2, "cd": 15.0, "mana": 25.0, "radius": 4.5, "range": 14.0, "color": Color(0.6,0.95,1), "lvl": 12}]},
	{"id": "necromancer", "name": "Некромант", "color": Color(0.55,0.3,0.8),
	 "desc": "Бледная кожа, тёмная аура, парящие черепа.\n+20% урона чар, +3% похищения жизни.",
	 "mods": [["spell%", 20], ["leech%", 3], ["dmg%", 10]],
	 "skill": {"id": "asc_summon", "name": "Поднять скелетов", "desc": "Призывает 2 скелетов на 25 сек", "kind": "summon", "mult": 0.6, "cd": 25.0, "mana": 35.0, "radius": 0.0, "range": 0.0, "color": Color(0.7,0.5,1)}, "skills_extra": [{"id": "asc_bones", "name": "Костяная буря", "desc": "Кольцо из 12 костяных осколков", "kind": "bone_nova", "mult": 1.2, "cd": 8.0, "mana": 18.0, "radius": 0.0, "range": 12.0, "color": Color(0.9,0.9,0.8), "lvl": 10},
		{"id": "asc_curse", "name": "Проклятие", "desc": "Враги в области получают на 30% больше урона и замедлены 8 с", "kind": "curse", "mult": 0.0, "cd": 16.0, "mana": 20.0, "radius": 5.0, "range": 14.0, "color": Color(0.6,0.3,0.9), "lvl": 12}]},
	{"id": "shadow", "name": "Тень", "color": Color(0.25,0.2,0.35),
	 "desc": "Тело окутано дымом, движения бесшумны.\n+10% крита, +50% силы крита, +10% скорости.",
	 "mods": [["crit", 10], ["critdmg%", 50], ["ms%", 10]],
	 "skill": {"id": "asc_strike", "name": "Теневой удар", "desc": "Телепорт к врагу и гарантированный крит", "kind": "shadow_strike", "mult": 4.0, "cd": 10.0, "mana": 20.0, "radius": 0.0, "range": 14.0, "color": Color(0.5,0.3,0.7)}, "skills_extra": [{"id": "asc_knives", "name": "Веер кинжалов", "desc": "8 кинжалов во все стороны", "kind": "knife_fan", "mult": 1.3, "cd": 7.0, "mana": 14.0, "radius": 0.0, "range": 11.0, "color": Color(0.7,0.6,0.9), "lvl": 10},
		{"id": "asc_vanish", "name": "Исчезновение", "desc": "1.5 с неуязвимости и +40% скорости на 4 с", "kind": "vanish", "mult": 0.0, "cd": 18.0, "mana": 15.0, "radius": 0.0, "range": 0.0, "color": Color(0.4,0.3,0.6), "lvl": 12}]},
	{"id": "druid", "name": "Друид-зверь", "color": Color(0.35,0.6,0.25),
	 "desc": "Облик медведя: огромное звериное тело.\n+30% здоровья, +15% урона, +3 регенерации.",
	 "mods": [["hp%", 30], ["dmg%", 15], ["regen", 3]],
	 "skill": {"id": "asc_roar", "name": "Рёв зверя", "desc": "Оглушает врагов вокруг и лечит", "kind": "beast_roar", "mult": 2.0, "cd": 14.0, "mana": 20.0, "radius": 6.0, "range": 0.0, "color": Color(0.5,0.9,0.3)}, "skills_extra": [{"id": "asc_maul", "name": "Размах когтей", "desc": "Сокрушительный удар лапами перед собой", "kind": "maul", "mult": 3.0, "cd": 8.0, "mana": 15.0, "radius": 4.0, "range": 4.0, "color": Color(0.6,0.85,0.35), "lvl": 10},
		{"id": "asc_regrow", "name": "Восстановление", "desc": "Восстанавливает 40% здоровья за 6 с", "kind": "regrowth", "mult": 0.0, "cd": 20.0, "mana": 20.0, "radius": 0.0, "range": 0.0, "color": Color(0.4,1,0.5), "lvl": 12}]},
]

var ENEMIES := {
	"slime": {"name": "Слизень", "hp": 40.0, "dmg": 6.0, "speed": 2.2, "range": 1.6, "interval": 1.4, "aggro": 8.0, "radius": 0.6, "xp": 14.0, "ranged": false, "boss": false, "color": Color(0.4,0.85,0.3)},
	"wolf": {"name": "Серый волк", "hp": 55.0, "dmg": 9.0, "speed": 5.2, "range": 1.8, "interval": 1.0, "aggro": 11.0, "radius": 0.7, "xp": 22.0, "ranged": false, "boss": false, "color": Color(0.45,0.45,0.48)},
	"skeleton_archer": {"name": "Скелет-лучник", "hp": 50.0, "dmg": 11.0, "speed": 2.6, "range": 11.0, "interval": 1.8, "aggro": 13.0, "radius": 0.5, "xp": 28.0, "ranged": true, "boss": false, "color": Color(0.9,0.88,0.8)},
	"skeleton": {"name": "Скелет-воин", "hp": 70.0, "dmg": 12.0, "speed": 3.4, "range": 1.9, "interval": 1.2, "aggro": 11.0, "radius": 0.5, "xp": 30.0, "ranged": false, "boss": false, "color": Color(0.85,0.83,0.75)},
	"goblin": {"name": "Гоблин-громила", "hp": 120.0, "dmg": 18.0, "speed": 3.0, "range": 2.2, "interval": 1.6, "aggro": 10.0, "radius": 0.8, "xp": 45.0, "ranged": false, "boss": false, "color": Color(0.35,0.55,0.2)},
	"ether_guard": {"name": "Страж Эфира", "hp": 160.0, "dmg": 16.0, "speed": 3.4, "range": 2.0, "interval": 1.3, "aggro": 30.0, "radius": 0.6, "xp": 60.0, "ranged": false, "boss": false, "color": Color(0.6,0.4,1.0)},
	"warden": {"name": "Хранитель Эфира", "hp": 3000.0, "dmg": 30.0, "speed": 3.6, "range": 3.4, "interval": 2.0, "aggro": 17.0, "radius": 1.6, "xp": 1500.0, "ranged": false, "boss": true, "color": Color(0.45,0.35,0.7)},
	"troll": {"name": "Древний тролль", "hp": 2200.0, "dmg": 28.0, "speed": 3.2, "range": 3.2, "interval": 1.8, "aggro": 16.0, "radius": 1.6, "xp": 500.0, "ranged": false, "boss": true, "color": Color(0.4,0.5,0.45)},
	# --- v0.5.1: семейства открытого мира (модели Quaternius CC0). ai: роль в бою ---
	"rat": {"name": "Полевая крыса", "hp": 30.0, "dmg": 5.0, "speed": 4.8, "range": 1.4, "interval": 0.9, "aggro": 10.0, "radius": 0.45, "xp": 10.0, "ranged": false, "boss": false, "color": Color(0.5,0.45,0.42), "model": "rat", "ai": "swarm"},
	"bull": {"name": "Дикий тур", "hp": 110.0, "dmg": 14.0, "speed": 3.0, "range": 2.4, "interval": 1.6, "aggro": 12.0, "radius": 0.9, "xp": 40.0, "ranged": false, "boss": false, "color": Color(0.25,0.2,0.18), "model": "bull", "model_scale": 0.85, "ai": "charger"},
	"spider": {"name": "Лесной паук", "hp": 45.0, "dmg": 7.0, "speed": 4.2, "range": 1.7, "interval": 1.0, "aggro": 11.0, "radius": 0.6, "xp": 18.0, "ranged": false, "boss": false, "color": Color(0.2,0.2,0.22), "model": "spider", "ai": "swarm"},
	"mushnub": {"name": "Спорыш", "hp": 35.0, "dmg": 26.0, "speed": 3.8, "range": 1.8, "interval": 1.0, "aggro": 12.0, "radius": 0.5, "xp": 16.0, "ranged": false, "boss": false, "color": Color(0.3,0.5,0.7), "model": "mushnub", "ai": "exploder"},
	"goblin_shaman": {"name": "Гоблин-шаман", "hp": 60.0, "dmg": 8.0, "speed": 2.8, "range": 10.0, "interval": 2.0, "aggro": 13.0, "radius": 0.5, "xp": 30.0, "ranged": true, "boss": false, "color": Color(0.45,0.6,0.3), "model": "goblin_q", "tint": Color(0.75, 0.95, 0.7), "emission": Color(0.3, 1.0, 0.4), "ai": "healer", "proj": Color(0.4, 1.0, 0.5)},
	"bee": {"name": "Жалень", "hp": 28.0, "dmg": 6.0, "speed": 5.0, "range": 1.5, "interval": 0.8, "aggro": 11.0, "radius": 0.45, "xp": 12.0, "ranged": false, "boss": false, "color": Color(0.9,0.75,0.2), "model": "bee", "ai": "swarm"},
	"orc": {"name": "Орк-рубака", "hp": 130.0, "dmg": 17.0, "speed": 3.2, "range": 2.2, "interval": 1.4, "aggro": 12.0, "radius": 0.7, "xp": 48.0, "ranged": false, "boss": false, "color": Color(0.4,0.55,0.25), "model": "orc", "ai": "melee"},
	"cactoro": {"name": "Колючник", "hp": 70.0, "dmg": 11.0, "speed": 2.0, "range": 11.0, "interval": 1.9, "aggro": 13.0, "radius": 0.6, "xp": 30.0, "ranged": true, "boss": false, "color": Color(0.35,0.6,0.3), "model": "cactoro", "ai": "ranged", "proj": Color(0.55, 0.9, 0.35), "shot_h": 0.9},
	"drake": {"name": "Пепельный дракончик", "hp": 65.0, "dmg": 16.0, "speed": 3.6, "range": 12.0, "interval": 2.6, "aggro": 14.0, "radius": 0.6, "xp": 36.0, "ranged": false, "boss": false, "color": Color(0.8,0.45,0.2), "model": "drake", "ai": "caster", "proj": Color(1.0, 0.45, 0.15), "minion": "drake"},
	"frog": {"name": "Болотная жаба", "hp": 75.0, "dmg": 12.0, "speed": 2.6, "range": 10.0, "interval": 2.0, "aggro": 12.0, "radius": 0.55, "xp": 32.0, "ranged": true, "boss": false, "color": Color(0.8,0.65,0.15), "model": "frog", "ai": "ranged", "proj": Color(0.6, 0.95, 0.2), "shot_h": 0.8},
	"crab": {"name": "Панцирник", "hp": 150.0, "dmg": 14.0, "speed": 2.4, "range": 1.9, "interval": 1.6, "aggro": 10.0, "radius": 0.75, "xp": 44.0, "ranged": false, "boss": false, "color": Color(0.7,0.25,0.2), "model": "crab", "ai": "melee"},
	"ghost": {"name": "Топкий призрак", "hp": 70.0, "dmg": 15.0, "speed": 3.0, "range": 12.0, "interval": 2.8, "aggro": 14.0, "radius": 0.55, "xp": 38.0, "ranged": false, "boss": false, "color": Color(0.3,0.2,0.4), "model": "ghost", "ai": "caster", "proj": Color(0.6, 0.35, 1.0), "minion": "bat"},
	"bat": {"name": "Нетопырь", "hp": 30.0, "dmg": 7.0, "speed": 5.5, "range": 1.5, "interval": 0.9, "aggro": 12.0, "radius": 0.45, "xp": 12.0, "ranged": false, "boss": false, "color": Color(0.2,0.15,0.3), "model": "bat", "ai": "swarm"},
	"yeti": {"name": "Йети", "hp": 170.0, "dmg": 20.0, "speed": 3.0, "range": 2.4, "interval": 1.7, "aggro": 12.0, "radius": 0.9, "xp": 60.0, "ranged": false, "boss": false, "color": Color(0.8,0.85,0.9), "model": "yeti", "ai": "charger"},
	"hywirl": {"name": "Вьюжник", "hp": 80.0, "dmg": 16.0, "speed": 3.2, "range": 12.0, "interval": 2.8, "aggro": 14.0, "radius": 0.6, "xp": 40.0, "ranged": false, "boss": false, "color": Color(0.5,0.75,1.0), "model": "hywirl", "tint": Color(0.6, 0.85, 1.25), "emission": Color(0.4, 0.8, 1.0), "ai": "caster", "proj": Color(0.55, 0.85, 1.0)},
	"imp": {"name": "Крылатый князь", "hp": 85.0, "dmg": 12.0, "speed": 3.4, "range": 11.0, "interval": 2.2, "aggro": 14.0, "radius": 0.6, "xp": 42.0, "ranged": true, "boss": false, "color": Color(0.55,0.65,0.2), "model": "imp", "ai": "healer", "proj": Color(0.9, 0.85, 0.3), "shot_h": 1.8},
	"demon": {"name": "Бес Эфира", "hp": 90.0, "dmg": 18.0, "speed": 3.4, "range": 12.0, "interval": 2.6, "aggro": 15.0, "radius": 0.7, "xp": 48.0, "ranged": false, "boss": false, "color": Color(0.7,0.15,0.15), "model": "demon", "ai": "caster", "proj": Color(0.95, 0.5, 1.0), "minion": "bat"},
	"bluedemon": {"name": "Рогатый демон", "hp": 150.0, "dmg": 20.0, "speed": 3.6, "range": 2.2, "interval": 1.3, "aggro": 14.0, "radius": 0.7, "xp": 55.0, "ranged": false, "boss": false, "color": Color(0.2,0.4,0.6), "model": "bluedemon", "ai": "melee"},
	# боссы зон мира — свои модели и приёмы (BossBrain: moves/adds)
	"boss_ogron": {"name": "Король холмов Огрон", "hp": 2200.0, "dmg": 28.0, "speed": 3.2, "range": 3.2, "interval": 1.8, "aggro": 16.0, "radius": 1.6, "xp": 520.0, "ranged": false, "boss": true, "color": Color(0.4,0.55,0.25), "model": "orc", "model_scale": 2.3, "moves": ["slam", "rock", "charge"], "adds": ["wolf", "bull"]},
	"boss_root": {"name": "Древень Мшистый Корень", "hp": 2300.0, "dmg": 27.0, "speed": 2.8, "range": 3.2, "interval": 1.9, "aggro": 16.0, "radius": 1.6, "xp": 560.0, "ranged": false, "boss": true, "color": Color(0.3,0.5,0.7), "model": "mushking", "model_scale": 2.2, "moves": ["slam", "spores", "rock"], "adds": ["mushnub", "spider"], "proj": Color(0.6, 0.9, 0.3)},
	"boss_urgal": {"name": "Пепельный дракон Ургал", "hp": 2400.0, "dmg": 30.0, "speed": 3.4, "range": 3.6, "interval": 2.0, "aggro": 18.0, "radius": 1.8, "xp": 620.0, "ranged": false, "boss": true, "color": Color(0.85,0.45,0.2), "model": "dragon", "model_scale": 2.6, "moves": ["breath", "rock", "charge"], "adds": ["drake", "drake"], "proj": Color(1.0, 0.45, 0.1), "elem": "fire"},
	"boss_gnil": {"name": "Топяной великан Гнилобрюх", "hp": 2500.0, "dmg": 30.0, "speed": 2.8, "range": 3.4, "interval": 2.0, "aggro": 16.0, "radius": 1.8, "xp": 660.0, "ranged": false, "boss": true, "color": Color(0.7,0.6,0.15), "model": "frog", "model_scale": 3.6, "moves": ["spores", "slam", "rock"], "adds": ["frog", "bat"], "proj": Color(0.6, 0.95, 0.2)},
	"boss_hyalm": {"name": "Инеистый йети Хьяльм", "hp": 2600.0, "dmg": 32.0, "speed": 3.2, "range": 3.4, "interval": 1.9, "aggro": 17.0, "radius": 1.8, "xp": 720.0, "ranged": false, "boss": true, "color": Color(0.8,0.9,1.0), "model": "yeti", "model_scale": 2.3, "moves": ["slam", "nova", "charge"], "adds": ["wolf", "hywirl"], "proj": Color(0.6, 0.9, 1.0)},
	"boss_seraph": {"name": "Падший серафим Эфира", "hp": 2800.0, "dmg": 34.0, "speed": 3.4, "range": 3.6, "interval": 2.0, "aggro": 18.0, "radius": 1.8, "xp": 800.0, "ranged": false, "boss": true, "color": Color(0.7,0.15,0.2), "model": "demon", "model_scale": 3.0, "moves": ["nova", "breath", "rock"], "adds": ["imp", "ether_guard"], "proj": Color(0.95, 0.5, 1.0)},
}

## Зоны: стартовая долина, подземелье, открытый мир «Земли Эфира» (WorldBuilder).
var ZONES := {
	"starter": {"name": "Пепельная долина", "scene": "res://scenes/zone.tscn", "available": true, "min_level": 1},
	"dungeon": {"name": "Склеп Эфира", "scene": "res://scenes/zone.tscn", "available": true, "min_level": 1, "requires": ["starter", "boss_troll_killed"]},
	"global": {"name": "Земли Эфира", "scene": "res://scenes/zone.tscn", "available": true, "min_level": 5},
}

# ---------------- Дерево талантов ----------------
var tree_nodes := {}     # id -> Dictionary
var tree_regions := {}   # id -> {name, color}
var tree_order := []

func _ready() -> void:
	_load_tree()

func _load_tree() -> void:
	var f := FileAccess.open("res://data/talent_tree.json", FileAccess.READ)
	if f == null:
		push_error("talent_tree.json не найден")
		return
	var data = JSON.parse_string(f.get_as_text())
	for r in data["regions"]:
		tree_regions[r["id"]] = {"name": r["name"], "color": Color.html(r["color"])}
	for n in data["nodes"]:
		var node := {
			"id": int(n["id"]), "name": n["name"], "type": n["type"], "region": n["region"], "class": n["classId"],
			"pos": Vector2(float(n["x"]), float(n["y"])), "mods": [], "links": [],
			"max_rank": int(n.get("max_rank", 1)), "fx": n.get("fx", {}), "branch": n.get("branch", ""),
			"req_asc": n.get("req_asc", ""), "req_branch": int(n.get("req_branch", 0)), "gate": bool(n.get("gate", false)),
			"desc": n.get("desc", ""), "branch_name": n.get("branch_name", ""), "branch_class": n.get("branch_class", "")}
		for m in n["mods"]:
			node["mods"].append([m["stat"], float(m["value"])])
		for l in n["links"]:
			node["links"].append(int(l))
		tree_nodes[node["id"]] = node
		tree_order.append(node["id"])

func start_node(class_id: String) -> int:
	for id in tree_order:
		var n = tree_nodes[id]
		if n["type"] == "start" and n["class"] == class_id:
			return id
	return 0

## Ворота региона превращения («Путь X»)
func keystone_of(region: String) -> Dictionary:
	for id in tree_order:
		var n = tree_nodes[id]
		if n["type"] == "keystone" and n["region"] == region and n["gate"]:
			return n
	return {}

## Ранг узла (0 — не изучен). Ранги хранятся в c["ranks"] {"id": ранг}; c["talents"] — изученные узлы.
func rank(c: Dictionary, id: int) -> int:
	if not c["talents"].has(id): return 0
	return maxi(1, int(c.get("ranks", {}).get(str(id), 1)))

func points_in_region(c: Dictionary, region: String) -> int:
	var k := 0
	for id in c["talents"]:
		if tree_nodes.has(int(id)) and tree_nodes[int(id)]["region"] == region:
			k += rank(c, int(id))
	return k

func points_in_branch(c: Dictionary, branch: String) -> int:
	var k := 0
	for id in c["talents"]:
		var n = tree_nodes.get(int(id))
		if n and n["branch"] == branch and n["type"] != "keystone": k += rank(c, int(id))
	return k

func spent_points(c: Dictionary) -> int:
	var k := 0
	for id in c["talents"]:
		if tree_nodes.has(int(id)) and tree_nodes[int(id)]["type"] != "start": k += rank(c, int(id))
	return k

func total_points(c: Dictionary) -> int:
	return (int(c["level"]) - 1) + 2 + (int(c["class_level"]) - 1) / 2

func free_points(c: Dictionary) -> int:
	return total_points(c) - spent_points(c)

func has_talent(c: Dictionary, id: int) -> bool:
	return c["talents"].has(id)

## "" — можно вложить очко (новый узел или следующий ранг), иначе причина
func alloc_block(c: Dictionary, id: int) -> String:
	if not tree_nodes.has(id): return "Нет узла"
	var n = tree_nodes[id]
	if n["type"] == "start": return "Стартовая точка"
	if has_talent(c, id) and rank(c, id) >= int(n["max_rank"]): return "Максимальный ранг"
	if free_points(c) <= 0: return "Нет очков"
	if n["req_asc"] != "" and c.get("ascendancy", "") != n["req_asc"]: return "Только для пути «%s»" % get_asc(n["req_asc"]).get("name", "?")
	if int(n["req_branch"]) > 0 and not has_talent(c, id) and points_in_branch(c, n["branch"]) < int(n["req_branch"]):
		return "Нужно %d очк. в ветви (%d)" % [int(n["req_branch"]), points_in_branch(c, n["branch"])]
	if has_talent(c, id): return ""
	for l in n["links"]:
		if has_talent(c, l): return ""
	return "Нет связи с изученным узлом"

func can_allocate(c: Dictionary, id: int) -> bool:
	return alloc_block(c, id) == ""

func allocate(c: Dictionary, id: int) -> bool:
	if not can_allocate(c, id): return false
	if not c.has("ranks"): c["ranks"] = {}
	if has_talent(c, id): c["ranks"][str(id)] = rank(c, id) + 1
	else:
		c["talents"].append(id)
		c["ranks"][str(id)] = 1
	return true

## "" — можно вернуть один ранг узла (без разрыва дерева и требований), иначе причина
func refund_block(c: Dictionary, id: int) -> String:
	if not has_talent(c, id): return "Не изучено"
	var n = tree_nodes[id]
	if n["type"] == "start": return "Стартовая точка"
	var asc: String = c.get("ascendancy", "")
	if rank(c, id) > 1:
		var tmp := c.duplicate(true)
		tmp["ranks"][str(id)] = rank(c, id) - 1
		return _req_broken(tmp, asc)
	# узел уходит целиком: остальные должны остаться связанными со стартом
	var rest: Array = c["talents"].duplicate(); rest.erase(id)
	var seen := {rest[0]: true} if not rest.is_empty() else {}
	var q: Array = [start_node(c["class"])]
	seen = {q[0]: true}
	while not q.is_empty():
		var cur: int = q.pop_back()
		for l in tree_nodes[cur]["links"]:
			if rest.has(l) and not seen.has(l):
				seen[l] = true; q.append(l)
	if seen.size() < rest.size(): return "Узел связывает другие изученные"
	var tmp2 := c.duplicate(true)
	tmp2["talents"] = rest
	return _req_broken(tmp2, asc)

func _req_broken(c: Dictionary, asc: String) -> String:
	for tid in c["talents"]:
		var m = tree_nodes.get(int(tid))
		if m and int(m["req_branch"]) > 0 and points_in_branch(c, m["branch"]) < int(m["req_branch"]):
			return "Нужно для «%s»" % m["name"]
	if asc != "":
		var key := keystone_of(asc)
		if not has_talent(c, key["id"]) or points_in_region(c, asc) < ASC_REGION_POINTS:
			return "Нужно для пути превращения (полный сброс отменит путь)"
	return ""

func refund(c: Dictionary, id: int) -> bool:
	if refund_block(c, id) != "": return false
	if rank(c, id) > 1: c["ranks"][str(id)] = rank(c, id) - 1
	else:
		c["talents"].erase(id)
		c.get("ranks", {}).erase(str(id))
	return true

func reset_talents(c: Dictionary) -> void:
	c["talents"] = [start_node(c["class"])]
	c["ranks"] = {}
	c["ascendancy"] = ""
	c["tree_v"] = TREE_VERSION

## Миграция сохранений со старым деревом: очки возвращаются, путь превращения сохраняется
func migrate_talents(c: Dictionary) -> int:
	if int(c.get("tree_v", 1)) >= TREE_VERSION and c.has("ranks"): return 0
	var old: int = maxi(0, (c.get("talents", []) as Array).size() - 1)
	var asc: String = c.get("ascendancy", "")
	c["talents"] = [start_node(c["class"])]
	c["ranks"] = {}
	c["ascendancy"] = asc
	c["tree_v"] = TREE_VERSION
	if old > 0: c["talent_refund"] = old
	return old

## Описание узла с рангами: текущее значение и следующий ранг
func describe_node(c: Dictionary, id: int) -> String:
	var n: Dictionary = tree_nodes[id]
	var r := rank(c, id)
	var mr := int(n["max_rank"])
	var t := ""
	if n["desc"] != "": t += n["desc"] + "\n"
	var shown := maxi(1, r)
	for m in n["mods"]: t += describe_mod([m[0], float(m[1]) * shown]) + "\n"
	for k in n["fx"]: t += describe_fx(k, float(n["fx"][k]) * shown) + "\n"
	if mr > 1:
		t += "[color=#e6c27a]Ранг %d/%d[/color]" % [r, mr]
		if r > 0 and r < mr:
			t += "  · след.: "
			var parts := []
			for m in n["mods"]: parts.append(describe_mod([m[0], float(m[1]) * (r + 1)]))
			for k in n["fx"]: parts.append(describe_fx(k, float(n["fx"][k]) * (r + 1)))
			t += ", ".join(parts)
		t += "\n"
	return t.strip_edges()

func describe_fx(k: String, v: float) -> String:
	var f: String = FX_NAMES.get(k, k)
	if "%s" in f:
		var vs := str(int(round(v))) if absf(v - round(v)) < 0.01 else ("%.1f" % v)
		return f % vs
	return f

func get_asc(id: String) -> Dictionary:
	for a in ASCENDANCIES:
		if a["id"] == id:
			return a
	return {}

## Возвращает "" если можно превратиться, иначе причину.
func asc_block_reason(c: Dictionary, a: Dictionary) -> String:
	if c["ascendancy"] != "": return "Путь уже выбран (сброс талантов отменит его)"
	if int(c["level"]) < ASC_LEVEL: return "Нужен %d уровень" % ASC_LEVEL
	var key := keystone_of(a["id"])
	if key.is_empty() or not has_talent(c, key["id"]): return "Изучите «%s»" % key.get("name", "?")
	var pts := points_in_region(c, a["id"])
	if pts < ASC_REGION_POINTS: return "Нужно %d очков в регионе (%d)" % [ASC_REGION_POINTS, pts]
	return ""

# ---------------- Умения и набор ----------------
const LOADOUT_SLOTS := 8   # + основная атака = 9 кнопок

## Все активные умения персонажа (без основной атаки): класс + путь превращения
func skill_pool(c: Dictionary) -> Array:
	var out: Array = []
	var cls: Dictionary = CLASSES[c["class"]]
	for i in range(1, cls.skills.size()): out.append(cls.skills[i])
	var a := get_asc(c.get("ascendancy", ""))
	if not a.is_empty():
		out.append(a.skill)
		for x in a.get("skills_extra", []): out.append(x)
	return out

## Все умения всех путей класса (для окна набора: показать будущие)
func skill_pool_all(c: Dictionary) -> Array:
	var out := skill_pool(c)
	return out

func find_skill(c: Dictionary, id: String):
	if id == "": return null
	for s in skill_pool(c):
		if s.id == id: return s
	return null

## "" — умение открыто, иначе причина
func skill_lock(c: Dictionary, s: Dictionary) -> String:
	if s.has("unlock") and int(c["class_level"]) < int(s.unlock): return "Мастерство %d" % int(s.unlock)
	if s.has("lvl") and int(c["level"]) < int(s.lvl): return "Уровень %d" % int(s.lvl)
	return ""

## Привести набор в порядок: убрать недоступные, умение пути — в слот, новые открытые — в пустые слоты
func ensure_loadout(c: Dictionary) -> void:
	var lo: Array = c.get("loadout", [])
	var cls: Dictionary = CLASSES[c["class"]]
	if lo.is_empty():
		lo = [cls.skills[1].id, cls.skills[2].id, "", "", "", "", "", ""]
	while lo.size() < LOADOUT_SLOTS: lo.append("")
	lo.resize(LOADOUT_SLOTS)
	for i in lo.size():
		var s = find_skill(c, str(lo[i]))
		if s == null: lo[i] = ""
	var a := get_asc(c.get("ascendancy", ""))
	if not a.is_empty() and not lo.has(a.skill.id):
		# умение пути — в третий слот (кнопка 3), прежнее умение оттуда — в свободный слот
		if lo[2] != "":
			var free := lo.find("")
			if free >= 0: lo[free] = lo[2]
		lo[2] = a.skill.id
	var auto: Array = c.get("auto_slotted", [])
	for s in skill_pool(c):
		if skill_lock(c, s) == "" and not lo.has(s.id) and not auto.has(s.id):
			var free := lo.find("")
			if free < 0: break
			lo[free] = s.id
			auto.append(s.id)
	c["auto_slotted"] = auto
	c["loadout"] = lo

func set_loadout_slot(c: Dictionary, slot: int, id: String) -> bool:
	ensure_loadout(c)
	var lo: Array = c["loadout"]
	if slot < 0 or slot >= lo.size(): return false
	if id != "":
		var s = find_skill(c, id)
		if s == null or skill_lock(c, s) != "": return false
		var prev := lo.find(id)
		if prev >= 0: lo[prev] = lo[slot]   # меняем местами
	lo[slot] = id
	c["loadout"] = lo
	return true

# ---------------- Персонаж ----------------
static func xp_to_next(level: int) -> int:
	return int(60.0 * pow(level, 1.6))

static func class_xp_to_next(cl: int) -> int:
	return int(100.0 * pow(cl, 1.5))

func new_character(char_name: String, class_id: String, look: Dictionary) -> Dictionary:
	return {
		"version": 2, "id": "%x%x" % [Time.get_ticks_usec(), randi()], "name": char_name, "class": class_id, "look": CharAssets.normalize_look(look),
		"level": 1, "xp": 0, "class_level": 1, "class_xp": 0,
		"talents": [start_node(class_id)], "ranks": {}, "tree_v": TREE_VERSION, "ascendancy": "",
		"gold": 0, "potions": 3, "inventory": [], "equipped": [starter_weapon(class_id)], "stash": [], "dust": 0,
		"zone": "starter", "has_pos": false, "pos": [0, 0, 0], "zones": {},
		"created": Time.get_unix_time_from_system(), "play_time": 0.0, "kills": 0,
	}

func get_equipped(c: Dictionary, slot: int):
	for it in c["equipped"]:
		if int(it["slot"]) == slot:
			return it
	return null

func describe_mod(m: Array) -> String:
	var stat: String = m[0]
	var v: float = m[1]
	var vs := str(int(round(v))) if absf(v - round(v)) < 0.01 else ("%.1f" % v)
	return ("+" if v >= 0 else "") + vs + " " + STAT_NAMES.get(stat, stat)

## Итоговые характеристики: класс + уровень + таланты + путь + снаряжение.
func compute_stats(c: Dictionary) -> Dictionary:
	var raw := {}
	var add := func(mods):
		for m in mods:
			raw[m[0]] = raw.get(m[0], 0.0) + float(m[1])
	var fx := {}
	for id in c["talents"]:
		if tree_nodes.has(int(id)):
			var n: Dictionary = tree_nodes[int(id)]
			var r := rank(c, int(id))
			for m in n["mods"]: raw[m[0]] = raw.get(m[0], 0.0) + float(m[1]) * r
			for k in n["fx"]: fx[k] = float(fx.get(k, 0.0)) + float(n["fx"][k]) * r
	var asc := get_asc(c["ascendancy"])
	if not asc.is_empty():
		add.call(asc["mods"])
	var weapon_dmg := 0.0
	var item_armor := 0.0
	for it in c["equipped"]:
		if Items.equip_block(c, it) != "": continue   # требование уровня/класса — строго
		add.call(it["mods"])
		if int(it["slot"]) == 0: weapon_dmg += float(it["base"])
		else: item_armor += float(it["base"])
	var sb := Items.set_bonuses(c)
	add.call(sb.mods)
	for k in sb.fx: fx[k] = float(fx.get(k, 0.0)) + float(sb.fx[k])
	raw["dmg%"] = raw.get("dmg%", 0.0) + (int(c["class_level"]) - 1) * 3.0
	var g := func(k): return raw.get(k, 0.0)
	var cls: Dictionary = CLASSES[c["class"]]
	var L := int(c["level"]) - 1
	var s := {}
	s.max_hp = (cls.hp + cls.hp_lvl * L + g.call("hp")) * (1 + g.call("hp%") / 100.0)
	s.max_mp = (cls.mp + cls.mp_lvl * L + g.call("mp")) * (1 + g.call("mp%") / 100.0)
	s.damage = cls.dmg + cls.dmg_lvl * L + weapon_dmg + g.call("dmg")
	s.dmg_mult = 1 + g.call("dmg%") / 100.0
	s.spell_mult = 1 + g.call("spell%") / 100.0
	s.attack_speed = maxf(0.3, 1 + g.call("as%") / 100.0)
	s.move_speed = 5.2 * clampf(1 + g.call("ms%") / 100.0, 0.5, 2.0)
	s.crit = clampf(5 + g.call("crit"), 0, 80) / 100.0
	s.crit_mult = 1.5 + g.call("critdmg%") / 100.0
	s.armor = maxf(0, (5 + item_armor + g.call("armor")) * (1 + g.call("armor%") / 100.0))
	s.regen = 0.5 + g.call("regen")
	s.mp_regen = 2.0 + g.call("mpregen")
	s.leech = g.call("leech%") / 100.0
	s.cdr = clampf(g.call("cdr%"), 0, 50) / 100.0
	s.dr = s.armor / (s.armor + 120.0) * 0.8 + g.call("dr%") / 100.0
	s.pen = clampf(g.call("pen%") + float(cls.get("pen", 0.0)), 0, Combat.PEN_CAP)   # воин: врождённое пробивание брони
	s.resred = maxf(0.0, g.call("resred"))
	if fx.has("leech_x"): s.leech *= 2.0
	if fx.has("no_regen"): s.regen = 0.0
	s.fx = fx
	return s

# ---------------- Добыча ----------------
const ARMOR_BASES := ["Кожаная куртка", "Кольчуга", "Латный доспех"]
const HELM_BASES := ["Капюшон", "Железный шлем", "Рогатый шлем"]
const RING_BASES := ["Медное кольцо", "Серебряное кольцо", "Кольцо с рубином"]
const PREFIXES := ["Острый", "Крепкий", "Быстрый", "Древний", "Пылающий", "Ледяной", "Кровавый", "Святой", "Теневой"]
const UNIQUES := ["Клык Тролля", "Сердце долины", "Пепельный венец", "Шёпот бури"]
const AFFIXES := [["hp",10,40],["mp",10,35],["dmg%",4,15],["as%",3,10],["ms%",2,8],["crit",1,5],
	["critdmg%",8,25],["armor",8,30],["regen",0.5,2.5],["spell%",5,16],["leech%",0.3,1.5],["cdr%",2,6],["pen%",4,12],["resred",3,10]]

func weapon_base(class_id: String, tier: int) -> String:
	match class_id:
		"archer": return ["Короткий лук", "Длинный лук", "Составной лук"][tier]
		"mage": return ["Посох", "Жезл чародея", "Посох архимага"][tier]
	return ["Меч", "Боевой топор", "Двуручный клинок"][tier]

func starter_weapon(class_id: String) -> Dictionary:
	return {"uid": str(randi()), "name": CLASSES[class_id].weapon, "slot": 0, "rarity": 0, "ilvl": 1, "base": 3.0, "mods": [],
		"type": Items.CLASS_WEAPON[class_id][0], "cls": class_id, "req": 1}

## Предмет под свой класс (торговец, тесты). Добыча с врагов — Items.drop_items (для всех классов)
func roll_item(ilvl: int, class_id: String, rarity_bonus := 0.0, slot := -1) -> Dictionary:
	return Items.roll(ilvl, class_id, rarity_bonus, false, slot)

## Уникальные предметы Хранителя Эфира (подземелье): у каждого класса свой, плюс общий перстень
const WARDEN_UNIQUES := {
	"warrior": {"name": "Клинок Хранителя", "slot": 0, "mods": [["dmg%", 22], ["hp%", 10], ["leech%", 1.5], ["armor", 30]]},
	"archer": {"name": "Лук Пустоты", "slot": 0, "mods": [["dmg%", 20], ["as%", 12], ["crit", 6], ["critdmg%", 25]]},
	"mage": {"name": "Посох Сжатого Эфира", "slot": 0, "mods": [["spell%", 26], ["mp", 40], ["cdr%", 8], ["mpregen", 2]]},
	"ring": {"name": "Печать Хранителя", "slot": 3, "mods": [["hp", 60], ["dmg%", 10], ["ms%", 6], ["regen", 3]]},
}
func warden_unique(key: String, ilvl: int) -> Dictionary:
	var u: Dictionary = WARDEN_UNIQUES[key]
	var it := {"uid": str(randi()), "name": u.name, "slot": u.slot, "rarity": 3, "ilvl": ilvl, "unique": "warden_" + key, "mods": []}
	var k := 1.0 + ilvl * 0.05
	for m in u.mods: it.mods.append([m[0], round(float(m[1]) * k * 10.0) / 10.0])
	it.base = round((3 + ilvl * 1.6) * 1.5) if u.slot == 0 else 0.0
	it["type"] = Items.CLASS_WEAPON[key][0] if u.slot == 0 else "ring"
	it["cls"] = key if u.slot == 0 else ""
	it["req"] = Items.req_level(ilvl)
	return it

## Флаг зоны (например, «босс повержен»)
func zone_flag(c: Dictionary, zone_id: String, flag: String) -> bool:
	return c.get("zones", {}).get(zone_id, {}).get("flags", []).has(flag)

func set_zone_flag(c: Dictionary, zone_id: String, flag: String) -> void:
	if not c.has("zones"): c["zones"] = {}
	var zs: Dictionary = c["zones"].get(zone_id, {"flags": []})
	if not zs.has("flags"): zs["flags"] = []
	if not zs["flags"].has(flag): zs["flags"].append(flag)
	c["zones"][zone_id] = zs

## Открыта ли зона для персонажа: "" — да, иначе причина
func zone_lock_reason(c: Dictionary, zone_id: String) -> String:
	var z: Dictionary = ZONES.get(zone_id, {})
	if z.is_empty() or not z["available"]: return "Путь откроется в следующих версиях"
	if int(c["level"]) < int(z["min_level"]): return "Нужен %d уровень" % z["min_level"]
	var req: Array = z.get("requires", [])
	if req.size() == 2 and not zone_flag(c, req[0], req[1]): return "Печать держится. Победите Древнего тролля"
	return ""

func describe_item(it: Dictionary) -> String:
	var s := "%s · %s · ур. %d\n" % [SLOT_NAMES[int(it.slot)], RARITY_NAMES[int(it.rarity)], int(it.ilvl)]
	if int(it.slot) == 0: s += "Урон: +%d\n" % int(it.base)
	elif float(it.base) > 0: s += "Броня: +%d\n" % int(it.base)
	for m in it.mods:
		s += describe_mod(m) + "\n"
	return s.strip_edges()

func sell_price(it: Dictionary) -> int:
	return 5 + int(it.ilvl) * 3 * (int(it.rarity) + 1)

# ---------------- Торговец ----------------
const RARITY_PRICE := [1.0, 2.2, 4.5, 9.0, 6.0]
const BUYBACK_SIZE := 10
func buy_price(it: Dictionary) -> int:
	return int(round((20 + int(it.ilvl) * 9) * RARITY_PRICE[int(it.rarity)]))

func potion_price(level: int) -> int:
	return 15 + level * 3

## Товары торговца: 6 предметов под уровень героя, редкость растёт с уровнем
func shop_stock(level: int, class_id: String) -> Array:
	var out := []
	var bonus := clampf(0.08 + level * 0.015, 0.0, 0.35)
	var names := {}
	var slots := [0, 1, 2, randi_range(3, 7), randi_range(3, 7), randi_range(0, 7)]
	for i in 6:
		var it := {}
		for guard in 30:
			var ilvl := maxi(1, level + randi_range(-1, 1))
			it = roll_item(ilvl, class_id, bonus, slots[i])
			if it.rarity == 3: continue  # уникальные — только с босса
			if names.has(it.name) and guard < 28: continue
			break
		names[it.name] = true
		out.append(it)
	return out

## Покупка/продажа (возвращают пустую строку при успехе, иначе причину)
func shop_buy(c: Dictionary, idx: int) -> String:
	var stock: Array = c["shop"]["stock"]
	if idx < 0 or idx >= stock.size(): return "Нет товара"
	var it: Dictionary = stock[idx]
	var price := buy_price(it)
	if int(c["gold"]) < price: return "Не хватает золота"
	if c["inventory"].size() >= INVENTORY_SIZE: return "Инвентарь полон"
	c["gold"] = int(c["gold"]) - price
	c["inventory"].append(it)
	stock.remove_at(idx)
	return ""

func shop_buy_potion(c: Dictionary, n := 1) -> String:
	var price := potion_price(int(c["level"])) * n
	if int(c["gold"]) < price: return "Не хватает золота"
	c["gold"] = int(c["gold"]) - price
	c["potions"] = int(c["potions"]) + n
	return ""

func shop_sell(c: Dictionary, idx: int) -> String:
	var inv: Array = c["inventory"]
	if idx < 0 or idx >= inv.size(): return "Нет предмета"
	var it: Dictionary = inv[idx]
	inv.remove_at(idx)
	c["gold"] = int(c["gold"]) + sell_price(it)
	var bb: Array = c["buyback"]
	bb.push_front(it)
	while bb.size() > BUYBACK_SIZE: bb.pop_back()
	return ""

func shop_buyback(c: Dictionary, idx: int) -> String:
	var bb: Array = c["buyback"]
	if idx < 0 or idx >= bb.size(): return "Нет предмета"
	var it: Dictionary = bb[idx]
	var price := sell_price(it)
	if int(c["gold"]) < price: return "Не хватает золота"
	if c["inventory"].size() >= INVENTORY_SIZE: return "Инвентарь полон"
	c["gold"] = int(c["gold"]) - price
	c["inventory"].append(it)
	bb.remove_at(idx)
	return ""

func shop_restock_price(level: int) -> int:
	return 10 + level * 4

func shop_ensure(c: Dictionary) -> void:
	if not c.has("buyback"): c["buyback"] = []
	if not c.has("shop") or int(c["shop"].get("level", -1)) != int(c["level"]):
		c["shop"] = {"level": int(c["level"]), "stock": shop_stock(int(c["level"]), c["class"])}
