extends GutTest

const MainScene := preload("res://scenes/main.tscn")


func test_sanity() -> void:
	assert_eq(1 + 1, 2, "math works")


func test_main_scene_shows_title() -> void:
	var main = add_child_autofree(MainScene.instantiate())
	assert_eq(main.get_title(), "Revolver Rush")
	assert_eq(main.get_node("%TitleLabel").text, "Revolver Rush")
	assert_eq(main.get_node("%BtnStart").text, "rush!")
	assert_null(main.get_node_or_null("%BtnEndless"), "endless mode removed")
	assert_null(main.get_node_or_null("%BtnPractice"), "practice mode removed")
