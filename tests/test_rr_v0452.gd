extends GutTest
## v0.4.52：头和持枪手臂稍晚跟上同一节奏，且始终贴在身上。


func test_version_0_4_52() -> void:
	assert_eq(GameVersion.STRING, "0.4.52")
	assert_true("0.4.52" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("一直连在一起" in FileAccess.get_file_as_string("res://data/changelog.json"))


func _make_cat() -> SkeletonPlayer:
	var p: SkeletonPlayer = SkeletonPlayer.new()
	add_child_autofree(p)
	return p


func test_head_lag_is_short_and_stays_attached() -> void:
	var p := _make_cat()
	await wait_frames(1)
	p.anim.play(&"idle")
	var beat: float = SkeletonPlayer.IDLE_BEAT
	var length: float = beat * 4.0
	assert_gte(SkeletonPlayer.IDLE_HEAD_LAG, 0.04)
	assert_lte(SkeletonPlayer.IDLE_HEAD_LAG, 0.06)
	assert_gt(SkeletonPlayer.IDLE_ARM_LAG, SkeletonPlayer.IDLE_HEAD_LAG)
	assert_lte(SkeletonPlayer.IDLE_ARM_LAG, SkeletonPlayer.IDLE_HEAD_LAG + 0.05)
	var head0: Vector2 = p.REST["Head"][0]
	var arm0: Vector2 = p.REST["UpperArmF"][0]
	var armb0: Vector2 = p.REST["UpperArmB"][0]
	var lim: float = SkeletonPlayer.IDLE_FOLLOW_MAX + 0.08
	# 整圈采样：头和手臂相对静止点的位移不超过限制
	for i in 25:
		var tt: float = length * float(i) / 24.0
		p.anim.seek(tt, true)
		assert_lte((p.bones["Head"].position - head0).length(), lim, "head stays on the body")
		assert_lte((p.bones["UpperArmF"].position - arm0).length(), lim, "gun arm stays on the shoulder")
		assert_lte((p.bones["UpperArmB"].position - armb0).length(), lim)
		var loc: Vector2 = SkeletonPlayer.idle_follow_local(tt, length, SkeletonPlayer.IDLE_HEAD_LAG)
		assert_lte(loc.length(), SkeletonPlayer.IDLE_FOLLOW_MAX + 0.001)
	# 下点瞬间身子先动，头稍晚但仍贴着
	p.anim.seek(0.0, true)
	assert_gt(p.bones["Torso"].position.y, p.REST["Torso"][0].y + 1.5)
	var at0: Vector2 = SkeletonPlayer.idle_follow_local(0.0, length, SkeletonPlayer.IDLE_HEAD_LAG)
	assert_lt(at0.y, -0.05, "head still a little up when the body dips")
	assert_gt(at0.y, -SkeletonPlayer.IDLE_FOLLOW_MAX - 0.001)
	p.anim.seek(SkeletonPlayer.IDLE_HEAD_LAG, true)
	var at_lag: Vector2 = SkeletonPlayer.idle_follow_local(SkeletonPlayer.IDLE_HEAD_LAG, length, SkeletonPlayer.IDLE_HEAD_LAG)
	assert_gt(at_lag.y, 0.0)
	assert_eq(p.current_animation(), &"idle")
	assert_almost_eq(p.bones["Hip"].position.y, p.REST["Hip"][0].y, 0.02)


func test_idle_still_blends_to_shoot() -> void:
	var p := _make_cat()
	await wait_frames(1)
	p.anim.play(&"idle")
	p.anim.seek(SkeletonPlayer.IDLE_BEAT * 1.25, true)
	p.play_shoot()
	assert_eq(p.current_animation(), &"shoot")
	p.anim.advance(0.5)
	assert_eq(p.current_animation(), &"idle")
