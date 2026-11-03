class_name FireResolver
## 整匣射击：按表计算每发基础伤害。

const ID_WHITE := 1
const ID_GOLD := 8
const ID_WRATH := 16  ## 愤怒
const ID_PRIDE := 17  ## 傲慢
const ID_GREED := 18  ## 贪婪
const ID_TOMBSTONE := 19  ## 墓碑（设计表编号9）
const ID_GHOST := 20  ## 幽灵（设计表编号10，墓碑衍生物）
const ID_SUPER_ROUND := 21  ## 兼容旧名；v0.4.0 起为「连发子弹」
const ID_BURST := 21  ## 连发子弹（原超级回合）
const ID_ARMOR_PIERCE := 22  ## 穿甲（设计表编号12）
const ID_DUMP := 23  ## 倾泻
const ID_ECHO := 24  ## 回声（设计表编号21）
const ID_LIFESTEAL := 25  ## 吸血（设计表编号22）
const ID_FLAME := 26  ## 火焰（设计表编号17）
const ID_EXPLOSIVE := 27  ## 炸药（设计表编号18）
const ID_SCATTER := 28  ## 散射（设计表编号15）
const ID_INSURANCE := 29  ## 保险（设计表编号16）
const ID_FOCUS := 30  ## 聚能（设计表编号19）
const ID_STONE := 31  ## 石头（设计表编号13）
const ID_PEBBLE := 32  ## 小石头（设计表编号14）
const ID_JUSTICE := 33  ## 正义（设计表编号20）
const ID_LUST := 34  ## 色欲
const ID_ENVY := 35  ## 嫉妒
const ID_GLUTTONY := 36  ## 暴食
const ID_SLOTH := 37  ## 懒惰


static func count_by_id(order: Array[int]) -> Dictionary:
	var c := {}
	for id in order:
		c[id] = int(c.get(id, 0)) + 1
	return c


static func base_damage_for(ammo_id: int, _order: Array[int], _index: int) -> int:
	match ammo_id:
		ID_WHITE:
			return 3
		ID_GOLD:
			return 3
		ID_WRATH:
			return 3
		ID_PRIDE, ID_GREED:
			return 2
		ID_TOMBSTONE, ID_GHOST:
			return 2
		ID_SUPER_ROUND, ID_BURST:
			return 1
		ID_DUMP:
			return 2
		ID_ARMOR_PIERCE:
			return 3
		ID_ECHO:
			return 1
		ID_LIFESTEAL:
			return 1
		ID_FLAME:
			return 1
		ID_EXPLOSIVE:
			return 1
		ID_SCATTER:
			return 5
		ID_INSURANCE:
			return 1
		ID_FOCUS:
			return 3
		ID_STONE:
			return 3
		ID_PEBBLE:
			return 1
		ID_JUSTICE:
			return 3
		ID_LUST, ID_ENVY, ID_GLUTTONY, ID_SLOTH:
			return 2
		_:
			return 0


static func compute_shot_damages(order: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for i in order.size():
		out.append(base_damage_for(order[i], order, i))
	return out


static func inherits_from(ammo_id: int) -> Dictionary:
	## 该发自带的状态效果旗标（击发后挂上枪口，后续击发都附带）。
	## 旧色弹与旧穿透/汽油/火/水/雷子弹已删除；枪口种类仍由在役弹挂上。
	return {
		"pierce": ammo_id == ID_ARMOR_PIERCE,
		"gas": false,
		"fire": ammo_id == ID_FLAME,
		"water": false,
		"thunder": false,
		"wrath": ammo_id == ID_WRATH,
		"pride": ammo_id == ID_PRIDE,
		"greed": ammo_id == ID_GREED,
		"lust": ammo_id == ID_LUST,
		"envy": ammo_id == ID_ENVY,
		"gluttony": ammo_id == ID_GLUTTONY,
		"sloth": ammo_id == ID_SLOTH,
		"echo": ammo_id == ID_ECHO,
		"lifesteal": ammo_id == ID_LIFESTEAL,
		"explosive": ammo_id == ID_EXPLOSIVE,
	}
