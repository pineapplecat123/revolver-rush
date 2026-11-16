extends GutTest
## v0.4.51：待机时头和持枪手臂跟身子同一节奏，但晚一拍再下点。


func test_version_0_4_51() -> void:
	assert_eq(GameVersion.STRING, "0.4.51")
	assert_true("0.4.51" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("晚一拍再跟上" in FileAccess.get_file_as_string("res://data/changelog.json"))


func _make_cat() -> SkeletonPlayer:
	var p: SkeletonPlayer = SkeletonPlayer.new()
	add_child_autofree(p)
	return p


func test_head_and_arms_bob_same_path_but_lag_one_beat() -> void:
	var p := _make_cat()
	await wait_frames(1)
	p.anim.play(&"idle")
	var beat: float = SkeletonPlayer.IDLE_BEAT
	var length: float = beat * 4.0
	assert_almost_eq(SkeletonPlayer.IDLE_HEAD_LAG, beat, 0.001)
	var torso0: Vector2 = p.REST["Torso"][0]
	var head0: Vector2 = p.REST["Head"][0]
	var arm0: Vector2 = p.REST["UpperArmF"][0]
	# t=0：身子在前端下点，头和手臂还在上一拍的抬起位置（相对身子向上）
	p.anim.seek(0.0, true)
	assert_gt(p.bones["Torso"].position.y, torso0.y + 1.5, "body dips first")
	assert_lt(p.bones["Head"].position.y, head0.y - 2.0, "head still up when body dips")
	assert_lt(p.bones["UpperArmF"].position.y, arm0.y - 2.0, "gun arm still up when body dips")
	assert_almost_eq(p.bones["Hip"].position.y, p.REST["Hip"][0].y, 0.02)
	assert_almost_eq(p.bones["ThighF"].rotation, p.REST["ThighF"][1], 0.001)
	# 头晚一拍才下点；此时身子已到中间抬起
	p.anim.seek(SkeletonPlayer.IDLE_HEAD_LAG, true)
	assert_lt(p.bones["Torso"].position.y, torso0.y - 0.5, "body has already lifted")
	assert_gt(p.bones["Head"].position.y, head0.y + 2.0, "head dips a beat later")
	# 持枪手臂稍再晚一点
	p.anim.seek(SkeletonPlayer.IDLE_ARM_LAG, true)
	assert_gt(p.bones["UpperArmF"].position.y, arm0.y + 2.0, "gun arm dips after the head")
	assert_gt(p.bones["UpperArmB"].position.y, p.REST["UpperArmB"][0].y + 1.5)
	# 世界路径就是身子路径延后 lag：本地 = follow_local
	var loc: Vector2 = SkeletonPlayer.idle_follow_local(0.0, length, SkeletonPlayer.IDLE_HEAD_LAG)
	assert_lt(loc.y, -2.0)
	var loc2: Vector2 = SkeletonPlayer.idle_follow_local(SkeletonPlayer.IDLE_HEAD_LAG, length, SkeletonPlayer.IDLE_HEAD_LAG)
	assert_gt(loc2.y, 2.0)
	assert_eq(p.current_animation(), &"idle")


func test_idle_still_blends_after_secondary_motion() -> void:
	var p := _make_cat()
	await wait_frames(1)
	p.anim.play(&"idle")
	p.anim.seek(SkeletonPlayer.IDLE_BEAT * 1.25, true)
	p.play_shoot()
	assert_eq(p.current_animation(), &"shoot")
	p.anim.advance(0.5)
	assert_eq(p.current_animation(), &"idle", "shoot should return to idle")
