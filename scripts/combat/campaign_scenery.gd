class_name CampaignScenery
extends Control
## 闯关侧向景物：小猫在玩家格锚定，背景相对平移表示在走。不挡输入、不改格子几何。

var scroll_x: float = 0.0
var active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	clip_contents = true


func set_scroll(x: float, on: bool) -> void:
	active = on
	scroll_x = x
	visible = on
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var sz: Vector2 = size
	if sz.x < 8.0 or sz.y < 8.0:
		return
	# 远景色带
	var sky := Color(0.22, 0.28, 0.36, 0.80)
	draw_rect(Rect2(Vector2.ZERO, sz), sky)
	var ground_y: float = sz.y * 0.78
	draw_rect(Rect2(0.0, ground_y, sz.x, sz.y - ground_y), Color(0.28, 0.30, 0.22, 0.70))
	_draw_layer(sz, ground_y, 180.0, 0.35, Color(0.16, 0.20, 0.26, 0.70), 10.0, true)
	_draw_layer(sz, ground_y, 110.0, 0.70, Color(0.12, 0.16, 0.14, 0.80), 6.0, false)
	_draw_layer(sz, ground_y, 70.0, 1.00, Color(0.10, 0.12, 0.11, 0.90), 3.0, false)


func _draw_layer(sz: Vector2, ground_y: float, spacing: float, parallax: float, col: Color, seed_k: float, hills: bool) -> void:
	var off: float = fposmod(scroll_x * parallax, spacing)
	var x: float = -off - spacing
	var i := 0
	while x < sz.x + spacing:
		var jitter: float = fposmod(seed_k * 17.0 + float(i) * 13.0, 11.0) - 5.0
		if hills:
			var h: float = 28.0 + fposmod(float(i) * 9.0 + seed_k, 22.0)
			var w: float = spacing * 0.7
			var pts := PackedVector2Array([
				Vector2(x - 4.0, ground_y + 4.0),
				Vector2(x + w * 0.5 + jitter, ground_y - h),
				Vector2(x + w + 4.0, ground_y + 4.0),
			])
			draw_colored_polygon(pts, col)
		else:
			var trunk_h: float = 22.0 + fposmod(float(i) * 7.0 + seed_k, 18.0)
			var tx: float = x + jitter
			draw_rect(Rect2(tx, ground_y - trunk_h, 4.0, trunk_h), col)
			var canopy := Vector2(tx + 2.0, ground_y - trunk_h - 2.0)
			draw_circle(canopy, 10.0 + fposmod(float(i) * 3.0, 6.0), col)
		x += spacing
		i += 1
