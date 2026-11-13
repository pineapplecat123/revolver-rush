shader_type canvas_item;
render_mode blend_premul_alpha;

// Quantize a CanvasGroup (or any canvas item) to nearest-neighbor pixels.
// pixel_size is in screen/texel pixels; 2 matches the pixelfx 1.75x scale closely.
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;

void fragment() {
	vec2 tex_px = vec2(textureSize(TEXTURE, 0));
	float ps = max(pixel_size, 1.0);
	vec2 snapped = (floor(UV * tex_px / ps) + 0.5) * ps / tex_px;
	COLOR = texture(TEXTURE, snapped);
}
