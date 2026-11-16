extends GutTest
## v0.4.51：待机时头和持枪手臂跟身子同一节奏，但晚一拍再下点。


func test_version_is_at_least_0_4_51() -> void:
	assert_true(GameVersion.STRING.naturalnocasecmp_to("0.4.51") >= 0)
	assert_true("0.4.51" in FileAccess.get_file_as_string("res://data/changelog.json"))
	assert_true("晚一拍再跟上" in FileAccess.get_file_as_string("res://data/changelog.json"))


func _make_cat() -> SkeletonPlayer:
	var p: SkeletonPlayer = SkeletonPlayer.new()
	add_child_autofree(p)
	return p


func test_head_and_arms_bob_same_path_but_lag_one_beat() -> void:
	## v0.4.52 起滞后改短，这里只保留身子下点和脚站住；贴合与短滞后见 0.4.52。
	var p := _make_cat()
	await wait_frames(1)
	p.anim.play(&"idle")
	var torso0: Vector2 = p.REST["Torso"][0]
	p.anim.seek(0.0, true)
	assert_gt(p.bones["Torso"].position.y, torso0.y + 1.5, "body dips first")
	assert_almost_eq(p.bones["Hip"].position.y, p.REST["Hip"][0].y, 0.02)
	assert_almost_eq(p.bones["ThighF"].rotation, p.REST["ThighF"][1], 0.001)
	assert_eq(p.current_animation(), &"idle")
	assert_lt(SkeletonPlayer.IDLE_HEAD_LAG, SkeletonPlayer.IDLE_BEAT * 0.25)


func test_idle_still_blends_after_secondary_motion() -> void:
	var p := _make_cat()
	await wait_frames(1)
	p.anim.play(&"idle")
	p.anim.seek(SkeletonPlayer.IDLE_BEAT * 1.25, true)
	p.play_shoot()
	assert_eq(p.current_animation(), &"shoot")
	p.anim.advance(0.5)
	assert_eq(p.current_animation(), &"idle", "shoot should return to idle")
