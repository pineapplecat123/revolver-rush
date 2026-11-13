class_name FireResolver
## 整匣射击：按表计算每发基础伤害。

const ID_WHITE := 1
const ID_GOLD := 8
const ID_WRATH := 16  ## 愤怒
const ID_PRIDE := 17  ## 傲慢
const ID_GREED := 18  ## 贪婪
const ID_TOMBSTONE := 19  ## 墓碑（设计表编号9）
const ID_GHOST := 20  ## 幽灵（设计表编号10，墓碑衍生物）
const ID_ARMOR_PIERCE := 22  ## 穿甲（设计表编号12）
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
const ID_QISHI := CombatConstants.QISHI_AMMO_ID
const ID_XULI := CombatConstants.XULI_AMMO_ID
const ID_DIZENG := CombatConstants.DIZENG_AMMO_ID
const ID_ZHONGSHEN := CombatConstants.ZHONGSHEN_AMMO_ID
const XULI_MULT := 1.5
const QISHI_BONUS := 0.1


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
		ID_QISHI, ID_XULI, ID_ZHONGSHEN:
			return 0
		ID_DIZENG:
			return 3
		_:
			var def: Dictionary = DataRegistry.get_ammo(ammo_id)
			if def.get("base_damage", null) != null:
				return int(def["base_damage"])
			return 0


static func round_damage(value: float) -> int:
	## 内部用 float 算；落到敌人/飘字时四舍五入（.5 远离 0）。
	return int(round(value))


static func type_tag(ammo_id: int) -> String:
	## 弹药的开始/中间/结束标签；无则空串。按 tags 读取，不写死 id。
	var tags = DataRegistry.get_ammo(ammo_id).get("tags", [])
	if tags is Array:
		var found: Dictionary = {}
		for t in tags:
			found[str(t).strip_edges()] = true
		for name in ["开始", "中间", "结束"]:
			if found.has(name):
				return name
	return ""


static func is_start_type(ammo_id: int) -> bool:
	return type_tag(ammo_id) == "开始"


static func load_type_rank(ammo_id: int) -> int:
	## 自动装填优先级：开始 0、中间 1、结束 2、无标签 3。
	var tag := type_tag(ammo_id)
	if tag == "开始":
		return 0
	if tag == "中间":
		return 1
	if tag == "结束":
		return 2
	return 3


static func compute_volley_damages(order: Array[int]) -> Array[float]:
	## 按连射顺序算每格「计算伤害」（空仓为 0）。起势加法叠层，蓄力连乘挂起，
	## 递增按 1 起槽位（空仓也占格），终审为此前计算伤害之和的一半。
	## 最终伤害 = 基础或公式 × (1 + 0.1×此前起势数) × 待消耗蓄力倍率。
	## 「开始」类型子弹互不影响：起势加成与蓄力倍率都不作用在开始弹上；
	## 蓄力倍率穿过开始弹与空仓，由下一发非开始弹消耗。
	var qishi := 0
	var xuli := 1.0
	var prior := 0.0
	var slot := 0
	var out: Array[float] = []
	for ammo_id in order:
		slot += 1
		if ammo_id == Magazine.EMPTY:
			out.append(0.0)
			continue
		var base := _formula_base(ammo_id, slot, prior)
		var start := is_start_type(ammo_id)
		var qishi_mult: float = 1.0 if start else (1.0 + QISHI_BONUS * float(qishi))
		var pending: float = 1.0 if start else xuli
		var dmg: float = base * qishi_mult * pending
		if ammo_id == ID_XULI:
			xuli *= XULI_MULT
		elif not start:
			xuli = 1.0
		if ammo_id == ID_QISHI:
			qishi += 1
		prior += dmg
		out.append(dmg)
	return out


static func _formula_base(ammo_id: int, slot: int, prior_computed: float) -> float:
	match ammo_id:
		ID_QISHI, ID_XULI:
			return 0.0
		ID_DIZENG:
			return 3.0 + float(slot) * 0.5
		ID_ZHONGSHEN:
			return prior_computed * 0.5
		_:
			return float(base_damage_for(ammo_id, [], 0))


static func compute_shot_damages(order: Array[int]) -> Array[int]:
	var floats: Array[float] = compute_volley_damages(order)
	var out: Array[int] = []
	for v in floats:
		out.append(round_damage(v))
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
