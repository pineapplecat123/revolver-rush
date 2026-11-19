extends GutTest
## v0.4.65：普通僵尸按自己走完的格子再生；小猫原地走路循环，开火/转枪后能回待机或继续走。


const CIV := 1
const ZOMBIE := CombatConstants.ZOMBIE_ENEMY_ID
const SUPER := CombatConstants.SUPER_ZOMBIE_ENEMY_ID
const OWN_CELL := CombatConstants.ZOMBIE_AUTO_STEP_SEC / CombatConstants.ENEMY_AUTO_STEP_SEC


func before_each() -> void:
	DataRegistry.reload()
	CombatState.boot_sandbox = false


func after_each() -> void:
	CombatState.boot_sandbox = false


func _fw(seed_v: int) -> CombatState:
	var cs := CombatState.new(seed_v)
	cs.free_walk = true
	cs.start_rush(seed_v)
	cs.spawn_paused = true
	cs.enemies.clear()
	return cs


func _put(cs: CombatState, def_id: int, cell: int, hp: int = -1) -> EnemyInstance:
	var e := EnemyInstance.new(DataRegistry.get_enemy(def_id), cell)
	if hp >= 0:
		e.max_hp = hp
		e.hp = hp
	e.pos_x = float(cell)
	e.speed_mul = 1.0
	e.atk = 0
	cs.enemies.append(e)
	return e


func _cat() -> SkeletonPlayer:
	var p: SkeletonPlayer = SkeletonPlayer.new()
	add_child_autofree(p)
	return p


func test_version_is_at_least_0_4_65() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.65") >= 0)
	var log := FileAccess.get_file_as_string("res://data/changelog.json")
	assert_true("0.4.65" in log)
	assert_true("走完一格" in log)
	assert_true("走路" in log)


func test_ordinary_zombie_regens_exactly_two_per_own_cell() -> void:
	var cs := _fw(46501)
	var z := _put(cs, ZOMBIE, 8, 20)
	z.hp = 10
	# 没走满一格：不回血
	cs.advance_enemy_glide(OWN_CELL * 0.4)
	assert_almost_eq(z.pos_x, 8.0 - 0.4, 0.0001)
	assert_eq(z.cell, 8)
	assert_eq(z.hp, 10)
	# 再走完这一格：恰好 +2
	cs.advance_enemy_glide(OWN_CELL * 0.6)
	assert_almost_eq(z.pos_x, 7.0, 0.0001)
	assert_eq(z.cell, 7)
	assert_eq(z.hp, 12, "每实际走完一格恰好 +2")
	# 再走两格：再 +4
	cs.advance_enemy_glide(OWN_CELL * 2.0)
	assert_almost_eq(z.pos_x, 5.0, 0.0001)
	assert_eq(z.cell, 5)
	assert_eq(z.hp, 16)


func test_ordinary_zombie_no_regen_when_stationary_or_on_global_tick() -> void:
	var cs := _fw(46502)
	var stop_x: float = float(CombatConstants.PLAYER_CELL + 1)
	var z := _put(cs, ZOMBIE, CombatConstants.PLAYER_CELL + 1, 20)
	z.hp = 10
	z.pos_x = stop_x
	for _i in 8:
		cs.advance_enemy_glide(OWN_CELL)
		cs._tick_zombie_regen_end_of_enemy_turn()
	assert_almost_eq(z.pos_x, stop_x, 0.0001)
	assert_eq(z.hp, 10, "停在玩家面前不回血，也不吃全局拍")


func test_super_and_other_enemies_regen_unchanged() -> void:
	var cs := _fw(46503)
	var s := _put(cs, SUPER, CombatConstants.PLAYER_CELL + 1, 50)
	var c := _put(cs, CIV, 8, 10)
	s.hp = 40
	s.pos_x = float(CombatConstants.PLAYER_CELL + 1)
	c.hp = 6
	cs._tick_zombie_regen_end_of_enemy_turn()
	assert_eq(s.hp, 45, "超级僵尸停着仍按落格拍 +5")
	assert_eq(c.hp, 6, "其他敌人不再生")
	# 再走普通 3.3 秒一格时，超级僵尸仍走全局落格拍（又 +5），不是普通僵尸那套走格。
	cs.advance_enemy_glide(1.0)
	assert_eq(c.hp, 6)
	assert_eq(s.hp, 50, "超级僵尸仍按全局落格拍再生，上限 50")


func test_summoned_ordinary_zombie_also_regens_per_own_cell() -> void:
	var cs := _fw(46504)
	var z := _put(cs, ZOMBIE, 6, 20)
	z.hp = 8
	cs.advance_enemy_glide(OWN_CELL)
	assert_eq(z.hp, 10)
	assert_eq(CombatConstants.zombie_regen_amount(z.def_id), 2)


func test_walk_cycle_moves_legs_and_keeps_head_attached() -> void:
	var p := _cat()
	await wait_process_frames(1)
	assert_true(p.anim.has_animation(&"walk"))
	assert_true(p.anim.get_animation(&"walk").loop_mode == Animation.LOOP_LINEAR)
	assert_almost_eq(p.anim.get_animation(&"walk").length, SkeletonPlayer.WALK_LEN, 0.0001)
	p.set_walking(true)
	assert_true(p.is_walking())
	assert_eq(p.current_animation(), SkeletonPlayer.ANIM_WALK)
	p.anim.play(SkeletonPlayer.ANIM_WALK, 0.0)
	var head0: Vector2 = p.REST["Head"][0]
	var arm0: Vector2 = p.REST["UpperArmF"][0]
	var thf0: float = p.REST["ThighF"][1]
	var thb0: float = p.REST["ThighB"][1]
	var saw_leg := false
	var lim: float = SkeletonPlayer.WALK_FOLLOW_MAX + 0.08
	for i in 17:
		var tt: float = SkeletonPlayer.WALK_LEN * float(i) / 16.0
		p.anim.seek(tt, true)
		assert_lte((p.bones["Head"].position - head0).length(), lim, "walk head stays on the body")
		assert_lte((p.bones["UpperArmF"].position - arm0).length(), lim, "walk gun arm stays on the shoulder")
		var loc: Vector2 = SkeletonPlayer.walk_follow_local(tt, SkeletonPlayer.WALK_LEN, SkeletonPlayer.IDLE_HEAD_LAG)
		assert_lte(loc.length(), SkeletonPlayer.WALK_FOLLOW_MAX + 0.001)
		if abs(p.bones["ThighF"].rotation - thf0) > 0.12 and abs(p.bones["ThighB"].rotation - thb0) > 0.12:
			saw_leg = true
	assert_true(saw_leg, "走路时应迈腿")
	# 左右腿应交错，不是同向摆
	p.anim.seek(SkeletonPlayer.WALK_LEN * 0.25, true)
	var df: float = p.bones["ThighF"].rotation - thf0
	var db: float = p.bones["ThighB"].rotation - thb0
	assert_true(df * db < 0.0, "左右腿交错")


func test_walk_stops_to_idle_and_fire_twirl_restore() -> void:
	var p := _cat()
	await wait_process_frames(1)
	p.set_walking(true)
	assert_eq(p.current_animation(), SkeletonPlayer.ANIM_WALK)
	p.set_walking(false)
	assert_false(p.is_walking())
	assert_eq(p.current_animation(), SkeletonPlayer.ANIM_IDLE)

	p.set_walking(true)
	p.play_shoot()
	assert_eq(p.current_animation(), SkeletonPlayer.ANIM_SHOOT)
	assert_true(p.is_walking(), "开火不关掉走路意愿")
	p.anim.advance(0.2)
	assert_eq(p.current_animation(), SkeletonPlayer.ANIM_WALK, "打完枪若仍在预览走，回到走路")

	p.play_gun_twirl(0.2)
	assert_eq(p.current_animation(), SkeletonPlayer.ANIM_TWIRL)
	# 转枪结束由 tween 回调；测试里手动收尾
	p._on_gun_twirl_finished(null)
	assert_eq(p.current_animation(), SkeletonPlayer.ANIM_WALK)

	p.set_walking(false)
	p.play_shoot()
	p.anim.advance(0.2)
	assert_eq(p.current_animation(), SkeletonPlayer.ANIM_IDLE, "关掉走路后开火应回到待机")


func test_sandbox_walk_preview_toggles_in_place() -> void:
	CombatState.boot_sandbox = true
	var ui = add_child_autofree(load("res://scenes/combat.tscn").instantiate())
	await wait_process_frames(3)
	assert_true(ui.state.sandbox_mode)
	if ui.get("_dev_open") != true:
		ui._toggle_dev()
	await wait_process_frames(2)
	var btn: Button = ui.dev_panel.find_child("SandboxWalkPreview", true, false) as Button
	assert_not_null(btn, "沙盒应有预览走路按钮")
	assert_not_null(ui._skel_player)
	assert_eq(ui._skel_player.current_animation(), SkeletonPlayer.ANIM_IDLE)
	ui._on_sandbox_walk_preview()
	assert_true(ui._skel_player.is_walking())
	assert_eq(ui._skel_player.current_animation(), SkeletonPlayer.ANIM_WALK)
	ui._on_sandbox_walk_preview()
	assert_false(ui._skel_player.is_walking())
	assert_eq(ui._skel_player.current_animation(), SkeletonPlayer.ANIM_IDLE)
	CombatState.boot_sandbox = false
