shader_type canvas_item;

// Shareholder Value glow outline for NPC box outlines.
// Glow intensity scales with shareholder value (0.0 = no glow, 1.0 = max glow).
// When shareholder_value >= 1, glow green. When < 0, glow a red-green mix.

uniform float glow_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float is_negative : hint_range(0.0, 1.0) = 0.0;
uniform float time_offset : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	// Base green glow color
	vec3 positive_color = vec3(0.2, 0.85, 0.3);
	// Negative shareholder value: red-green sickly mix
	vec3 negative_color = vec3(0.8, 0.4, 0.15);

	vec3 glow_color = mix(positive_color, negative_color, is_negative);

	// Pulsing effect based on TIME for a subtle living glow
	float pulse = 0.85 + 0.15 * sin(TIME * 2.0 + time_offset);

	// Apply glow as additive color on existing pixels
	if (col.a > 0.1) {
		// Blend glow into existing color
		float effective_glow = glow_intensity * pulse * 0.6;
		col.rgb = mix(col.rgb, glow_color, effective_glow);
		// Increase alpha slightly for visibility
		col.a = clamp(col.a + effective_glow * 0.4, 0.0, 1.0);
	}

	COLOR = col;
}
