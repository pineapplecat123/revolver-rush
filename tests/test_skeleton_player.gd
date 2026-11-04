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
	assert_true(p.skeleton.get_bone_count() >= 13, "13 根骨")
	for bn in ["Hip", "Torso", "Head", "UpperArmF", "ForearmF", "HandF", "UpperArmB", "ForearmB", "HandB", "ThighF", "ShinF", "ThighB", "ShinB"]:
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
