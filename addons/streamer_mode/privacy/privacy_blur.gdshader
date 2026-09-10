shader_type canvas_item;
render_mode blend_mix;

// Screen-reading privacy mask: pixelate + box-blur whatever is drawn behind
// this node, then tint it slightly so it reads as an intentional mask rather
// than a glitch. Works in the GL Compatibility renderer.
//
// PrivacyEngine places a BackBufferCopy behind the masks so hint_screen_texture
// has fresh contents on every renderer. The masks are drawn after that copy, so
// they never sample themselves or each other.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float pixel_size : hint_range(1.0, 80.0) = 14.0;   // block size, screen px
uniform float blur_spread : hint_range(0.0, 6.0) = 1.6;    // tap spacing, screen px
uniform vec4 tint : source_color = vec4(0.05, 0.07, 0.10, 1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.30;
uniform float feather : hint_range(0.0, 0.5) = 0.05;       // edge softness, local UV
uniform float fill_opacity : hint_range(0.0, 1.0) = 1.0;   // driven by the fade

const int R = 2; // (2R + 1)^2 = 25 taps

void fragment() {
	vec2 texel = SCREEN_PIXEL_SIZE;

	// Pixelate: quantise the sample position into square blocks.
	vec2 block = texel * max(pixel_size, 1.0);
	vec2 base_uv = (floor(SCREEN_UV / block) + 0.5) * block;

	// Box blur around the quantised position.
	vec3 acc = vec3(0.0);
	for (int x = -R; x <= R; x++) {
		for (int y = -R; y <= R; y++) {
			vec2 o = vec2(float(x), float(y)) * texel * blur_spread;
			acc += texture(screen_tex, base_uv + o).rgb;
		}
	}
	vec3 col = acc / float((2 * R + 1) * (2 * R + 1));

	// Neutral tint so the masked area looks deliberate on stream.
	col = mix(col, tint.rgb, tint_amount);

	// Feathered rectangular edge from this node's own UV.
	vec2 d = min(UV, vec2(1.0) - UV);
	float a = smoothstep(0.0, max(feather, 0.0001), min(d.x, d.y)) * fill_opacity;

	COLOR = vec4(col, a);
}
