extends GutTest
## v0.4.19 厨房水槽伤害研究：全战斗弹药 × 数量 × 关键对 × 混装采样 → tools/_kitchensink_damage.json

const REPORT_PATH := "res://tools/_kitchensink_damage.json"
const DUMMY_HP := 999999
const WHITE := CombatConstants.WHITE_AMMO_ID

var _solo: Array = []
var _counts: Array = []
var _pairs: Array = []
var _mixed: Array = []
var _exclusions: Array = []
var _method_notes: Array = []


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func test_kitchensink_damage_study() -> void:
	_method_notes.append("脚本化 CombatState.start_sandbox + 木桩；无 UI。伤害=木桩总 HP 掉量（多怪取 sum）。")
	_method_notes.append("平庸基线：单发3；满匣6白=18。lift=场景总伤−等价白弹基线。")
	_method_notes.append("倾泻用 fire_tap(true) 同步打完；连发窗在窗口内尽量点射（每点间隔 = 射速帽）。")
	_method_notes.append("禁用旧色弹/穿透/汽油等 enabled_in_combat=false 未入测。")
	_collect_exclusions()
	_run_solo_ladder()
	_run_count_ladder()
	_run_key_pairs()
	_run_mixed_bags()
	_write_report()
	assert_gt(_solo.size(), 15, "solo rows")
	assert_true(FileAccess.file_exists(REPORT_PATH), "report written")


func _collect_exclusions() -> void:
	for it in DataRegistry.all_ammo():
		if not bool(it.get("enabled_in_combat", true)):
			_exclusions.append({"id": int(it.get("id", 0)), "name": str(it.get("name", "?"))})


func _fresh(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_sandbox(seed_v, FireResolver.ID_WRATH)
	cs.dev_clear_bag()
	cs.discard.clear()
	cs.discard_temp.clear()
	cs.sandbox_clear_enemies()
	cs.sandbox_clear_muzzle()
	cs.justice_damage_bonus = 0
	cs.gold = 20
	cs.player_hp = CombatConstants.PLAYER_MAX_HP
	cs.auto_enemy_advance = false
	return cs


func _dummy(cs: CombatState, cell: int = 3, hp: int = DUMMY_HP) -> EnemyInstance:
	return cs.sandbox_spawn_dummy(hp, cell)


func _sum_hp(cs: CombatState) -> int:
	var s := 0
	for e in cs.enemies:
		s += e.hp
	return s


func _force_slots(cs: CombatState, ids: Array) -> void:
	var six: Array[int] = []
	for i in 6:
		if i < ids.size():
			six.append(int(ids[i]))
		else:
			six.append(Magazine.EMPTY)
	cs.dev_force_load(six)
	cs.magazine.set_start(0)


func _fire_empty_cylinder(cs: CombatState, max_ops: int = 40) -> Dictionary:
	## 清空当前弹匣：倾泻同步；连发窗尽量点；其它逐发。返回 {dealt, shots, ops, gold_spent, heal}
	var hp0 := _sum_hp(cs)
	var gold0 := cs.gold
	var hp_player0 := cs.player_hp
	var shots := 0
	var ops := 0
	var guard := max_ops
	while guard > 0 and cs.magazine != null and not cs.magazine.is_empty():
		guard -= 1
		ops += 1
		var before_loaded := cs.magazine.loaded_count()
		cs.player_fire_gate_remaining = 0.0
		var results: Array = cs.fire_tap(true)
		shots += maxi(results.size(), 1)
		# 连发窗：窗口内继续点免费平庸
		var burst_guard := 24
		while cs.burst_window_remaining > 0.0 and burst_guard > 0:
			burst_guard -= 1
			cs.tick_combat_time(CombatConstants.MIN_FIRE_INTERVAL_SEC)
			if cs.burst_window_remaining <= 0.0:
				break
			ops += 1
			var br: Array = cs.fire_tap(true)
			shots += maxi(br.size(), 1)
		# 若匣未空且没倾泻/窗，继续
		if cs.magazine.is_empty():
			break
		if before_loaded == cs.magazine.loaded_count() and results.is_empty():
			# 卡住则强制推进一发
			if cs.begin_fire():
				cs.fire_next_shot()
				if cs.has_paced_shot_pending():
					cs.finalize_paced_shot()
				if cs.post_fire_enemy_pending():
					cs._post_fire_enemy_pending = false
				shots += 1
			else:
				break
	var dealt := hp0 - _sum_hp(cs)
	return {
		"dealt": dealt,
		"shots": shots,
		"ops": ops,
		"gold_spent": gold0 - cs.gold,
		"heal": cs.player_hp - hp_player0,
		"dps_proxy": float(dealt) / float(maxi(ops, 1)),
	}


func _ammo_name(id: int) -> String:
	var it = DataRegistry.get_ammo(id)
	if it == null:
		return str(id)
	return str(it.get("name", str(id)))


func _rarity(id: int) -> String:
	var it = DataRegistry.get_ammo(id)
	if it == null:
		return "?"
	return str(it.get("rarity", "?"))


## ——— 单发阶梯：每种战斗弹药在 1 槽位射击一次 ———
func _run_solo_ladder() -> void:
	var combat_ids: Array = _combat_ammo_ids()
	# 平庸基线
	var base := _measure_cylinder([WHITE], "solo_white_1")
	_solo.append({
		"id": WHITE, "name": "平庸弹药", "rarity": "common", "copies": 1,
		"dealt": int(base["dealt"]), "shots": int(base["shots"]), "ops": int(base["ops"]),
		"dps_proxy": float(base["dps_proxy"]), "lift_vs_white": 0,
		"scenario": "solo_1", "note": "基线单发",
	})
	for aid in combat_ids:
		if int(aid) == WHITE:
			continue
		# 特殊：幽灵单独打；墓碑无幽灵时只测自身
		var res := _measure_cylinder([int(aid)], "solo_%d" % int(aid))
		var lift := int(res["dealt"]) - int(base["dealt"])
		_solo.append({
			"id": int(aid), "name": _ammo_name(int(aid)), "rarity": _rarity(int(aid)),
			"copies": 1, "dealt": int(res["dealt"]), "shots": int(res["shots"]),
			"ops": int(res["ops"]), "dps_proxy": float(res["dps_proxy"]),
			"lift_vs_white": lift, "scenario": "solo_1",
			"note": "单槽射击", "gold_spent": int(res.get("gold_spent", 0)),
			"heal": int(res.get("heal", 0)),
		})


func _measure_cylinder(ids: Array, seed_tag: String) -> Dictionary:
	var seed_v := int(hash(seed_tag) % 100000) + 50000
	var cs := _fresh(seed_v)
	_dummy(cs)
	# 多目标场景给散射/炸药一点空间：再补 2 木桩
	if ids.has(FireResolver.ID_SCATTER) or ids.has(FireResolver.ID_EXPLOSIVE) or ids.has(FireResolver.ID_ARMOR_PIERCE):
		cs.sandbox_spawn_dummy(DUMMY_HP, 2)
		cs.sandbox_spawn_dummy(DUMMY_HP, 4)
	# 墓碑：袋里塞幽灵以便显现真实爆发（若测墓碑本身）
	if ids.has(FireResolver.ID_TOMBSTONE) and not ids.has(FireResolver.ID_GHOST):
		cs.sandbox_add_ammo(FireResolver.ID_GHOST, 4, CombatConstants.GHOST_TTL_SEC)
	# 金币：固定金池
	if ids.has(FireResolver.ID_GOLD):
		cs.gold = 20
	_force_slots(cs, ids)
	return _fire_empty_cylinder(cs)


func _combat_ammo_ids() -> Array:
	var out: Array = []
	for it in DataRegistry.all_ammo():
		if bool(it.get("enabled_in_combat", false)):
			out.append(int(it["id"]))
	out.sort()
	return out


## ——— 数量阶梯：1/2/3/6 份同种弹药（余槽 EMPTY，倾泻/连发除外用白填）———
func _run_count_ladder() -> void:
	var ids: Array = _combat_ammo_ids()
	for aid in ids:
		for n in [1, 2, 3, 6]:
			var slots: Array = []
			for i in n:
				slots.append(int(aid))
			# dump：余槽填白，才能体现倾泻价值
			if int(aid) == FireResolver.ID_DUMP:
				while slots.size() < 6:
					slots.append(WHITE)
			# burst：只放 1 发连发（多发意义弱），n>1 时余槽白
			elif int(aid) == FireResolver.ID_BURST:
				slots = [FireResolver.ID_BURST]
				for _i in (n - 1):
					slots.append(WHITE)
				while slots.size() < mini(n, 6):
					slots.append(WHITE)
			# tombstone：袋幽灵随 copies 增加
			var seed_tag := "count_%d_x%d" % [int(aid), n]
			var seed_v := int(hash(seed_tag) % 100000) + 60000
			var cs := _fresh(seed_v)
			_dummy(cs)
			if int(aid) == FireResolver.ID_SCATTER or int(aid) == FireResolver.ID_EXPLOSIVE or int(aid) == FireResolver.ID_ARMOR_PIERCE:
				cs.sandbox_spawn_dummy(DUMMY_HP, 2)
				cs.sandbox_spawn_dummy(DUMMY_HP, 4)
			if int(aid) == FireResolver.ID_TOMBSTONE:
				cs.sandbox_add_ammo(FireResolver.ID_GHOST, n * 2, CombatConstants.GHOST_TTL_SEC)
			if int(aid) == FireResolver.ID_GOLD:
				cs.gold = 30
			_force_slots(cs, slots)
			var res := _fire_empty_cylinder(cs)
			var white_equiv := 0
			# 基线：同样槽位数的白弹（倾泻特殊：整匣6白）
			if int(aid) == FireResolver.ID_DUMP:
				white_equiv = 3 * 6
			elif int(aid) == FireResolver.ID_BURST:
				white_equiv = 3 * slots.size()  # 粗略：不含窗免费
			else:
				white_equiv = 3 * n
			var lift := int(res["dealt"]) - white_equiv
			_counts.append({
				"id": int(aid), "name": _ammo_name(int(aid)), "rarity": _rarity(int(aid)),
				"copies": n, "slots": slots.size(),
				"dealt": int(res["dealt"]), "shots": int(res["shots"]), "ops": int(res["ops"]),
				"dps_proxy": float(res["dps_proxy"]),
				"white_equiv": white_equiv, "lift": lift,
				"gold_spent": int(res.get("gold_spent", 0)),
				"heal": int(res.get("heal", 0)),
			})


## ——— 关键对 / 涌现 ———
func _run_key_pairs() -> void:
	_pair_row("平庸满匣基线", [WHITE, WHITE, WHITE, WHITE, WHITE, WHITE], {},
		"6白同步逐发")
	_pair_row("倾泻×5白", [FireResolver.ID_DUMP, WHITE, WHITE, WHITE, WHITE, WHITE], {},
		"同步倾泻整匣")
	_pair_row("倾泻×3愤怒×2白", [FireResolver.ID_DUMP, FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH, WHITE, WHITE], {},
		"倾泻叠怒雪球")
	_pair_row("连发窗×白载体", [FireResolver.ID_BURST], {}, "窗内尽量点射")
	_pair_row("墓碑×袋4幽灵", [FireResolver.ID_TOMBSTONE], {"ghosts": 4}, "无回声")
	_pair_row("墓碑×袋4幽灵×预挂回声", [FireResolver.ID_TOMBSTONE], {"ghosts": 4, "muzzle": {"echo": [1, 4.0]}}, "回声放大幽灵齐射")
	_pair_row("回声×3白", [FireResolver.ID_ECHO, WHITE, WHITE, WHITE], {}, "挂回声后白弹双结算")
	_pair_row("火焰×炸药×3白(3桩)", [FireResolver.ID_FLAME, FireResolver.ID_EXPLOSIVE, WHITE, WHITE, WHITE], {"dummies": 3}, "溅射+燃烧")
	_pair_row("愤怒×6", [FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH], {}, "满匣怒（触发三罪自伤）")
	_pair_row("正义卸2怒后白", [FireResolver.ID_JUSTICE], {"pre_load_sins": 2, "then_white": true}, "strip 后白弹吃 bonus")
	_pair_row("正义bonus6×3白", [WHITE, WHITE, WHITE], {"justice_bonus": 6}, "模拟成长后载体")
	_pair_row("金币×3(金20)", [FireResolver.ID_GOLD, FireResolver.ID_GOLD, FireResolver.ID_GOLD], {"gold": 20}, "抽金换伤")
	_pair_row("吸血×5", [FireResolver.ID_LIFESTEAL, FireResolver.ID_LIFESTEAL, FireResolver.ID_LIFESTEAL, FireResolver.ID_LIFESTEAL, FireResolver.ID_LIFESTEAL], {}, "叠层吸血窗")
	_pair_row("聚能×3", [FireResolver.ID_FOCUS, FireResolver.ID_FOCUS, FireResolver.ID_FOCUS], {}, "递增序列")
	_pair_row("穿甲×1(3桩)", [FireResolver.ID_ARMOR_PIERCE], {"dummies": 3}, "贯穿衰减")
	_pair_row("散射×1(3桩)", [FireResolver.ID_SCATTER], {"dummies": 3}, "均分")
	_pair_row("散射×1(1桩)", [FireResolver.ID_SCATTER], {"dummies": 1}, "单体效率差")
	_pair_row("石头×2", [FireResolver.ID_STONE, FireResolver.ID_STONE], {}, "碎石增生")
	_pair_row("保险×3怒", [FireResolver.ID_INSURANCE, FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_WRATH], {}, "防爆工具不增伤")
	_pair_row("连发窗×预挂怒3", [FireResolver.ID_BURST], {"muzzle": {"wrath": [3, 4.0]}}, "怒乘区下免费白弹")
	_pair_row("倾泻×5白×预挂回声", [FireResolver.ID_DUMP, WHITE, WHITE, WHITE, WHITE, WHITE], {"muzzle": {"echo": [1, 4.0]}}, "倾泻每发双结算")
	_pair_row("倾泻×5白×预挂怒3", [FireResolver.ID_DUMP, WHITE, WHITE, WHITE, WHITE, WHITE], {"muzzle": {"wrath": [3, 4.0]}}, "倾泻×怒乘")
	_pair_row("墓碑×袋6幽灵×回声×怒2", [FireResolver.ID_TOMBSTONE], {"ghosts": 6, "muzzle": {"echo": [1, 4.0], "wrath": [2, 4.0]}}, "极端清场包")
	_pair_row("暴食枪口×连发点杀", [FireResolver.ID_BURST], {"muzzle": {"gluttony": [3, 4.0]}, "low_hp_dummies": 4}, "击杀回血")
	_pair_row("懒惰×3白", [FireResolver.ID_SLOTH, WHITE, WHITE, WHITE], {}, "挂慢不直接抬伤")
	_pair_row("色欲×3白", [FireResolver.ID_LUST, WHITE, WHITE, WHITE], {}, "混乱控场")
	_pair_row("嫉妒×白", [FireResolver.ID_ENVY, WHITE], {}, "复制看概率")
	_pair_row("傲慢×3白", [FireResolver.ID_PRIDE, WHITE, WHITE, WHITE], {}, "减伤向")
	_pair_row("贪婪×3白", [FireResolver.ID_GREED, WHITE, WHITE, WHITE], {}, "经济向")


func _pair_row(name: String, slots: Array, opts: Dictionary, note: String) -> void:
	var seed_v := int(hash(name) % 100000) + 70000
	var cs := _fresh(seed_v)
	var dummy_n := int(opts.get("dummies", 1))
	if opts.has("low_hp_dummies"):
		for i in int(opts["low_hp_dummies"]):
			cs.sandbox_spawn_dummy(1, clampi(2 + i, 1, 6))
	else:
		for i in dummy_n:
			cs.sandbox_spawn_dummy(DUMMY_HP, clampi(2 + i, 1, 6))
	if opts.has("gold"):
		cs.gold = int(opts["gold"])
	if opts.has("justice_bonus"):
		cs.justice_damage_bonus = int(opts["justice_bonus"])
	if opts.has("ghosts"):
		cs.sandbox_add_ammo(FireResolver.ID_GHOST, int(opts["ghosts"]), CombatConstants.GHOST_TTL_SEC)
	if opts.has("muzzle"):
		var mz: Dictionary = opts["muzzle"]
		for k in mz.keys():
			var arr: Array = mz[k]
			cs.sandbox_set_muzzle(str(k), int(arr[0]), float(arr[1]))
	# 正义卸罪：先塞罪再装正义
	if opts.has("pre_load_sins"):
		var nsin := int(opts["pre_load_sins"])
		var pre: Array = []
		for _i in nsin:
			pre.append(FireResolver.ID_WRATH)
		pre.append(FireResolver.ID_JUSTICE)
		_force_slots(cs, pre)
		# 手动触发 strip（装入时）— 若 force_load 不走装弹钩，直接调用
		cs._apply_justice_strip_on_load(FireResolver.ID_JUSTICE)
		if bool(opts.get("then_white", false)):
			_force_slots(cs, [WHITE])
			var res_j := _fire_empty_cylinder(cs)
			_pairs.append({
				"name": name, "dealt": int(res_j["dealt"]), "shots": int(res_j["shots"]),
				"ops": int(res_j["ops"]), "dps_proxy": float(res_j["dps_proxy"]),
				"note": note + " bonus=%d" % cs.justice_damage_bonus,
				"heal": int(res_j.get("heal", 0)), "gold_spent": int(res_j.get("gold_spent", 0)),
				"slots": pre,
			})
			return
	_force_slots(cs, slots)
	var res := _fire_empty_cylinder(cs)
	_pairs.append({
		"name": name,
		"dealt": int(res["dealt"]),
		"shots": int(res["shots"]),
		"ops": int(res["ops"]),
		"dps_proxy": float(res["dps_proxy"]),
		"note": note,
		"heal": int(res.get("heal", 0)),
		"gold_spent": int(res.get("gold_spent", 0)),
		"slots": slots.duplicate(),
		"player_hp": cs.player_hp,
	})


## ——— 混装随机袋：多样弹药装匣开火多轮 ———
func _run_mixed_bags() -> void:
	var pool: Array = _combat_ammo_ids()
	# 固定几种「厨房水槽」配方
	var recipes: Array = [
		{
			"name": "厨槽A·爆发核",
			"bag": [
				FireResolver.ID_TOMBSTONE, FireResolver.ID_ECHO, FireResolver.ID_DUMP,
				FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_FLAME,
				FireResolver.ID_EXPLOSIVE, WHITE, WHITE, WHITE, WHITE, WHITE,
			],
			"ghosts": 5,
		},
		{
			"name": "厨槽B·窗与怒",
			"bag": [
				FireResolver.ID_BURST, FireResolver.ID_BURST, FireResolver.ID_WRATH,
				FireResolver.ID_WRATH, FireResolver.ID_WRATH, FireResolver.ID_LIFESTEAL,
				WHITE, WHITE, WHITE, WHITE, WHITE, WHITE,
			],
		},
		{
			"name": "厨槽C·正义成长",
			"bag": [
				FireResolver.ID_JUSTICE, FireResolver.ID_WRATH, FireResolver.ID_WRATH,
				FireResolver.ID_PRIDE, FireResolver.ID_GREED, FireResolver.ID_LUST,
				WHITE, WHITE, WHITE, WHITE, WHITE, WHITE,
			],
		},
		{
			"name": "厨槽D·AOE溅射",
			"bag": [
				FireResolver.ID_FLAME, FireResolver.ID_EXPLOSIVE, FireResolver.ID_SCATTER,
				FireResolver.ID_ARMOR_PIERCE, FireResolver.ID_ECHO, WHITE,
				WHITE, WHITE, WHITE, WHITE, WHITE, WHITE,
			],
			"dummies": 4,
		},
		{
			"name": "厨槽E·工具低伤",
			"bag": [
				FireResolver.ID_INSURANCE, FireResolver.ID_SLOTH, FireResolver.ID_STONE,
				FireResolver.ID_PEBBLE, FireResolver.ID_GOLD, FireResolver.ID_FOCUS,
				WHITE, WHITE, WHITE, WHITE, WHITE, WHITE,
			],
			"gold": 15,
		},
	]
	# 再加若干伪随机混装
	var rng := RandomNumberGenerator.new()
	rng.seed = 4191901
	for r in 12:
		var bag: Array = []
		for _i in 12:
			bag.append(int(pool[rng.randi_range(0, pool.size() - 1)]))
		recipes.append({"name": "随机混装#%d" % (r + 1), "bag": bag, "ghosts": 3, "dummies": 1 + (r % 3)})

	for rec in recipes:
		var seed_v := int(hash(str(rec["name"])) % 100000) + 80000
		var cs := _fresh(seed_v)
		var dn := int(rec.get("dummies", 1))
		for i in dn:
			cs.sandbox_spawn_dummy(DUMMY_HP, clampi(2 + i, 1, 6))
		if rec.has("ghosts"):
			cs.sandbox_add_ammo(FireResolver.ID_GHOST, int(rec["ghosts"]), CombatConstants.GHOST_TTL_SEC)
		if rec.has("gold"):
			cs.gold = int(rec["gold"])
		for aid in rec["bag"]:
			cs.sandbox_add_ammo(int(aid), 1, 0.0)
		# 多轮：装→打空→再装，共 3 匣
		var total_dealt := 0
		var total_shots := 0
		var total_ops := 0
		var total_gold := 0
		var total_heal := 0
		for _cycle in 3:
			if cs.magazine == null or cs.magazine.is_empty():
				cs.do_load()
			if cs.magazine == null or cs.magazine.is_empty():
				break
			var res := _fire_empty_cylinder(cs, 60)
			total_dealt += int(res["dealt"])
			total_shots += int(res["shots"])
			total_ops += int(res["ops"])
			total_gold += int(res.get("gold_spent", 0))
			total_heal += int(res.get("heal", 0))
			# 补幽灵 TTL（墓碑消耗）
			if rec.has("ghosts") and _cycle < 2:
				cs.sandbox_add_ammo(FireResolver.ID_GHOST, int(rec["ghosts"]), CombatConstants.GHOST_TTL_SEC)
		_mixed.append({
			"name": str(rec["name"]),
			"dealt": total_dealt,
			"shots": total_shots,
			"ops": total_ops,
			"dps_proxy": float(total_dealt) / float(maxi(total_ops, 1)),
			"gold_spent": total_gold,
			"heal": total_heal,
			"bag_size": rec["bag"].size(),
			"cycles": 3,
		})


func _write_report() -> void:
	# 汇总：按 count ladder copies=3 的 lift 排序作「影响力」
	var influence: Array = []
	var by_id: Dictionary = {}
	for row in _counts:
		if int(row["copies"]) != 3:
			continue
		by_id[int(row["id"])] = row
	for id in by_id.keys():
		var row: Dictionary = by_id[id]
		influence.append({
			"id": int(id),
			"name": str(row["name"]),
			"rarity": str(row["rarity"]),
			"dealt_x3": int(row["dealt"]),
			"lift_x3": int(row["lift"]),
			"dps_proxy": float(row["dps_proxy"]),
			"ops": int(row["ops"]),
		})
	influence.sort_custom(func(a, b): return int(a["lift_x3"]) > int(b["lift_x3"]))

	var pair_rank: Array = _pairs.duplicate()
	pair_rank.sort_custom(func(a, b): return int(a["dealt"]) > int(b["dealt"]))

	var mixed_rank: Array = _mixed.duplicate()
	mixed_rank.sort_custom(func(a, b): return int(a["dealt"]) > int(b["dealt"]))

	var out := {
		"version": GameVersion.STRING,
		"commit": "73070d7",
		"generated_at": "2026-11-02",
		"method": _method_notes,
		"exclusions": _exclusions,
		"solo": _solo,
		"counts": _counts,
		"pairs": _pairs,
		"mixed": _mixed,
		"influence_rank_x3": influence,
		"pair_rank": pair_rank,
		"mixed_rank": mixed_rank,
		"baseline_white_solo": 3,
		"baseline_white_x6": 18,
	}
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	assert_not_null(f, "open report")
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("KITCHENSINK_REPORT_WRITTEN ", REPORT_PATH, " influence_top=", influence[0]["name"] if influence.size() else "?")
