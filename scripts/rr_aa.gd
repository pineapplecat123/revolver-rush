extends Object
class_name RrAa
## v0.4.31：全局抗锯齿开关。false = 全关（Web/兼容省 GPU）；改 true 可整包恢复。
const ENABLED := false


static func line() -> bool:
	return ENABLED


static func poly() -> bool:
	return ENABLED


static func apply_to_viewport(vp: Viewport) -> void:
	## 关闭 MSAA / FXAA / TAA（Compatibility 下 TAA 本就无效，一并关）。
	if vp == null:
		return
	if ENABLED:
		return
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false


static func apply_project_defaults() -> void:
	## 运行时再钉一次工程默认（与 project.godot 一致）。
	if ENABLED:
		return
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_2d", 0)
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/screen_space_aa", 0)
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/use_taa", false)
