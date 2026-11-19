class_name UiStyle
extends RefCounted
## v0.4.72 极简 UI：低饱和蓝灰、薄边或无边、半透明平底。弹药颜色仍作功能标识。

const TEXT := Color(0.86, 0.90, 0.93, 1.0)
const TEXT_DIM := Color(0.62, 0.68, 0.74, 1.0)
const TEXT_TITLE := Color(0.90, 0.93, 0.96, 1.0)
const TEXT_GOLD := Color(0.78, 0.72, 0.52, 1.0)
const TEXT_HP_OK := Color(0.62, 0.82, 0.70, 1.0)
const TEXT_HP_LOW := Color(0.86, 0.52, 0.50, 1.0)
const PANEL := Color(0.07, 0.09, 0.12, 0.82)
const PANEL_HEAVY := Color(0.06, 0.08, 0.11, 0.90)
const PANEL_MODAL := Color(0.10, 0.13, 0.16, 0.98)
const PANEL_GHOST := Color(0.06, 0.08, 0.11, 0.0)
const BORDER := Color(0.62, 0.70, 0.78, 0.22)
const BUTTON := Color(0.14, 0.17, 0.21, 0.86)
const BUTTON_HOVER := Color(0.20, 0.24, 0.29, 0.94)
const BUTTON_PRESSED := Color(0.10, 0.12, 0.16, 0.94)
const BUTTON_DISABLED := Color(0.10, 0.11, 0.13, 0.70)
const DIMMER := Color(0.02, 0.03, 0.05, 0.70)


static func panel_box(bg: Color = PANEL, border_alpha: float = 1.0, radius: int = 6, margin: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	var use_border := border_alpha > 0.01
	sb.set_border_width_all(1 if use_border else 0)
	sb.border_color = Color(BORDER.r, BORDER.g, BORDER.b, BORDER.a * border_alpha)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = maxi(4, margin - 2)
	sb.content_margin_bottom = maxi(4, margin - 2)
	return sb


static func button_box(bg: Color, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(1)
	sb.border_color = BORDER
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func apply_panel(panel: Control, bg: Color = PANEL, border_alpha: float = 1.0, radius: int = 6) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", panel_box(bg, border_alpha, radius))


static func apply_text_button(btn: Button) -> void:
	if btn == null:
		return
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", Color(0.95, 0.97, 0.99, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.88, 0.91, 0.94, 1.0))
	btn.add_theme_color_override("font_focus_color", TEXT)
	btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.58, 0.62, 0.8))
	btn.add_theme_stylebox_override("normal", button_box(BUTTON))
	btn.add_theme_stylebox_override("hover", button_box(BUTTON_HOVER))
	btn.add_theme_stylebox_override("pressed", button_box(BUTTON_PRESSED))
	btn.add_theme_stylebox_override("focus", button_box(BUTTON_HOVER))
	var dis := button_box(BUTTON_DISABLED)
	dis.border_color = Color(BORDER.r, BORDER.g, BORDER.b, 0.08)
	btn.add_theme_stylebox_override("disabled", dis)


static func apply_label(lab: Label, color: Color = TEXT, outline: bool = true) -> void:
	if lab == null:
		return
	lab.add_theme_color_override("font_color", color)
	if outline:
		lab.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.04, 0.7))
		lab.add_theme_constant_override("outline_size", 3)
