extends RefCounted
## 把代码绘制的骨骼小人画进 CanvasGroup，再用邻近取样放大，做出和 pixelfx 接近的像素风。
## 只包 Rig，血条/数字/状态环留在外面保持清晰。像素格取 2px（最接近 PIXELfx 的 1.75 倍）。

const PIXEL_SIZE := 2.0
const SHADER := preload("res://shaders/character_pixelate.gdshader")


static func attach(host: Node2D, rig: Node2D) -> CanvasGroup:
	var g := CanvasGroup.new()
	g.name = "PixelRig"
	g.fit_margin = 16.0
	g.z_index = rig.z_index
	g.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("pixel_size", PIXEL_SIZE)
	g.material = mat
	host.add_child(g)
	g.add_child(rig)
	return g
