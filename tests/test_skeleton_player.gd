extends GutTest
## v0.4.21 骨骼动画玩家：场景可实例化、动画齐全、钩子驱动动作（纯表现）。

const SCENE := "res://scenes/player/skeleton_player.tscn"


func _make() -> SkeletonPlayer:
	var p: SkeletonPlayer = (load(SCENE) as PackedScene).instantiate() as SkeletonPlayer
	add_child_autofree(p)
	return p


func test_scene_instantiates_with_skeleton_and_revolver() -> void:
	var p := _make()
	assert_not_null(p)
	assert_true(p.skeleton is Skeleton2D)
	assert_true(p.skeleton.get_bone_count() >= 16, "13 根身体骨 + 3 节尾巴")
	for bn in ["Hip", "Torso", "Head", "UpperArmF", "ForearmF", "HandF", "UpperArmB", "ForearmB", "HandB", "ThighF", "ShinF", "ThighB", "ShinB", "Tail1", "Tail2", "Tail3"]:
		assert_true(p.bones.has(bn) and p.bones[bn] is Bone2D, bn)
	var gun: Node = p.bones["HandF"].get_node_or_null("Revolver")
	assert_not_null(gun, "左轮挂在持枪手骨上")
	assert_not_null(p.muzzle)


func test_animations_exist() -> void:
	var p := _make()
	for a in [&"idle", &"shoot", &"reload", &"hurt", &"death"]:
		assert_true(p.anim.has_animation(a), String(a))
	assert_eq(p.anim.get_animation(&"idle").loop_mode, Animation.LOOP_LINEAR)
	assert_lt(p.anim.get_animation(&"shoot").length, 0.25, "开枪要短促")
	assert_eq(p.current_animation(), &"idle")


func test_fire_hook_plays_shoot_and_rapid_fire_restarts() -> void:
	var p := _make()
	var cs := CombatState.new()
	p.bind_state(cs)
	cs.hooks.emit_hook(&"on_shot", {"cs": cs, "ammo_id": 1, "virtual": false, "dealt": 1})
	assert_eq(p.current_animation(), &"shoot")
	p.anim.advance(0.08)
	cs.hooks.emit_hook(&"on_shot", {"cs": cs, "ammo_id": 1, "virtual": false, "dealt": 1})
	assert_eq(p.current_animation(), &"shoot")
	assert_lt(p.anim.current_animation_position, 0.05, "连点从头再播")
	p.anim.advance(0.5)
	assert_eq(p.current_animation(), &"idle", "播完回待机")


func test_load_hurt_death_and_revive() -> void:
	var p := _make()
	var cs := CombatState.new()
	p.bind_state(cs)
	cs.hooks.emit_hook(&"on_chamber_loaded", {"cs": cs, "ammo_id": 1, "slot": 0, "temporary": false})
	assert_eq(p.current_animation(), &"reload")
	cs.player_hp = 10
	cs.player_damaged.emit(3, "")
	assert_eq(p.current_animation(), &"hurt")
	cs._set_phase(CombatState.Phase.LOST)
	assert_true(p.is_dead)
	assert_eq(p.current_animation(), &"death")
	cs.hooks.emit_hook(&"on_shot", {"cs": cs, "ammo_id": 1, "virtual": false, "dealt": 1})
	assert_eq(p.current_animation(), &"death", "死后不再开枪")
	cs._set_phase(CombatState.Phase.AWAIT_LOAD)
	assert_false(p.is_dead)
	assert_eq(p.current_animation(), &"idle")


func test_combat_ui_mounts_skeleton_on_player_cell() -> void:
	var ui = (load("res://scenes/combat.tscn") as PackedScene).instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	assert_not_null(ui._skel_player)
	var unit: Node = ui.board_row.get_child(CombatConstants.PLAYER_CELL).get_node("UnitBody")
	assert_eq(ui._skel_player.get_parent(), unit)
	ui.state.hooks.emit_hook(&"on_shot", {"cs": ui.state, "ammo_id": 1, "virtual": false, "dealt": 1})
	assert_eq(ui._skel_player.current_animation(), &"shoot")


func test_head_and_status_anchors_above_head() -> void:
	var p := _make()
	await wait_frames(1)
	assert_not_null(p.head_anchor)
	assert_not_null(p.status_anchor)
	var head_y: float = p.bones["Head"].global_position.y
	assert_lt(p.head_top_global_position().y, head_y, "锚点在头顶上方")
	assert_lt(p.status_anchor_global_position().y, p.head_top_global_position().y, "状态环在帽顶之上")


func test_cat_big_head_and_big_gun() -> void:
	var p := _make()
	await wait_frames(1)
	assert_gt(p.GUN_SCALE, 1.4, "左轮放大")
	assert_eq(p.bones["HandF"].get_node("Revolver").scale, Vector2(p.GUN_SCALE, p.GUN_SCALE))
	# 头（含耳）占全身 35%~50%：耳尖 ≈ head_anchor 附近，脚底 = 原点
	var total: float = -p.head_anchor.position.y - float(p.REST["Head"][0].y) - float(p.REST["Torso"][0].y) - float(p.REST["Hip"][0].y)
	var head_h: float = 40.0
	assert_between(head_h / total, 0.35, 0.5)
	assert_not_null(p.bones["Tail3"].get_parent() == p.bones["Tail2"])


func test_death_switches_to_x_eyes_and_revive_restores() -> void:
	var p := _make()
	p.play_death()
	p.anim.advance(1.2)
	assert_false(p.eyes.visible)
	assert_true(p.xeyes.visible)
	p.revive()
	p.anim.advance(0.05)
	assert_true(p.eyes.visible)
	assert_false(p.xeyes.visible)


func _barrel_angle(p: SkeletonPlayer) -> float:
	var sh: Vector2 = p.bones["UpperArmF"].global_position
	return (p.muzzle.global_position - sh).angle()


func test_aim_tracks_nearest_target_and_clamps() -> void:
	var p := _make()
	p.position = Vector2(100, 300)
	await wait_frames(1)
	p.anim.pause()
	var sh: Vector2 = p.bones["UpperArmF"].global_position
	# 目标在右下方 → 枪口往下压，对准目标
	var low := sh + Vector2(200, 80)
	p.set_aim_target(low)
	for _i in 60:
		p._unapply_aim()
		p.update_aim(1.0 / 30.0)
	assert_gt(p.aim_angle, 0.1, "往下瞄")
	assert_almost_eq(_barrel_angle(p), (low - p.bones["UpperArmF"].global_position).angle(), 0.08, "枪口指向目标")
	# 目标换到右上方 → 往上抬
	var high := sh + Vector2(200, -120)
	p.set_aim_target(high)
	for _i in 60:
		p._unapply_aim()
		p.update_aim(1.0 / 30.0)
	assert_lt(p.aim_angle, -0.1, "往上瞄")
	assert_almost_eq(_barrel_angle(p), (high - p.bones["UpperArmF"].global_position).angle(), 0.08)
	# 正上方：夹角，不会拧成麻花
	p.set_aim_target(sh + Vector2(1, -400))
	for _i in 60:
		p._unapply_aim()
		p.update_aim(1.0 / 30.0)
	assert_almost_eq(p.aim_angle, p.AIM_MIN, 0.02)
	# 没目标 → 回中
	p.set_aim_target(null)
	for _i in 90:
		p._unapply_aim()
		p.update_aim(1.0 / 30.0)
	assert_almost_eq(p.aim_angle, 0.0, 0.02)


func test_aim_is_additive_over_recoil() -> void:
	var p := _make()
	await wait_frames(1)
	var sh: Vector2 = p.bones["UpperArmF"].global_position
	p.set_aim_target(sh + Vector2(200, 80))
	for _i in 40:
		p._process(1.0 / 30.0)
	var applied0: float = p._applied_arm
	var anim_only0: float = p.bones["UpperArmF"].rotation - applied0
	assert_gt(applied0, 0.1, "瞄准偏转已叠上")
	p.play_shoot()
	for _i in 3:
		p._process(0.01)
	var anim_only1: float = p.bones["UpperArmF"].rotation - p._applied_arm
	assert_lt(anim_only1, anim_only0 - 0.05, "后坐（动画层）把手往上顶")
	assert_almost_eq(p._applied_arm, applied0, 0.05, "瞄准偏转仍叠在后坐之上")


func test_combat_ui_aims_at_nearest_enemy() -> void:
	var ui = (load("res://scenes/combat.tscn") as PackedScene).instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	var st = ui.state
	st.sandbox_clear_enemies()
	st.sandbox_spawn_dummy(999, 7)
	st.sandbox_spawn_dummy(999, 3)
	ui._refresh()
	await wait_frames(2)
	var tgt = ui._nearest_enemy_global()
	assert_true(tgt is Vector2)
	assert_almost_eq((tgt as Vector2).x, ui._cell_unit_global_center(3).x, 1.0, "最近的是 3 号格")
