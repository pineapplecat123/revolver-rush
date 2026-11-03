extends GutTest
## v0.4.17 沙盒多轮压测：机制 / 弹药 / 钩子 / 涌现互动；结果写 tools/_stress_report.json

const REPORT_PATH := "res://tools/_stress_report.json"

var _hook_counts: Dictionary = {}
var _ammo_rows: Array = []
var _mech_rows: Array = []
var _combo_rows: Array = []
var _balance_notes: Array = []
var _issues: Array = []


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()
	CombatState.boot_sandbox = false


func _shot_one(cs: CombatState, resolve_enemy: bool = false) -> void:
	assert_true(cs.begin_fire())
	cs.fire_next_shot()
	if cs.has_paced_shot_pending():
		cs.finalize_paced_shot()
	if cs.post_fire_enemy_pending():
		if resolve_enemy:
			cs.resolve_post_fire_enemy_turn()
		else:
			cs._post_fire_enemy_pending = false


func _attach_hook_counter(cs: CombatState) -> void:
	_hook_counts.clear()
	cs.hooks.hooked.connect(func(event: StringName, _payload: Dictionary) -> void:
		var k := String(event)
		_hook_counts[k] = int(_hook_counts.get(k, 0)) + 1
	)


func _fresh_sandbox(seed_v: int = 41790) -> CombatState:
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
	_attach_hook_counter(cs)
	return cs


func _force_one(cs: CombatState, ammo_id: int) -> void:
	cs.dev_force_load([
		ammo_id,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)


func _dummy(cs: CombatState, hp: int = 5000, cell: int = 3) -> EnemyInstance:
	return cs.sandbox_spawn_dummy(hp, cell)


func _count_bag(cs: CombatState, ammo_id: int) -> int:
	var n := 0
	for id in cs.bag:
		if int(id) == ammo_id:
			n += 1
	return n


func _row_ammo(name: String, status: String, note: String, dealt: int = -1, extra: Dictionary = {}) -> void:
	var d := {"name": name, "status": status, "note": note, "dealt": dealt}
	for k in extra.keys():
		d[k] = extra[k]
	_ammo_rows.append(d)


func _row_mech(name: String, status: String, note: String) -> void:
	_mech_rows.append({"name": name, "status": status, "note": note})


func _isfinite_hp(cs: CombatState) -> bool:
	if cs.player_hp != cs.player_hp:  # NaN
		return false
	for e in cs.enemies:
		if e.hp != e.hp or e.hp < 0:
			return false
	return true


## ——— 机制多轮 ———

func test_stress_mechanisms_and_ammo() -> void:
	_run_mech_sandbox_flags()
	_run_mech_dump_interrupt()
	_run_mech_burst_window()
	_run_mech_dot_tick()
	_run_mech_load_temp_sin()
	_run_mech_three_sin_wrath()
	_run_mech_muzzle_timers()
	_run_ammo_suite()
	_run_emergent_combos()
	_run_balance_sims()
	_write_report()
	# Soft assert: critical broken rows must not exist
	for r in _ammo_rows:
		assert_ne(str(r["status"]), "broken", "ammo broken: %s — %s" % [r["name"], r["note"]])
	for r in _mech_rows:
		# 「仅tick_combat不掉枪口」记的是已知坑，status=pass 表示坑仍在
		if str(r["name"]).begins_with("仅tick_combat"):
			continue
		assert_ne(str(r["status"]), "fail", "mech fail: %s — %s" % [r["name"], r["note"]])


func _run_mech_sandbox_flags() -> void:
	var cs := _fresh_sandbox(41791)
	assert_true(cs.sandbox_mode and cs.spawn_paused and cs.map_shop_disabled)
	cs.tick_combat_time(60.0)
	var ok: bool = cs.enemies.is_empty() and cs.shop_cell == -1
	_row_mech("沙盒停刷怪/关地图店", "pass" if ok else "fail",
		"60s 后 enemies=%d shop_cell=%d" % [cs.enemies.size(), cs.shop_cell])
	var d: EnemyInstance = cs.sandbox_spawn_dummy(999, 4)
	var movers: Dictionary = cs.compute_enemy_movers()
	var immobile := d != null and not movers.has(d.get_instance_id()) and not cs.can_attack_player(d)
	_row_mech("木桩不动不攻", "pass" if immobile else "fail",
		"is_dummy=%s mobility=%d atk=%d" % [d.is_dummy, d.mobility, d.atk])


func _run_mech_dump_interrupt() -> void:
	var cs := _fresh_sandbox(41792)
	_dummy(cs, 9999, 3)
	cs.dev_force_load([
		FireResolver.ID_DUMP,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	# 异步倾泻：先主发，再 take 一发，再 interrupt
	var shots: Array = cs.fire_tap(false)
	var dump_started: bool = cs._dump_pending
	var after_one: Array = cs.take_dump_shot()
	var mid_loaded: int = cs.magazine.loaded_count()
	var interrupted: bool = cs.interrupt_dump()
	var still_pending: bool = cs._dump_pending
	var ok: bool = dump_started and not after_one.is_empty() and interrupted and not still_pending and mid_loaded >= 1
	_row_mech("倾泻步进+中断", "pass" if ok else "fail",
		"主发shots=%d pending_after_start=%s take=%d mid_loaded=%d interrupted=%s interval=%.2f" % [
			shots.size(), dump_started, after_one.size(), mid_loaded, interrupted,
			CombatConstants.DUMP_SHOT_INTERVAL_SEC
		])
	# 同步倾泻打完
	cs2_sync_dump()


func cs2_sync_dump() -> void:
	var cs := _fresh_sandbox(41793)
	_dummy(cs, 9999, 3)
	cs.dev_force_load([
		FireResolver.ID_DUMP,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	var shots: Array = cs.fire_tap(true)
	var dealt: int = hp0 - cs.enemies[0].hp
	# dump2 + white3 + white3 = 8
	var ok: bool = shots.size() >= 3 and dealt == 8 and cs.magazine.loaded_count() == 0
	_row_mech("倾泻同步打完", "pass" if ok else "fail",
		"shots=%d dealt=%d (expect 8) left=%d" % [shots.size(), dealt, cs.magazine.loaded_count()])


func _run_mech_burst_window() -> void:
	var cs := _fresh_sandbox(41794)
	_dummy(cs, 9999, 3)
	_force_one(cs, FireResolver.ID_BURST)
	var hp0: int = cs.enemies[0].hp
	cs.fire_tap(true)
	var after_main: int = hp0 - cs.enemies[0].hp
	var win: float = cs.burst_window_remaining
	hp0 = cs.enemies[0].hp
	cs.player_fire_gate_remaining = 0.0
	cs.fire_tap(true)  # free white in window
	var free_dealt: int = hp0 - cs.enemies[0].hp
	var ok: bool = after_main == 1 and win > 0.0 and free_dealt == 3 and cs.magazine.loaded_count() == 0
	_row_mech("连发窗免费平庸", "pass" if ok else "fail",
		"主发dealt=%d win=%.2f 免费dealt=%d BURST_WINDOW=%.1f" % [
			after_main, win, free_dealt, CombatConstants.BURST_WINDOW_SEC
		])


func _run_mech_dot_tick() -> void:
	var cs := _fresh_sandbox(41795)
	var e: EnemyInstance = _dummy(cs, 200, 3)
	cs.sandbox_set_enemy_status({"burn": 4})
	var hp0: int = e.hp
	# 推进两个 DoT 跳（0.5s）
	cs.tick_combat_time(CombatConstants.DOT_TICK_SEC)
	cs.tick_combat_time(CombatConstants.DOT_TICK_SEC)
	var dealt: int = hp0 - e.hp
	var ok: bool = dealt >= 2 and int(_hook_counts.get("on_dot_tick", 0)) >= 1
	_row_mech("DoT 0.5s 跳", "pass" if ok else "fail",
		"burn4 两跳 dealt=%d on_dot_tick=%d DOT_TICK=%.1f" % [
			dealt, int(_hook_counts.get("on_dot_tick", 0)), CombatConstants.DOT_TICK_SEC
		])


func _run_mech_load_temp_sin() -> void:
	## 多轮装填统计 33% 临时罪
	var hits := 0
	var trials := 60
	for i in trials:
		var cs := CombatState.new(41800 + i)
		cs.start_sandbox(41800 + i, FireResolver.ID_WRATH)
		cs.dev_clear_bag()
		# 装 1 发愤怒（从 0→1，不触发三罪）
		cs.sandbox_add_ammo(FireResolver.ID_WRATH, 1, 0.0)
		cs.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 5, 0.0)
		var bag0: int = _count_bag(cs, FireResolver.ID_WRATH)
		cs.do_load()
		var bag1: int = _count_bag(cs, FireResolver.ID_WRATH)
		# 装入拿走 1，若 33% 触发则袋内同种临时 +1 → bag1 == bag0（净零）或 bag0-1
		# 更稳：看 on_temp_sin_spawn / temp 标志
		if bag1 >= bag0:
			hits += 1
		elif cs.bag_temp.size() > 0:
			for t in cs.bag_temp:
				if Magazine.temp_value(t) > 0.0:
					hits += 1
					break
	# 改用钩子计数更准
	hits = 0
	for i in trials:
		var cs := CombatState.new(41900 + i)
		cs.start_sandbox(41900 + i, FireResolver.ID_WRATH)
		cs.dev_clear_bag()
		var spawned := [0]
		cs.hooks.subscribe(&"on_temp_sin_spawn", func(_p: Dictionary) -> void:
			spawned[0] = int(spawned[0]) + 1
		)
		cs.sandbox_add_ammo(FireResolver.ID_WRATH, 1, 0.0)
		cs.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 5, 0.0)
		cs.do_load()
		hits += int(spawned[0])
	var rate: float = float(hits) / float(trials)
	var ok: bool = rate > 0.15 and rate < 0.55
	_row_mech("装填临时罪≈33%", "pass" if ok else "fragile",
		"trials=%d spawn=%d rate=%.2f (expect ~0.33)" % [trials, hits, rate])


func _run_mech_three_sin_wrath() -> void:
	var cs := _fresh_sandbox(41796)
	cs.sandbox_add_ammo(FireResolver.ID_WRATH, 3, 0.0)
	cs.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 3, 0.0)
	var hp0: int = cs.player_hp
	var three := [0]
	cs.hooks.subscribe(&"on_three_sin", func(_p: Dictionary) -> void:
		three[0] += 1
	)
	cs.do_load()
	var ok: bool = int(three[0]) == 1 and cs.player_hp == hp0 - 6
	_row_mech("三罪愤怒自伤6", "pass" if ok else "fail",
		"on_three_sin=%d hpΔ=%d" % [three[0], hp0 - cs.player_hp])


func _run_mech_muzzle_timers() -> void:
	var cs := _fresh_sandbox(41797)
	cs.sandbox_set_muzzle("echo", 1, 1.5)
	cs.sandbox_set_muzzle("wrath", 2, 2.0)
	# v0.4.18：tick_combat_time 内已调 tick_muzzle_durations（勿双调）。
	cs.tick_combat_time(1.6)
	var echo_gone: bool = not cs._muzzle_echo
	var wrath_left: int = cs._muzzle_wrath
	var ok: bool = echo_gone and wrath_left == 2
	_row_mech("枪口层独立计时", "pass" if ok else "fail",
		"tick_combat 1.6s后 echo=%s wrath_stacks=%d" % [cs._muzzle_echo, wrath_left])
	cs.tick_combat_time(0.5)
	ok = cs._muzzle_wrath == 0
	_row_mech("枪口层到期清除", "pass" if ok else "fail", "再 combat 0.5s wrath=%d" % cs._muzzle_wrath)
	# v0.4.18：沙盒只推战斗秒也会掉枪口
	var cs2 := _fresh_sandbox(41798)
	cs2.sandbox_set_muzzle("echo", 1, 1.0)
	cs2.tick_combat_time(2.0)
	var still: bool = cs2._muzzle_echo
	_row_mech("tick_combat掉枪口", "pass" if not still else "fail",
		"只 tick_combat_time(2s) 后 echo=%s（期望 false）" % still)
	if still:
		_issues.append("tick_combat_time 未衰减枪口层")


## ——— 弹药套件 ———

func _run_ammo_suite() -> void:
	_ammo_white()
	_ammo_burst()
	_ammo_dump()
	_ammo_tomb_ghost()
	_ammo_echo()
	_ammo_lifesteal()
	_ammo_flame_explosive()
	_ammo_scatter()
	_ammo_insurance()
	_ammo_focus()
	_ammo_stone_pebble()
	_ammo_justice()
	_ammo_gold()
	_ammo_armor_pierce()
	_ammo_sins()


func _ammo_white() -> void:
	var cs := _fresh_sandbox(42001)
	_dummy(cs)
	_force_one(cs, CombatConstants.WHITE_AMMO_ID)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	var dealt: int = hp0 - cs.enemies[0].hp
	_row_ammo("平庸", "ok" if dealt == 3 else "broken", "单发固定3", dealt)


func _ammo_burst() -> void:
	var cs := _fresh_sandbox(42002)
	_dummy(cs)
	_force_one(cs, FireResolver.ID_BURST)
	cs.fire_tap(true)
	var ok: bool = cs.burst_window_remaining > 0.9 and int(_hook_counts.get("on_burst_window", 0)) >= 1
	_row_ammo("连发窗", "ok" if ok else "fragile",
		"window=%.2f on_burst_window=%d" % [cs.burst_window_remaining, int(_hook_counts.get("on_burst_window", 0))], 1)


func _ammo_dump() -> void:
	var cs := _fresh_sandbox(42003)
	_dummy(cs)
	cs.dev_force_load([
		FireResolver.ID_DUMP, CombatConstants.WHITE_AMMO_ID, Magazine.EMPTY,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	var hp0: int = cs.enemies[0].hp
	cs.fire_tap(true)
	var dealt: int = hp0 - cs.enemies[0].hp
	var ok: bool = dealt == 5 and int(_hook_counts.get("on_dump_start", 0)) >= 1 and int(_hook_counts.get("on_dump_end", 0)) >= 1
	_row_ammo("倾泻", "ok" if ok else "broken",
		"dump2+white3 dealt=%d dump_hooks start/end=%d/%d" % [
			dealt, int(_hook_counts.get("on_dump_start", 0)), int(_hook_counts.get("on_dump_end", 0))
		], dealt)


func _ammo_tomb_ghost() -> void:
	var cs := _fresh_sandbox(42004)
	_dummy(cs)
	cs.sandbox_add_ammo(FireResolver.ID_GHOST, 3, CombatConstants.GHOST_TTL_SEC)
	_force_one(cs, FireResolver.ID_TOMBSTONE)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	var dealt: int = hp0 - cs.enemies[0].hp
	# tombstone 2 + (3 existing + 1 new) ghosts * 2 = 2+8 = 10
	var expect := 2 + 4 * 2
	var left_g := _count_bag(cs, FireResolver.ID_GHOST)
	var ok: bool = dealt == expect and left_g == 0
	_row_ammo("墓碑/幽灵", "ok" if ok else "fragile",
		"dealt=%d expect=%d bag_ghost=%d ghost_leave=%d" % [
			dealt, expect, left_g, int(_hook_counts.get("on_bag_leave", 0))
		], dealt)


func _ammo_echo() -> void:
	var cs := _fresh_sandbox(42005)
	_dummy(cs)
	_force_one(cs, FireResolver.ID_ECHO)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	var dealt: int = hp0 - cs.enemies[0].hp
	# echo base 1, applies muzzle then double-settles → 1+1=2
	var ok: bool = dealt == 2 and cs._muzzle_echo and int(_hook_counts.get("on_muzzle_apply", 0)) >= 1
	_row_ammo("回声", "ok" if ok else "fragile",
		"dealt=%d (双结算) muzzle_echo=%s" % [dealt, cs._muzzle_echo], dealt)
	# follow-up white under echo
	cs.dev_force_load([
		CombatConstants.WHITE_AMMO_ID, Magazine.EMPTY, Magazine.EMPTY,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	hp0 = cs.enemies[0].hp
	_shot_one(cs)
	var white_echo: int = hp0 - cs.enemies[0].hp
	_balance_notes.append("回声下平庸：%d（无回声应为3）" % white_echo)
	if white_echo != 6:
		_issues.append("回声下平庸期望6实得%d" % white_echo)


func _ammo_lifesteal() -> void:
	var cs := _fresh_sandbox(42006)
	_dummy(cs)
	cs.player_hp = 10
	# 叠满 5 层吸血保证触发
	for _i in 5:
		_force_one(cs, FireResolver.ID_LIFESTEAL)
		_shot_one(cs)
	var stacks: int = cs._muzzle_lifesteal
	var ok: bool = stacks == 5
	_row_ammo("吸血", "ok" if ok else "fragile",
		"5发后层数=%d（每层20%%吸50%%伤）player_hp=%d" % [stacks, cs.player_hp], -1,
		{"stacks": stacks, "hp": cs.player_hp})


func _ammo_flame_explosive() -> void:
	var cs := _fresh_sandbox(42007)
	_dummy(cs, 9999, 3)
	cs.sandbox_spawn_dummy(9999, 2)
	cs.sandbox_spawn_dummy(9999, 4)
	_force_one(cs, FireResolver.ID_FLAME)
	_shot_one(cs)
	var burn: int = cs.enemies[0].burn_stacks if not cs.enemies.is_empty() else 0
	# find front-most
	var front: EnemyInstance = cs.front_enemy()
	burn = front.burn_stacks if front else 0
	_force_one(cs, FireResolver.ID_EXPLOSIVE)
	var hps: Array = []
	for e in cs.enemies:
		hps.append(e.hp)
	_shot_one(cs)
	var total_drop := 0
	for i in cs.enemies.size():
		total_drop += int(hps[i]) - cs.enemies[i].hp
	var ok: bool = burn >= 1 and total_drop >= 3 and cs._muzzle_fire and cs._muzzle_explosive
	_row_ammo("火焰+炸药", "ok" if ok else "fragile",
		"flame后burn=%d explosive溅射总伤≈%d muzzle flame/expl=%s/%s" % [
			burn, total_drop, cs._muzzle_fire, cs._muzzle_explosive
		], total_drop)


func _ammo_scatter() -> void:
	# <3 enemies: 30% each of 5 = 2 (round)
	var cs := _fresh_sandbox(42008)
	cs.sandbox_spawn_dummy(200, 3)
	cs.sandbox_spawn_dummy(200, 5)
	_force_one(cs, FireResolver.ID_SCATTER)
	var hp_a: int = cs.enemies[0].hp
	var hp_b: int = cs.enemies[1].hp
	_shot_one(cs)
	var d0: int = hp_a - cs.enemies[0].hp
	var d1: int = hp_b - cs.enemies[1].hp
	var ok_lt3 := d0 == 2 and d1 == 2  # round(5*0.3)=2
	# >=3: split
	var cs2 := _fresh_sandbox(42009)
	for c in [2, 4, 6]:
		cs2.sandbox_spawn_dummy(200, c)
	_force_one(cs2, FireResolver.ID_SCATTER)
	var before: Array = []
	for e in cs2.enemies:
		before.append(e.hp)
	_shot_one(cs2)
	var per := int(round(5.0 / 3.0))  # 2
	var drops: Array = []
	for i in cs2.enemies.size():
		drops.append(int(before[i]) - cs2.enemies[i].hp)
	var ok3 := true
	for d in drops:
		if int(d) != per:
			ok3 = false
	var status := "ok" if (ok_lt3 and ok3) else "fragile"
	_row_ammo("散射", status,
		"<3人各%d（期望2）；≥3均分各%s 期望%d" % [d0, str(drops), per], d0 + d1)


func _ammo_insurance() -> void:
	var cs := _fresh_sandbox(42010)
	# mag already has 2 wrath; bag has insurance + third wrath
	cs.dev_force_load([
		FireResolver.ID_WRATH, FireResolver.ID_WRATH, Magazine.EMPTY,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	# Need to load a third wrath with insurance in bag
	cs.sandbox_add_ammo(FireResolver.ID_INSURANCE, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_WRATH, 1, 0.0)
	cs.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 4, 0.0)
	# Use load session path: do_load fills empties from bag
	# Simpler: begin_load / load_next repeatedly — do_load should insurance-swap
	# Reset mag empty and load 3 wrath with insurance present
	cs.dev_force_load([
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.dev_clear_bag()
	cs.sandbox_add_ammo(FireResolver.ID_INSURANCE, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_WRATH, 3, 0.0)
	cs.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 2, 0.0)
	var hp0: int = cs.player_hp
	var swap := [0]
	cs.hooks.subscribe(&"on_insurance_swap", func(_p: Dictionary) -> void:
		swap[0] += 1
	)
	cs.do_load()
	var wrath_in_mag := 0
	for id in cs.magazine.slots:
		if int(id) == FireResolver.ID_WRATH:
			wrath_in_mag += 1
	var ok: bool = int(swap[0]) >= 1 and wrath_in_mag < 3 and cs.player_hp == hp0
	_row_ammo("保险", "ok" if ok else "fragile",
		"on_insurance_swap=%d mag_wrath=%d hpΔ=%d" % [swap[0], wrath_in_mag, hp0 - cs.player_hp])


func _ammo_focus() -> void:
	var cs := _fresh_sandbox(42011)
	_dummy(cs)
	cs.dev_force_load([
		FireResolver.ID_FOCUS, FireResolver.ID_FOCUS, FireResolver.ID_FOCUS,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	var deals: Array = []
	for _i in 3:
		var hp0: int = cs.enemies[0].hp
		_shot_one(cs)
		deals.append(hp0 - cs.enemies[0].hp)
	var ok: bool = deals == [3, 4, 5]
	_row_ammo("聚能", "ok" if ok else "broken", "三连伤害序列=%s 期望[3,4,5]" % str(deals), int(deals[0]) if deals.size() else -1)


func _ammo_stone_pebble() -> void:
	var cs := _fresh_sandbox(42012)
	_dummy(cs)
	_force_one(cs, FireResolver.ID_STONE)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	var dealt: int = hp0 - cs.enemies[0].hp
	var pebbles: int = _count_bag(cs, FireResolver.ID_PEBBLE)
	var ok_stone := dealt == 3 and pebbles == 3 and int(_hook_counts.get("on_stone_shatter", 0)) >= 1
	# fuse: load 3 pebbles adjacent
	cs.dev_clear_bag()
	cs.dev_force_load([
		FireResolver.ID_PEBBLE, FireResolver.ID_PEBBLE, FireResolver.ID_PEBBLE,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs.magazine.set_start(0)
	hp0 = cs.enemies[0].hp
	_shot_one(cs)
	var fuse_dealt: int = hp0 - cs.enemies[0].hp
	var ok_fuse := fuse_dealt == 3 and int(_hook_counts.get("on_pebble_fuse", 0)) >= 1
	_row_ammo("石头/小石", "ok" if (ok_stone and ok_fuse) else "fragile",
		"stone dealt=%d pebbles=%d; fuse dealt=%d" % [dealt, pebbles, fuse_dealt], dealt)


func _ammo_justice() -> void:
	cs2_justice_force()


func cs2_justice_force() -> void:
	var cs := _fresh_sandbox(42014)
	_dummy(cs)
	cs.dev_force_load([
		FireResolver.ID_WRATH, FireResolver.ID_WRATH, Magazine.EMPTY,
		Magazine.EMPTY, Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	var slot := -1
	for i in cs.magazine.slots.size():
		if cs.magazine.slots[i] == Magazine.EMPTY:
			slot = i
			break
	cs.magazine.set_slot(slot, FireResolver.ID_JUSTICE, false)
	var stripped: int = cs._apply_justice_strip_on_load(FireResolver.ID_JUSTICE)
	var bonus: int = cs.justice_damage_bonus
	_force_one(cs, CombatConstants.WHITE_AMMO_ID)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	var dealt: int = hp0 - cs.enemies[0].hp
	# stripped 2 → bonus 4 → white 3+4=7
	var ok: bool = stripped == 2 and bonus == 4 and dealt == 7
	_row_ammo("正义", "ok" if ok else "fragile",
		"stripped=%d bonus=%d white_dealt=%d (期望7)" % [stripped, bonus, dealt], dealt, {"bonus": bonus})


func _ammo_gold() -> void:
	var cs := _fresh_sandbox(42015)
	_dummy(cs)
	cs.gold = 10
	_force_one(cs, FireResolver.ID_GOLD)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	var dealt: int = hp0 - cs.enemies[0].hp
	var expect := 3 + int(10 * 0.20)  # 5
	var ok: bool = dealt == expect and cs.gold == 9 and int(_hook_counts.get("on_gold_ammo_spend", 0)) >= 1
	_row_ammo("金币", "ok" if ok else "broken",
		"dealt=%d expect=%d gold_after=%d" % [dealt, expect, cs.gold], dealt)
	_balance_notes.append("金币弹：金10→伤5，每发−1金；金池与商店共用")


func _ammo_armor_pierce() -> void:
	var cs := _fresh_sandbox(42016)
	cs.sandbox_spawn_dummy(50, 2)
	cs.sandbox_spawn_dummy(50, 3)
	cs.sandbox_spawn_dummy(50, 4)
	_force_one(cs, FireResolver.ID_ARMOR_PIERCE)
	var before: Array = []
	for e in cs.enemies_sorted_by_cell():
		before.append(e.hp)
	_shot_one(cs)
	var after_e: Array = cs.enemies_sorted_by_cell()
	var drops: Array = []
	for i in mini(before.size(), after_e.size()):
		drops.append(int(before[i]) - after_e[i].hp)
	# 3,2,1 on three dummies
	var ok: bool = drops.size() >= 3 and int(drops[0]) == 3 and int(drops[1]) == 2 and int(drops[2]) == 1
	var pierce_emit := false
	# Check if on_muzzle_apply kind pierce ever fired — scan by re-run with filter
	var cs2 := _fresh_sandbox(42017)
	var pierce_hooks := [0]
	cs2.hooks.subscribe(&"on_muzzle_apply", func(p: Dictionary) -> void:
		if str(p.get("kind", "")) == "pierce":
			pierce_hooks[0] += 1
	)
	_dummy(cs2)
	_force_one(cs2, FireResolver.ID_ARMOR_PIERCE)
	_shot_one(cs2)
	pierce_emit = pierce_hooks[0] > 0
	var status := "ok" if ok else "broken"
	var note := "贯穿伤害=%s" % str(drops)
	if not pierce_emit:
		status = "fragile" if ok else status
		note += "；on_muzzle_apply(pierce) 未 emit（效果本身正常）"
		_issues.append("穿甲挂枪口未 emit on_muzzle_apply(kind=pierce)，与 hooks 文档不一致")
	_row_ammo("穿甲", status, note, int(drops[0]) if drops.size() else -1)


func _ammo_sins() -> void:
	# Lust confuse
	var cs := _fresh_sandbox(42020)
	_dummy(cs)
	_force_one(cs, FireResolver.ID_LUST)
	_shot_one(cs)
	var lust_ok := cs._muzzle_lust >= 1
	_row_ammo("色欲", "ok" if lust_ok else "broken",
		"muzzle_lust=%d on_muzzle=%d" % [cs._muzzle_lust, int(_hook_counts.get("on_muzzle_apply", 0))])

	# Envy kill copy — force kill with envy muzzle
	var cs2 := _fresh_sandbox(42021)
	cs2.sandbox_spawn_dummy(2, 3)
	cs2.sandbox_set_muzzle("envy", 5, 4.0)  # ~100%*ish with 5*30%
	# set last non-sin via white/stone shot first
	_force_one(cs2, CombatConstants.WHITE_AMMO_ID)
	_shot_one(cs2)
	# spawn fresh low hp
	cs2.sandbox_clear_enemies()
	cs2.sandbox_spawn_dummy(1, 3)
	cs2.sandbox_set_muzzle("envy", 5, 4.0)
	_force_one(cs2, FireResolver.ID_ENVY)
	var bag0 := cs2.bag.size()
	_shot_one(cs2)
	var copy_hooks := int(_hook_counts.get("on_envy_copy", 0))
	# re-attach — hook counts on cs2
	_row_ammo("嫉妒", "ok" if cs2._muzzle_envy >= 1 else "fragile",
		"muzzle_envy=%d bagΔ=%d（复制看概率）" % [cs2._muzzle_envy, cs2.bag.size() - bag0])

	# Gluttony heal on kill
	var cs3 := _fresh_sandbox(42022)
	cs3.player_hp = 10
	cs3.sandbox_spawn_dummy(2, 3)
	cs3.sandbox_set_muzzle("gluttony", 3, 4.0)
	_force_one(cs3, CombatConstants.WHITE_AMMO_ID)
	_shot_one(cs3)
	# white 3 kills hp2; gluttony should heal +1
	var ok_g := cs3.player_hp >= 11
	_row_ammo("暴食", "ok" if ok_g else "fragile",
		"杀木桩后 hp=%d（期望≥11）muzzle=%d" % [cs3.player_hp, cs3._muzzle_gluttony])

	# Sloth slow
	var cs4 := _fresh_sandbox(42023)
	var e: EnemyInstance = _dummy(cs4)
	_force_one(cs4, FireResolver.ID_SLOTH)
	_shot_one(cs4)
	var slow_ok := e.slow_stacks() >= 1 and cs4._muzzle_sloth >= 1
	_row_ammo("懒惰", "ok" if slow_ok else "broken",
		"slow_stacks=%d muzzle_sloth=%d" % [e.slow_stacks(), cs4._muzzle_sloth])

	# Wrath / Pride / Greed muzzle apply
	for pack in [
		["愤怒", FireResolver.ID_WRATH, "wrath"],
		["傲慢", FireResolver.ID_PRIDE, "pride"],
		["贪婪", FireResolver.ID_GREED, "greed"],
	]:
		var csx := _fresh_sandbox(42030 + int(pack[1]))
		_dummy(csx)
		_force_one(csx, int(pack[1]))
		var hp0: int = csx.enemies[0].hp
		_shot_one(csx)
		var dealt: int = hp0 - csx.enemies[0].hp
		_row_ammo(str(pack[0]), "ok" if dealt > 0 else "broken",
			"单发dealt=%d（含本发枪口层）" % dealt, dealt)


## ——— 涌现连携 ———

func _run_emergent_combos() -> void:
	# 1 tombstone + echo
	var cs := _fresh_sandbox(43001)
	_dummy(cs, 99999, 3)
	cs.sandbox_set_muzzle("echo", 1, 4.0)
	cs.sandbox_add_ammo(FireResolver.ID_GHOST, 2, CombatConstants.GHOST_TTL_SEC)
	_force_one(cs, FireResolver.ID_TOMBSTONE)
	var hp0: int = cs.enemies[0].hp
	_shot_one(cs)
	var dealt: int = hp0 - cs.enemies[0].hp
	# Without echo: tomb2 + ghosts(2+1)*2 = 8 → 2+6=8
	# With echo: each shot doubles → tomb 2*2=4 + 3 ghosts *2 *2 = 12 → 16?
	# Virtual ghost also echoes. Tombstone itself also echoes if muzzle already set BEFORE mount order.
	# sandbox echo already on; tombstone shot gets echo twin; ghosts get echo.
	_combo_rows.append({
		"name": "墓碑幽灵 × 回声枪口",
		"power": "高",
		"dealt": dealt,
		"note": "预挂回声后墓碑连射幽灵；本测 dealt=%d（无回声基线约8）" % dealt,
		"works": dealt > 8,
	})

	# 2 flame + explosive multi
	var cs2 := _fresh_sandbox(43002)
	for c in [2, 3, 4, 5]:
		cs2.sandbox_spawn_dummy(500, c)
	cs2.sandbox_set_muzzle("flame", 1, 4.0)
	cs2.sandbox_set_muzzle("explosive", 1, 4.0)
	_force_one(cs2, CombatConstants.WHITE_AMMO_ID)
	# first white applies burn via flame
	_shot_one(cs2)
	_force_one(cs2, CombatConstants.WHITE_AMMO_ID)
	var sum0 := 0
	for e in cs2.enemies:
		sum0 += e.hp
	_shot_one(cs2)
	var sum1 := 0
	for e in cs2.enemies:
		sum1 += e.hp
	var splash: int = sum0 - sum1
	_combo_rows.append({
		"name": "火焰 × 炸药（白弹载体）",
		"power": "高",
		"dealt": splash,
		"note": "预挂火焰+炸药后两发白弹，第二发溅射总伤=%d" % splash,
		"works": splash >= 9,
	})

	# 3 envy + stone
	var cs3 := _fresh_sandbox(43003)
	cs3.sandbox_spawn_dummy(3, 3)
	_force_one(cs3, FireResolver.ID_STONE)
	_shot_one(cs3)  # sets last non-sin = stone, may kill or not
	cs3.sandbox_clear_enemies()
	cs3.sandbox_spawn_dummy(1, 3)
	cs3.sandbox_set_muzzle("envy", 5, 4.0)
	_force_one(cs3, FireResolver.ID_ENVY)
	var bag_before := _count_bag(cs3, FireResolver.ID_STONE) + _count_bag(cs3, FireResolver.ID_PEBBLE)
	_shot_one(cs3)
	var bag_after := _count_bag(cs3, FireResolver.ID_STONE) + _count_bag(cs3, FireResolver.ID_PEBBLE)
	_combo_rows.append({
		"name": "嫉妒 × 石头/砾",
		"power": "中",
		"dealt": bag_after - bag_before,
		"note": "击杀复制非罪 TTL；石/砾袋增量=%d（概率）" % (bag_after - bag_before),
		"works": true,
	})

	# 4 burst + gluttony
	var cs4 := _fresh_sandbox(43004)
	cs4.player_hp = 10
	cs4.sandbox_set_muzzle("gluttony", 3, 4.0)
	cs4.sandbox_spawn_dummy(1, 3)
	_force_one(cs4, FireResolver.ID_BURST)
	cs4.fire_tap(true)
	# kill with free burst shots
	var guard := 8
	while cs4.enemies.size() > 0 and cs4.burst_window_remaining > 0.0 and guard > 0:
		guard -= 1
		cs4.player_fire_gate_remaining = 0.0
		cs4.fire_tap(true)
	_combo_rows.append({
		"name": "连发窗 × 暴食击杀回血",
		"power": "中",
		"dealt": cs4.player_hp - 10,
		"note": "窗内点杀后 hpΔ=%d（暴食+1/杀）enemies_left=%d" % [cs4.player_hp - 10, cs4.enemies.size()],
		"works": cs4.player_hp >= 10,
	})

	# 5 dump + wrath stacks
	var cs5 := _fresh_sandbox(43005)
	_dummy(cs5, 99999, 3)
	cs5.dev_force_load([
		FireResolver.ID_DUMP,
		FireResolver.ID_WRATH,
		FireResolver.ID_WRATH,
		FireResolver.ID_WRATH,
		Magazine.EMPTY, Magazine.EMPTY,
	] as Array[int])
	cs5.magazine.set_start(0)
	var h0: int = cs5.enemies[0].hp
	cs5.fire_tap(true)
	var dump_wrath_dealt: int = h0 - cs5.enemies[0].hp
	_combo_rows.append({
		"name": "倾泻 × 愤怒叠层",
		"power": "高",
		"dealt": dump_wrath_dealt,
		"note": "倾泻打出多发愤怒，枪口层滚雪球；总伤=%d wrath_stacks=%d" % [dump_wrath_dealt, cs5._muzzle_wrath],
		"works": dump_wrath_dealt > 20,
	})

	# 6 justice + sins farm
	var cs6 := _fresh_sandbox(43006)
	_dummy(cs6)
	cs6.justice_damage_bonus = 6  # simulate 3 strips
	_force_one(cs6, CombatConstants.WHITE_AMMO_ID)
	var h1: int = cs6.enemies[0].hp
	_shot_one(cs6)
	var jd: int = h1 - cs6.enemies[0].hp
	_combo_rows.append({
		"name": "正义永久加伤载体",
		"power": "高（成长）",
		"dealt": jd,
		"note": "bonus=6 时白弹伤=%d（3+6）" % jd,
		"works": jd == 9,
	})

	# weak: insurance alone
	_combo_rows.append({
		"name": "保险（纯防爆）",
		"power": "低（工具）",
		"dealt": 0,
		"note": "不增伤；挡三罪。与懒惰/倾泻无自然增伤联动（除非另写订阅）",
		"works": true,
	})


func _run_balance_sims() -> void:
	# dump full mag whites vs burst+clicks DPS proxy (damage per "action")
	var cs := _fresh_sandbox(44001)
	_dummy(cs, 99999, 3)
	cs.dev_force_load([
		FireResolver.ID_DUMP,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
		CombatConstants.WHITE_AMMO_ID,
	] as Array[int])
	cs.magazine.set_start(0)
	var h0: int = cs.enemies[0].hp
	cs.fire_tap(true)
	var dump_total: int = h0 - cs.enemies[0].hp
	# 2 + 5*3 = 17 in one tap chain; wall time ~5*0.06 if async
	_balance_notes.append("倾泻满匣(倾泻+5白)：总伤=%d，同步1次操作；异步约%.2fs" % [
		dump_total, 5.0 * CombatConstants.DUMP_SHOT_INTERVAL_SEC
	])

	var cs2 := _fresh_sandbox(44002)
	_dummy(cs2, 99999, 3)
	_force_one(cs2, FireResolver.ID_BURST)
	h0 = cs2.enemies[0].hp
	cs2.fire_tap(true)
	var clicks := 1
	var guard := 20
	while cs2.burst_window_remaining > 0.0 and guard > 0:
		guard -= 1
		# simulate time drain between clicks
		cs2.tick_combat_time(CombatConstants.MIN_FIRE_INTERVAL_SEC)
		if cs2.burst_window_remaining <= 0.0:
			break
		cs2.fire_tap(true)
		clicks += 1
	var burst_total: int = h0 - cs2.enemies[0].hp
	_balance_notes.append("连发窗：1秒内点射×%d 总伤=%d（主发1+免费平庸×n）" % [clicks, burst_total])

	# tombstone echo risk
	var cs3 := _fresh_sandbox(44003)
	_dummy(cs3, 99999, 3)
	cs3.sandbox_set_muzzle("echo", 1, 4.0)
	cs3.sandbox_add_ammo(FireResolver.ID_GHOST, 5, CombatConstants.GHOST_TTL_SEC)
	_force_one(cs3, FireResolver.ID_TOMBSTONE)
	h0 = cs3.enemies[0].hp
	_shot_one(cs3)
	var te: int = h0 - cs3.enemies[0].hp
	_balance_notes.append("墓碑+袋5幽灵+预挂回声：单次点射总伤=%d（清场风险高）" % te)

	# scatter vs 1 target inefficiency
	var cs4 := _fresh_sandbox(44004)
	_dummy(cs4, 999, 3)
	_force_one(cs4, FireResolver.ID_SCATTER)
	h0 = cs4.enemies[0].hp
	_shot_one(cs4)
	_balance_notes.append("散射对1木桩：dealt=%d（底伤5×30%%→2），单体弱" % (h0 - cs4.enemies[0].hp))

	# gold sink
	_balance_notes.append("商店价：普通5/精良8/稀有14/史诗22；金币弹持续射击会抽干买店本钱")

	# three-sin severity snapshot
	_balance_notes.append("三罪惩罚：愤怒自伤6（最大HP20的30%%）；傲慢拉近；贪婪-6金；色欲自混乱；嫉妒弃2永久；暴食自DoT；懒惰射速窗4s")


func _write_report() -> void:
	# Also collect full hook coverage from a kitchen-sink run
	var coverage: Dictionary = _kitchen_sink_hooks()
	var out := {
		"version": GameVersion.STRING,
		"commit_hint": "e02bce3",
		"ammo": _ammo_rows,
		"mechanisms": _mech_rows,
		"combos": _combo_rows,
		"balance": _balance_notes,
		"issues": _issues,
		"hook_coverage": coverage,
		"hook_docs_events": [
			"on_fire", "on_shot", "on_chamber_loaded", "on_bag_enter", "on_bag_leave",
			"on_three_sin", "on_muzzle_apply", "on_kill", "on_shop_enter",
			"on_dump_start", "on_dump_end", "on_burst_window", "on_temp_sin_spawn", "on_dot_tick",
			"on_insurance_swap", "on_stone_shatter", "on_pebble_fuse", "on_justice_strip",
			"on_gold_ammo_spend", "on_confuse", "on_confuse_attack", "on_player_confuse",
			"on_self_hit", "on_envy_copy", "on_envy_discard", "on_gluttony_heal",
			"on_gluttony_self_dot", "on_slow", "on_sloth_fire_penalty",
		],
	}
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	assert_not_null(f)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("STRESS_REPORT_WRITTEN ", REPORT_PATH)


func _kitchen_sink_hooks() -> Dictionary:
	var cs := _fresh_sandbox(45000)
	var counts: Dictionary = {}
	cs.hooks.hooked.connect(func(event: StringName, payload: Dictionary) -> void:
		var k := String(event)
		counts[k] = int(counts.get(k, 0)) + 1
		if k == "on_muzzle_apply":
			var kind := "muzzle:" + str(payload.get("kind", "?"))
			counts[kind] = int(counts.get(kind, 0)) + 1
	)
	# burn + confuse multi enemies
	for c in [2, 3, 4]:
		cs.sandbox_spawn_dummy(30, c)
	cs.sandbox_set_enemy_status({"burn": 3, "confuse": 2.0})
	# bag variety
	cs.sandbox_add_ammo(FireResolver.ID_GHOST, 2, 10.0)
	cs.sandbox_add_ammo(FireResolver.ID_INSURANCE, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_STONE, 2, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_FLAME, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_EXPLOSIVE, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_ECHO, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_TOMBSTONE, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_BURST, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_DUMP, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_GOLD, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_LIFESTEAL, 2, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_SCATTER, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_FOCUS, 2, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_ARMOR_PIERCE, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_JUSTICE, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_WRATH, 3, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_LUST, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_ENVY, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_GLUTTONY, 1, 0.0)
	cs.sandbox_add_ammo(FireResolver.ID_SLOTH, 1, 0.0)
	cs.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 6, 0.0)
	cs.do_load()
	# fire many
	for _i in 12:
		if cs.magazine == null or cs.magazine.is_empty():
			cs.do_load()
		if cs.magazine == null or cs.magazine.is_empty():
			break
		cs.fire_tap(true)
		cs.tick_combat_time(0.2)
	cs.tick_combat_time(1.0)
	# three sin envy discard path
	var cs2 := _fresh_sandbox(45001)
	cs2.hooks.hooked.connect(func(event: StringName, _p: Dictionary) -> void:
		var k := String(event)
		counts[k] = int(counts.get(k, 0)) + 1
	)
	cs2.sandbox_add_ammo(FireResolver.ID_ENVY, 3, 0.0)
	cs2.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 3, 0.0)
	cs2.sandbox_add_ammo(FireResolver.ID_STONE, 2, 0.0)
	cs2.do_load()
	# gluttony self dot
	var cs3 := _fresh_sandbox(45002)
	cs3.hooks.hooked.connect(func(event: StringName, _p: Dictionary) -> void:
		var k := String(event)
		counts[k] = int(counts.get(k, 0)) + 1
	)
	cs3.sandbox_add_ammo(FireResolver.ID_GLUTTONY, 3, 0.0)
	cs3.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 3, 0.0)
	cs3.do_load()
	cs3.tick_combat_time(1.0)
	# lust three
	var cs4 := _fresh_sandbox(45003)
	cs4.hooks.hooked.connect(func(event: StringName, _p: Dictionary) -> void:
		var k := String(event)
		counts[k] = int(counts.get(k, 0)) + 1
	)
	cs4.sandbox_add_ammo(FireResolver.ID_LUST, 3, 0.0)
	cs4.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 3, 0.0)
	cs4.do_load()
	_dummy(cs4)
	_force_one(cs4, CombatConstants.WHITE_AMMO_ID)
	_shot_one(cs4)
	# sloth three
	var cs5 := _fresh_sandbox(45004)
	cs5.hooks.hooked.connect(func(event: StringName, _p: Dictionary) -> void:
		var k := String(event)
		counts[k] = int(counts.get(k, 0)) + 1
	)
	cs5.sandbox_add_ammo(FireResolver.ID_SLOTH, 3, 0.0)
	cs5.sandbox_add_ammo(CombatConstants.WHITE_AMMO_ID, 3, 0.0)
	cs5.do_load()
	return counts
