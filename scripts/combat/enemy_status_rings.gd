extends Control
class_name EnemyStatusRings
## 敌人头顶的小圆环：弧长 = 剩余时间比例。多状态并排，两行封顶，不挡身体。

const RING_SIZE := 18.0
const RING_GAP := 2.0
const COLS := 3

var entries: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_entries(next: Array) -> void:
	entries = next
	queue_redraw()


func _draw() -> void:
	var n := entries.size()
	if n <= 0:
		return
	var cols := mini(n, COLS)
	var total_w := float(cols) * RING_SIZE + float(maxi(cols - 1, 0)) * RING_GAP
	var x0 := (size.x - total_w) * 0.5
	var font := get_theme_default_font()
	for i in n:
		var e: Dictionary = entries[i]
		var col_i := i % COLS
		var row_i := int(i / COLS)
		var center := Vector2(
			x0 + float(col_i) * (RING_SIZE + RING_GAP) + RING_SIZE * 0.5,
			float(row_i) * (RING_SIZE + RING_GAP) + RING_SIZE * 0.5
		)
		var colr: Color = e.get("color", Color(1.0, 0.8, 0.3))
		var ratio: float = clampf(float(e.get("ratio", 1.0)), 0.0, 1.0)
		if ratio <= 0.25 and bool(e.get("timed", true)):
			colr = Color(1.0, 0.28, 0.18)
		var radius := RING_SIZE * 0.5 - 1.6
		draw_circle(center, radius, Color(0.05, 0.04, 0.03, 0.78))
		draw_arc(center, radius, 0.0, TAU, 28, Color(0.0, 0.0, 0.0, 0.9), 2.0, true)
		if ratio > 0.02:
			var a0 := -PI * 0.5
			var a1 := a0 + TAU * ratio
			draw_arc(center, radius, a0, a1, maxi(6, int(round(22.0 * ratio))), colr, 2.6, true)
		var label := str(e.get("label", ""))
		if font == null or label == "":
			continue
		var fs := 11
		var ascent := font.get_ascent(fs)
		var sz := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var baseline := center + Vector2(-sz.x * 0.5, ascent * 0.35)
		draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.97, 0.92))
