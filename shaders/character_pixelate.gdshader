shader_type canvas_item;
render_mode unshaded, blend_mix;

// CanvasGroup writes a premultiplied backbuffer. A custom material must sample
// hint_screen_texture at SCREEN_UV (the built-in CanvasGroup shader does this).
// Sampling TEXTURE with blend_premul_alpha treated the group's clear color as
// straight-alpha white (1,1,1,0), which composited into an opaque white rect
// behind the character.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE * max(pixel_size, 1.0);
	vec2 uv = (floor(SCREEN_UV / ps) + 0.5) * ps;
	vec4 c = textureLod(screen_texture, uv, 0.0);
	if (c.a < 0.001) {
		discard;
	}
	c.rgb /= c.a;
	COLOR *= c;
}
