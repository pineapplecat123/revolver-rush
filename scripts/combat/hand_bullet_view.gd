class_name HandBulletView
extends Control
## 手里的弹药：和袋里一样画成圆，单色填充、字始终正向。

var ammo_id: int = 1
var fill: Color = Color(0.7, 0.7, 0.7, 1.0)
var fg: Color = Color(0.07, 0.07, 0.08, 1.0)
var glyph: String = ""
var temporary: bool = false


func setup(aid: int, colors: Dictionary, g: String, is_temp: bool = false) -> void:
	ammo_id = aid
	fill = colors.get("bg", fill)
	fg = colors.get("fg", fg)
	glyph = g
	temporary = is_temp
	# 与袋内半透明、转轮仓 0.48 一致：临时/打出即毁复制体入手后仍半透明。
	modulate = Color(1, 1, 1, 0.48) if temporary else Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var h: float = maxf(minf(size.x, size.y) * 0.92, 8.0)
	var mid: Vector2 = size * 0.5
	BagPhysicsBox.stamp_bag_bullet(self, mid, h, 0.0, fill)
	var font := get_theme_default_font()
	if font == null or glyph.is_empty():
		return
	var fsize: int = BagPhysicsBox.label_font_size_for_height(h)
	var ts := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var off := Vector2(-ts.x * 0.5, -ts.y * 0.5 + font.get_ascent(fsize))
	var oc := Color(0.08, 0.08, 0.1, 0.7) if fg.r + fg.g + fg.b > 1.6 else Color(1, 1, 1, 0.35)
	draw_string_outline(font, mid + off, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 2, oc)
	draw_string(font, mid + off, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, fg)
