extends GutTest
## v0.3.3：敌人平滑连续滑行 + 放慢；转轮动画 ×1.5；手动装弹不覆盖已有弹。

const CombatUIScript = preload("res://scripts/combat/combat_ui.gd")


func before_each() -> void:
	DataRegistry.reload()
	BulletEffectRegistry.ensure_defaults()


func _rush(seed_v: int = 4242) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.start_rush(seed_v)
	for e in cs.enemies:
		e.hp = 9999
		e.max_hp = 9999
	return cs


func _add_enemy(cs: CombatState, cell: int) -> EnemyInstance:
	var src: EnemyInstance = cs.enemies[0]
	var e := EnemyInstance.new(DataRegistry.get_enemy(src.def_id), cell)
	e.hp = 9999
	e.max_hp = 9999
	cs.enemies.append(e)
	return e


func _fill_bag_white(cs: CombatState, n: int) -> void:
	cs.bag.clear()
	cs.bag_temp.clear()
	for _i in n:
		cs.bag.append(FireResolver.ID_WHITE)
		cs.bag_temp.append(false)


var last_loaded_id: int = Magazine.EMPTY


func _manual_load_one(cs: CombatState) -> bool:
	## 与 UI _run_manual_load_one 同路径（无动画）。last_loaded_id = 本次实际装入的弹（无则 EMPTY）。
	last_loaded_id = Magazine.EMPTY
	if not cs.can_manual_load():
		return false
	if not cs.is_busy_loading():
		if not cs.begin_load():
			return false
		if not cs.is_busy_loading():
			return true
	var r: Dictionary = cs.load_next_chamber()
	if not bool(r.get("ok", false)):
		return false
	last_loaded_id = int(r.get("ammo_id", Magazine.EMPTY))
	if not bool(r.get("done", false)):
		cs.apply_load_rotate()
	return true


func _snapshot(cs: CombatState) -> Array:
	return cs.magazine.slots.duplicate()


func _assert_only_empties_filled(before: Array, after: Array, ctx: String) -> void:
	var added := 0
	for i in before.size():
		if int(before[i]) != Magazine.EMPTY:
			assert_eq(int(after[i]), int(before[i]), "%s：仓%d 已有弹被覆盖" % [ctx, i])
		elif int(after[i]) != Magazine.EMPTY:
			added += 1
	assert_true(added <= 1, "%s：一次手装只应补 1 发（实际 %d）" % [ctx, added])


# ---------- 装弹不覆盖（回归 t340u） ----------

func test_reload_after_partial_fire_never_overwrites() -> void:
	## 半匣（有弹仓与空仓交错）继续手装：上弹口必须跳过有弹仓，已有弹不变。
	var cs := _rush()
	_fill_bag_white(cs, 12)
	cs.magazine.clear()
	cs.magazine.set_slot(0, FireResolver.ID_RED)
	cs.magazine.set_slot(2, FireResolver.ID_BLUE)
	cs.magazine.set_slot(3, FireResolver.ID_GREEN)
	cs.magazine.start_index = 0
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	for k in 3:
		var before := _snapshot(cs)
		assert_true(_manual_load_one(cs), "手装第 %d 发" % (k + 1))
		_assert_only_empties_filled(before, _snapshot(cs), "手装%d" % (k + 1))
	assert_eq(cs.magazine.slots[0], FireResolver.ID_RED)
	assert_eq(cs.magazine.slots[2], FireResolver.ID_BLUE)
	assert_eq(cs.magazine.slots[3], FireResolver.ID_GREEN)
	assert_eq(cs.magazine.loaded_count(), 6)


func test_load_rotate_skips_occupied_chambers() -> void:
	var cs := _rush()
	_fill_bag_white(cs, 6)
	cs.magazine.clear()
	cs.magazine.set_slot(1, FireResolver.ID_RED)
	cs.magazine.set_slot(2, FireResolver.ID_BLUE)
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	assert_true(cs.begin_load())
	var r: Dictionary = cs.load_next_chamber()
	assert_false(bool(r.get("done", true)))
	cs.apply_load_rotate()
	var port: int = cs.magazine.chamber_at_load_port()
	assert_eq(cs.magazine.slots[port], Magazine.EMPTY, "转盘后上弹口必须对着空仓")
	assert_eq(int(r.get("rotate_to", -1)), cs.magazine.start_index)


func test_fuzz_interleaved_fire_and_reload_keeps_ammo() -> void:
	## 随机交错 手装/开火 200 次：任何一次手装都不改已有弹；匣内弹数守恒。
	for seed_v in [1, 7, 33, 2026]:
		var cs := _rush(seed_v)
		# v0.3.5 补袋会带回罪孽，第 3 颗即自伤：给足血量保证跑满 200 步
		cs.player_max_hp = 9999
		cs.player_hp = 9999
		_fill_bag_white(cs, 30)
		cs.discard.clear()
		cs.discard_temp.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		for step in 200:
			if cs.phase == CombatState.Phase.WON or cs.phase == CombatState.Phase.LOST:
				break
			if rng.randf() < 0.6:
				var before := _snapshot(cs)
				var cnt: int = cs.magazine.loaded_count()
				if _manual_load_one(cs):
					if last_loaded_id in [FireResolver.ID_WRATH, FireResolver.ID_PRIDE, FireResolver.ID_GREED]:
						# v0.3.5：第 3 颗同种罪孽入膛即刻惩罚（可能扣命重置转轮），不在此守恒断言内
						continue
					_assert_only_empties_filled(before, _snapshot(cs), "seed%d step%d" % [seed_v, step])
					var want: int = cnt + (1 if last_loaded_id != Magazine.EMPTY else 0)
					assert_eq(cs.magazine.loaded_count(), want, "seed%d step%d：装入 1 发弹数应 +1（覆盖则不变）" % [seed_v, step])
			elif cs.can_fire():
				var cnt2: int = cs.magazine.loaded_count()
				assert_true(cs.begin_fire())
				cs.fire_next_shot()
				if cs.has_paced_shot_pending():
					cs.finalize_paced_shot()
				cs.finalize_post_fire()
				assert_eq(cs.magazine.loaded_count(), cnt2 - 1, "白弹开火只消耗 1 发")
			assert_true(cs.magazine.loaded_count() <= CombatConstants.MAGAZINE_SIZE)


# ---------- 敌人连续滑行 ----------

func test_enemy_speed_slower_than_v032() -> void:
	## v0.3.2 为 1.15s/格；v0.3.3 放慢约 30%。
	assert_almost_eq(CombatConstants.ENEMY_AUTO_STEP_SEC, 1.65, 0.001)
	var slow_ratio: float = 1.0 - 1.15 / CombatConstants.ENEMY_AUTO_STEP_SEC
	assert_between(slow_ratio, 0.25, 0.40)


func test_glide_is_continuous_and_lands_on_cell() -> void:
	var cs := _rush()
	cs.enemies.resize(1)
	var e: EnemyInstance = cs.enemies[0]
	e.cell = 6
	cs.reset_enemy_glide()
	assert_eq(cs.advance_enemy_glide(0.25), 0)
	assert_eq(e.cell, 6)
	assert_almost_eq(cs.enemy_continuous_x(e), 5.75, 0.0001)
	assert_eq(cs.advance_enemy_glide(0.5), 0)
	assert_almost_eq(cs.enemy_continuous_x(e), 5.25, 0.0001)
	# 跨格：逻辑格 -1，连续位置不跳
	assert_eq(cs.advance_enemy_glide(0.35), 1)
	assert_eq(e.cell, 5)
	assert_almost_eq(cs.enemy_continuous_x(e), 4.9, 0.0001)


func test_glide_many_small_frames_matches_speed() -> void:
	## 60fps 模拟 ENEMY_AUTO_STEP_SEC×3 秒 → 走 3 格；位置单调递减。
	var cs := _rush()
	cs.enemies.resize(1)
	var e: EnemyInstance = cs.enemies[0]
	e.cell = 8
	cs.reset_enemy_glide()
	var dt := 1.0 / 60.0
	var frames: int = int(round(CombatConstants.ENEMY_AUTO_STEP_SEC * 3.0 / dt))
	var last_x: float = cs.enemy_continuous_x(e)
	for _f in frames:
		cs.advance_enemy_glide(dt / CombatConstants.ENEMY_AUTO_STEP_SEC)
		var x: float = cs.enemy_continuous_x(e)
		assert_true(x <= last_x + 0.0001, "滑行不得后退")
		assert_true(last_x - x < 0.05, "单帧位移不得跳格")
		last_x = x
	assert_almost_eq(cs.enemy_continuous_x(e), 5.0, 0.05)


func test_blocked_and_adjacent_enemies_do_not_glide() -> void:
	var cs := _rush()
	cs.enemies.resize(1)
	var a: EnemyInstance = cs.enemies[0]
	a.cell = 1
	var b: EnemyInstance = _add_enemy(cs, 2)
	b.cell = 2
	b.hp = 9999
	b.max_hp = 9999
	cs.reset_enemy_glide()
	cs.advance_enemy_glide(0.5)
	assert_eq(cs.enemy_glide_fraction(a), 0.0, "贴脸的怪不滑")
	assert_eq(cs.enemy_glide_fraction(b), 0.0, "被挡的怪不滑")
	var hp0: int = cs.player_hp
	cs.advance_enemy_glide(0.6)
	assert_eq(a.cell, 1)
	assert_eq(b.cell, 2)
	assert_true(cs.player_hp < hp0, "到达玩家侧仍攻击")


func test_follower_glides_with_moving_leader() -> void:
	var cs := _rush()
	cs.enemies.resize(1)
	var a: EnemyInstance = cs.enemies[0]
	a.cell = 4
	var b: EnemyInstance = _add_enemy(cs, 5)
	b.cell = 5
	cs.reset_enemy_glide()
	cs.advance_enemy_glide(0.4)
	assert_almost_eq(cs.enemy_glide_fraction(a), 0.4, 0.0001)
	assert_almost_eq(cs.enemy_glide_fraction(b), 0.4, 0.0001)
	cs.advance_enemy_glide(0.6)
	assert_eq(a.cell, 3)
	assert_eq(b.cell, 4)


func test_unblocked_mid_step_waits_for_next_step_no_teleport() -> void:
	## 拍中被挡者前方怪死亡：本拍不瞬移，下一拍再开始滑。
	var cs := _rush()
	cs.enemies.resize(1)
	var a: EnemyInstance = cs.enemies[0]
	a.cell = 1
	a.atk = 0
	var b: EnemyInstance = _add_enemy(cs, 2)
	b.cell = 2
	b.atk = 0
	cs.reset_enemy_glide()
	cs.advance_enemy_glide(0.5)
	a.hp = 0
	cs._remove_dead()
	assert_eq(cs.enemy_glide_fraction(b), 0.0)
	cs.advance_enemy_glide(0.6)
	assert_eq(b.cell, 2, "解除阻挡的那一拍不跳格")
	cs.advance_enemy_glide(0.5)
	assert_almost_eq(cs.enemy_glide_fraction(b), 0.6, 0.0001)


func test_wheel_anim_speed_is_1_5x() -> void:
	assert_almost_eq(CombatUIScript.WHEEL_SPEED_MULT, 1.5, 0.0001)
	assert_almost_eq(CombatUIScript.STEP_ROT_DURATION, 0.12, 0.0001)
	assert_almost_eq(CombatUIScript.ROLL_ANIM_BASE, 0.30, 0.0001)
	assert_almost_eq(CombatUIScript.ROLL_ANIM_MAX, 0.70, 0.0001)
	assert_almost_eq(CombatUIScript.LOAD_INSERT_PAUSE, 0.14 / 1.5, 0.0001)
	assert_almost_eq(CombatUIScript.FIRE_SHOT_DELAY, 0.4 / 1.5, 0.0001)
	assert_almost_eq(CombatUIScript.FIRE_FLASH_HOLD, 0.2 / 1.5, 0.0001)


func test_ui_uses_per_frame_glide_not_timer() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/combat/combat_ui.gd")
	assert_true(src.contains("func _process(delta: float)"))
	assert_true(src.contains("advance_enemy_glide"))
	assert_false(src.contains("EnemyAutoTimer"), "不再用计时器一格一跳")


# ---------- 逻辑审计回归 ----------

func test_corpse_keeps_glide_position_until_flushed() -> void:
	var cs := _rush()
	cs.enemies.resize(1)
	var e: EnemyInstance = cs.enemies[0]
	e.cell = 6
	cs.reset_enemy_glide()
	cs.advance_enemy_glide(0.4)
	e.hp = 0  # pace 下尸体留场飚血
	assert_almost_eq(cs.enemy_glide_fraction(e), 0.4, 0.0001, "死亡瞬间不得瞬移回格心")


func test_step_during_firing_keeps_wrath_greed_for_duration() -> void:
	var cs := _rush()
	cs._muzzle_wrath = 1
	cs._muzzle_wrath_t = CombatConstants.MUZZLE_DURATION_WRATH_SEC
	cs._muzzle_greed = 1
	cs._muzzle_greed_t = CombatConstants.MUZZLE_DURATION_GREED_SEC
	cs._set_phase(CombatState.Phase.FIRING)
	cs.reset_enemy_glide()
	cs.advance_enemy_glide(1.0)
	assert_eq(cs._muzzle_wrath, 1, "飞行中不清愤怒")
	assert_eq(cs._muzzle_greed, 1, "飞行中不清贪婪")
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	cs.finalize_post_fire()
	assert_eq(cs._muzzle_wrath, 1, "收束也不清；等持续时间")
	assert_eq(cs._muzzle_greed, 1)
	cs.tick_muzzle_durations(CombatConstants.MUZZLE_DURATION_WRATH_SEC + 0.01)
	assert_eq(cs._muzzle_wrath, 0)
	assert_eq(cs._muzzle_greed, 0)


func test_step_outside_firing_does_not_clear_wrath() -> void:
	var cs := _rush()
	cs._muzzle_wrath = 2
	cs._muzzle_wrath_t = CombatConstants.MUZZLE_DURATION_WRATH_SEC
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	cs.reset_enemy_glide()
	cs.advance_enemy_glide(1.0)
	assert_eq(cs._muzzle_wrath, 2, "落格拍不再清愤怒")


func test_lose_mid_load_session_ends_session() -> void:
	var cs := _rush()
	_fill_bag_white(cs, 10)
	assert_true(_manual_load_one(cs))
	cs.player_hp = 0
	cs._lose_hp()
	assert_false(cs.is_busy_loading())
	assert_false(cs.can_manual_load())
	assert_false(cs.can_fire())


func test_multiple_attackers_each_hit_on_step() -> void:
	var cs := _rush()
	cs.enemies.resize(1)
	var a: EnemyInstance = cs.enemies[0]
	a.cell = 1
	a.atk = 2
	a.attack_range = 1
	var b: EnemyInstance = _add_enemy(cs, 2)
	b.atk = 3
	b.attack_range = 2
	cs.player_hp = 50
	cs.player_max_hp = 50
	cs.reset_enemy_glide()
	cs.advance_enemy_glide(1.0)
	assert_eq(cs.player_hp, 50 - 2 - 3)


func test_enemy_kills_player_ends_and_stops_glide() -> void:
	var cs := _rush()
	cs.enemies.resize(1)
	var a: EnemyInstance = cs.enemies[0]
	a.cell = 1
	a.atk = 999
	cs.reset_enemy_glide()
	cs.advance_enemy_glide(1.0)
	assert_eq(cs.phase, CombatState.Phase.LOST)
	assert_eq(cs.advance_enemy_glide(5.0), 0)


func test_fire_with_only_empty_chambers_is_rejected() -> void:
	var cs := _rush()
	cs.magazine.clear()
	cs._set_phase(CombatState.Phase.AWAIT_ACTION)
	assert_false(cs.can_fire())
	assert_false(cs.begin_fire())
