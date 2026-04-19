shader_type canvas_item;

// Replaces the body color (#9badb7) with the NPC's class color.
uniform vec4 class_color : source_color = vec4(0.608, 0.678, 0.718, 1.0);
uniform float tolerance : hint_range(0.0, 0.3) = 0.08;

const vec3 BODY_COLOR = vec3(0.608, 0.678, 0.718); // #9badb7

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float diff = distance(tex.rgb, BODY_COLOR);
	// Skip nearly-transparent pixels to avoid recoloring anti-aliased edges and empty space
	if (diff <= tolerance && tex.a > 0.01) {
		COLOR = vec4(class_color.rgb, tex.a);
	} else {
		COLOR = tex;
	}
}
