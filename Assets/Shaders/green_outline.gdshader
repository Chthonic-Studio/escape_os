shader_type canvas_item;

// Green outline shader that fades out over time.
// Applied to NPC sprites when they receive a comms signal.

uniform float outline_width : hint_range(0.0, 5.0) = 2.0;
uniform vec4 outline_color : source_color = vec4(0.3, 1.0, 0.3, 1.0);
uniform float fade_progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	
	if (col.a < 0.1) {
		// Check neighboring pixels for an edge
		vec2 ps = TEXTURE_PIXEL_SIZE * outline_width;
		float a = 0.0;
		a += texture(TEXTURE, UV + vec2(-ps.x, 0.0)).a;
		a += texture(TEXTURE, UV + vec2(ps.x, 0.0)).a;
		a += texture(TEXTURE, UV + vec2(0.0, -ps.y)).a;
		a += texture(TEXTURE, UV + vec2(0.0, ps.y)).a;
		a += texture(TEXTURE, UV + vec2(-ps.x, -ps.y)).a;
		a += texture(TEXTURE, UV + vec2(ps.x, -ps.y)).a;
		a += texture(TEXTURE, UV + vec2(-ps.x, ps.y)).a;
		a += texture(TEXTURE, UV + vec2(ps.x, ps.y)).a;
		
		if (a > 0.0) {
			col = outline_color;
			col.a *= (1.0 - fade_progress);
		}
	}
	
	COLOR = col;
}
