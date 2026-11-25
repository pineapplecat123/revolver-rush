class_name EnemyInstance
## 场上敌人运行时实例（汽油/燃烧/湿/流血）。

var def_id: int = 0
var name_zh: String = ""
var max_hp: int = 0
var hp: int = 0
var atk: int = 0
var mobility: int = 1
var tags: Array[String] = []
var cell: int = CombatConstants.BOARD_SIZE - 1
var bleed_stacks: int = 0
## 距下次流血跳伤的剩余战斗秒。0 且未流血 = 未计时；刚挂上时设为 DOT_TICK_SEC。
var bleed_tick_left: float = 0.0
var gas_stacks: int = 0
var burn_stacks: int = 0
var wet_stacks: int = 0
## 色欲：混乱剩余秒；>0 时攻击邻近怪物而非玩家。
var confuse_remaining: float = 0.0
## 混乱本次时长（环形倒计时的满圈）。
var confuse_total: float = 0.0
## 懒惰：减速层剩余秒（每层独立）；层数=减速强度。
var slow_layers: Array = []
## 与 slow_layers 同序的该层初始秒数。
var slow_layer_totals: Array = []
## 燃烧/流血层数峰值，用来画「还剩多久」的环（层数掉下去环就缩短）。
var burn_peak: int = 0
var bleed_peak: int = 0
## 减速跳格计数（层数越高越常跳过移动）。
var slow_skip: int = 0
## 攻击距离（格）；1=仅邻接。精英/Boss 灰盒可抬高。
var attack_range: int = 1
## 沙盒木桩：不移动、不攻击。
var is_dummy: bool = false
## v0.4.28 自由行走（UI 实战）：连续位置（格为单位）、个体速度倍率、本帧是否在走。
var pos_x: float = -999.0
var speed_mul: float = 1.0
var walking: bool = false
## v0.4.20 沙盒统计：本个体累计挨了多少伤害（清零时归 0）。
var dmg_taken_total: int = 0


func _init(def: Dictionary = {}, spawn_cell: int = CombatConstants.BOARD_SIZE - 1) -> void:
	if def.is_empty():
		return
	def_id = int(def.get("id", 0))
	name_zh = str(def.get("name", ""))
	max_hp = int(def.get("hp", 1))
	hp = max_hp
	atk = int(def.get("atk", 1))
	mobility = int(def.get("mobility", 1))
	tags.clear()
	for t in def.get("tags", []):
		tags.append(str(t))
	cell = spawn_cell
	bleed_stacks = 0
	bleed_tick_left = 0.0
	gas_stacks = 0
	burn_stacks = 0
	wet_stacks = 0
	confuse_remaining = 0.0
	confuse_total = 0.0
	slow_layers.clear()
	slow_layer_totals.clear()
	burn_peak = 0
	bleed_peak = 0
	slow_skip = 0
	attack_range = 1
	is_dummy = bool(def.get("dummy", false)) or ("木桩" in tags)
	if is_dummy:
		mobility = 0
		atk = 0
		attack_range = 0


func is_alive() -> bool:
	return hp > 0


func revive_to_full() -> void:
	## 沙盒木桩死后恢复：满血并清掉状态，仍停在原格。
	hp = max_hp
	clear_bleed()
	gas_stacks = 0
	burn_stacks = 0
	wet_stacks = 0
	confuse_remaining = 0.0
	confuse_total = 0.0
	clear_slow_layers()
	burn_peak = 0
	bleed_peak = 0
	if is_dummy:
		mobility = 0
		atk = 0
		attack_range = 0


func has_tag(tag: String) -> bool:
	return tag in tags


## 纯扣血（石头 <4 无视）。不触发击中特效。
func apply_damage(raw_damage: int) -> int:
	if not is_alive():
		return 0
	var dmg := raw_damage
	if has_tag("石头") and dmg < 4:
		dmg = 0
	if dmg <= 0:
		return 0
	hp = maxi(0, hp - dmg)
	return dmg


## 子弹/攻击命中：实际掉血后，血肉生物（含僵尸）挂上永久流血；不叠层、不重置跳表。
func apply_hit(raw_damage: int) -> int:
	var dealt := apply_damage(raw_damage)
	if dealt > 0 and can_receive_bleed():
		start_permanent_bleed()
	return dealt


func can_receive_bleed() -> bool:
	## 僵尸也是主线血肉怪物，不能因旧表缺少【生物】标签而漏挂。
	## 保留明确非血肉对象（骷髅、石头、木桩）的既有免疫。
	return (has_tag("生物") or has_tag("僵尸")) and not has_tag("骷髅")


func is_bleeding() -> bool:
	return bleed_stacks > 0 and is_alive()


func start_permanent_bleed() -> void:
	## 首次挂上：层数视为 1，0.7s 后第一次跳伤。重复命中不叠层、不推迟、不重启跳表。
	if bleed_stacks <= 0:
		bleed_stacks = 1
		bleed_tick_left = CombatConstants.DOT_TICK_SEC
		bleed_peak = 1
		return
	bleed_stacks = 1
	if bleed_tick_left <= 0.0:
		bleed_tick_left = CombatConstants.DOT_TICK_SEC


func clear_bleed() -> void:
	bleed_stacks = 0
	bleed_tick_left = 0.0
	bleed_peak = 0


func arm_bleed_from_sandbox(stacks: int) -> void:
	## 沙盒直接改层数：>0 视为永久流血；若原先没有计时，从满一跳开始，避免当场跳伤。
	var n: int = maxi(0, stacks)
	if n <= 0:
		clear_bleed()
		return
	var was: bool = bleed_stacks > 0 and bleed_tick_left > 0.0
	bleed_stacks = 1
	bleed_peak = 1
	if not was:
		bleed_tick_left = CombatConstants.DOT_TICK_SEC


func status_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if gas_stacks > 0:
		parts.append("油%d" % gas_stacks)
	if burn_stacks > 0:
		parts.append("燃%d" % burn_stacks)
	if wet_stacks > 0:
		parts.append("湿%d" % wet_stacks)
	if bleed_stacks > 0:
		parts.append("血")
	if confuse_remaining > 0.0:
		parts.append("乱%.1f" % confuse_remaining)
	if not slow_layers.is_empty():
		parts.append("缓%d" % slow_layers.size())
	return " ".join(parts)


func slow_stacks() -> int:
	return slow_layers.size()


func apply_confuse(sec: float) -> void:
	## 混乱可刷新为更长剩余（不叠加时长叠乘，取较大值）。
	if sec > confuse_remaining:
		confuse_remaining = sec
		confuse_total = sec


func set_confuse_remaining(sec: float) -> void:
	## 沙盒直接改剩余：环从满圈开始倒。
	confuse_remaining = maxf(0.0, sec)
	confuse_total = confuse_remaining


func add_slow_layer(sec: float) -> void:
	var s := maxf(0.0, sec)
	slow_layers.append(s)
	slow_layer_totals.append(maxf(s, 0.01))


func clear_slow_layers() -> void:
	slow_layers.clear()
	slow_layer_totals.clear()


func tick_status_timers(delta_sec: float) -> void:
	if delta_sec <= 0.0:
		return
	if confuse_remaining > 0.0:
		confuse_remaining = maxf(0.0, confuse_remaining - delta_sec)
		if confuse_remaining <= 0.0:
			confuse_total = 0.0
	var i := 0
	while i < slow_layers.size():
		var left: float = maxf(0.0, float(slow_layers[i]) - delta_sec)
		if left <= 0.0:
			slow_layers.remove_at(i)
			if i < slow_layer_totals.size():
				slow_layer_totals.remove_at(i)
		else:
			slow_layers[i] = left
			i += 1


func _sync_stack_peaks() -> void:
	if burn_stacks <= 0:
		burn_peak = 0
	elif burn_stacks > burn_peak:
		burn_peak = burn_stacks
	if bleed_stacks <= 0:
		bleed_peak = 0
	elif bleed_stacks > bleed_peak:
		bleed_peak = bleed_stacks


func _decay_ring(stacks: int, peak: int, dot_left: float) -> Dictionary:
	## 层数每 DOT_TICK_SEC 掉 1。dot_left<0 时按当前层还满一跳来估。
	var tick: float = CombatConstants.DOT_TICK_SEC
	var into: float = tick if dot_left < 0.0 else clampf(dot_left, 0.0, tick)
	var remaining: float = float(maxi(stacks - 1, 0)) * tick + into
	var total: float = float(maxi(peak, stacks)) * tick
	total = maxf(total, remaining)
	var ratio: float = 0.0 if total <= 0.0 else clampf(remaining / total, 0.0, 1.0)
	return {"remaining": remaining, "total": total, "ratio": ratio}


func status_ring_entries(dot_left: float = -1.0) -> Array:
	## 头顶小环：燃烧/流血按剩余层数折成时间；混乱/减速按剩余秒；油/湿不消退，环保持满圈。
	_sync_stack_peaks()
	var out: Array = []
	if burn_stacks > 0:
		var b := _decay_ring(burn_stacks, burn_peak, dot_left)
		b["id"] = "burn"
		b["label"] = "燃"
		b["stacks"] = burn_stacks
		b["timed"] = true
		b["color"] = Color(1.0, 0.45, 0.12)
		out.append(b)
	# 流血改为永久 buff，倒计时环不再展示；血条旁图标见 SkeletonEnemy。
	if gas_stacks > 0:
		out.append({
			"id": "gas", "label": "油", "stacks": gas_stacks,
			"remaining": -1.0, "total": -1.0, "ratio": 1.0, "timed": false,
			"color": Color(0.75, 0.95, 0.35),
		})
	if wet_stacks > 0:
		out.append({
			"id": "wet", "label": "湿", "stacks": wet_stacks,
			"remaining": -1.0, "total": -1.0, "ratio": 1.0, "timed": false,
			"color": Color(0.35, 0.78, 1.0),
		})
	if confuse_remaining > 0.0:
		if confuse_total < confuse_remaining:
			confuse_total = confuse_remaining
		var total_c: float = maxf(confuse_total, 0.01)
		out.append({
			"id": "confuse", "label": "乱", "stacks": 1,
			"remaining": confuse_remaining, "total": total_c,
			"ratio": clampf(confuse_remaining / total_c, 0.0, 1.0),
			"timed": true, "color": Color(0.95, 0.45, 0.9),
		})
	if not slow_layers.is_empty():
		var best_i := 0
		var best := 0.0
		for si in slow_layers.size():
			if float(slow_layers[si]) > best:
				best = float(slow_layers[si])
				best_i = si
		var total_s: float = best
		if best_i < slow_layer_totals.size():
			total_s = maxf(float(slow_layer_totals[best_i]), best)
		total_s = maxf(total_s, 0.01)
		out.append({
			"id": "slow", "label": "缓", "stacks": slow_layers.size(),
			"remaining": best, "total": total_s,
			"ratio": clampf(best / total_s, 0.0, 1.0),
			"timed": true, "color": Color(0.55, 0.62, 1.0),
		})
	return out
