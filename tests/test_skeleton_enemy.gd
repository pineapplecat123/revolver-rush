extends GutTest
## 小动物怪：场景可实例化、物种映射、动画齐全；棋盘挂载后受击/死亡可播。


const SCENE := "res://scenes/enemy/skeleton_enemy.tscn"
const IDS := [1, 2, 3, 4, 5, 900]


func _make(def_id: int) -> SkeletonEnemy:
	var p: SkeletonEnemy = (load(SCENE) as PackedScene).instantiate() as SkeletonEnemy
	p.setup(def_id)
	add_child_autofree(p)
	return p


func test_species_mapping_and_bones() -> void:
	var expect := {
		1: "rabbit", 2: "raccoon", 3: "bear", 4: "bat", 5: "pig", 900: "dummy"
	}
	for id in IDS:
		var p := _make(id)
		assert_eq(p.species, expect[id], "id %d" % id)
		assert_true(p.skeleton is Skeleton2D)
		assert_true(p.bones.has("Hip") and p.bones.has("Head"))
		assert_true(p.anim.has_animation(&"idle"))
		assert_true(p.anim.has_animation(&"walk"))
		assert_true(p.anim.has_animation(&"attack"))
		assert_true(p.anim.has_animation(&"hurt"))
		assert_true(p.anim.has_animation(&"death"))
		assert_not_null(p.status_anchor)
		if id == 5:
			assert_true(p.is_boss)
			assert_gt(p.scale.x, 1.3)
		if id == 900:
			assert_true(p.is_dummy)


func test_walk_attack_death_flow() -> void:
	var p := _make(2)
	assert_eq(p.current_animation(), &"idle")
	p.set_moving(true)
	assert_eq(p.current_animation(), &"walk")
	p.set_moving(false)
	assert_eq(p.current_animation(), &"idle")
	p.play_attack()
	assert_eq(p.current_animation(), &"attack")
	p.anim.advance(0.5)
	assert_eq(p.current_animation(), &"idle")
	p.play_hurt()
	assert_eq(p.current_animation(), &"hurt")
	p.play_death()
	assert_true(p.is_dead)
	assert_eq(p.current_animation(), &"death")
	p.set_moving(true)
	assert_eq(p.current_animation(), &"death", "死后不走路")
	p.play_attack()
	assert_eq(p.current_animation(), &"death", "死后不攻击")


func test_dummy_ignores_walk_and_attack() -> void:
	var p := _make(900)
	p.set_moving(true)
	assert_eq(p.current_animation(), &"idle")
	p.play_attack()
	assert_eq(p.current_animation(), &"idle")
	p.play_hurt()
	assert_eq(p.current_animation(), &"hurt")


func test_combat_ui_mounts_animals_on_enemy_cells() -> void:
	var ui = (load("res://scenes/combat.tscn") as PackedScene).instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	var st = ui.state
	st.sandbox_clear_enemies()
	st.sandbox_spawn_enemy(1, 4)
	st.sandbox_spawn_enemy(5, 7)
	st.sandbox_spawn_dummy(50, 2)
	ui._refresh()
	await wait_frames(2)
	assert_eq(ui._skel_enemies.size(), 3)
	var rabbit: SkeletonEnemy = null
	var pig: SkeletonEnemy = null
	var dummy: SkeletonEnemy = null
	for e in st.enemies:
		var sk: SkeletonEnemy = ui._skel_enemies[e.get_instance_id()]
		match int(e.def_id):
			1: rabbit = sk
			5: pig = sk
			900: dummy = sk
	assert_not_null(rabbit)
	assert_eq(rabbit.species, "rabbit")
	assert_eq(rabbit.get_parent(), ui.board_row.get_child(4).get_node("UnitBody"))
	assert_not_null(pig)
	assert_true(pig.is_boss)
	assert_not_null(dummy)
	assert_true(dummy.is_dummy)
	# 攻击信号 → 播 attack
	st.enemy_attacked.emit(st.enemies[0], "player")
	# 找非木桩
	for e in st.enemies:
		if int(e.def_id) == 1:
			assert_eq(ui._skel_enemies[e.get_instance_id()].current_animation(), &"attack")
