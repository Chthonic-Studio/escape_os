shader_type canvas_item;

uniform vec4 color : source_color = vec4(1.0, 0.2, 0.2, 1.0); // Cyberdyne Red
uniform float ring_radius : hint_range(0.0, 1.0) = 0.0;
uniform float thickness : hint_range(0.0, 0.5) = 0.1;

void fragment() {
	// Center UV coordinates (0,0 is now the center)
	vec2 uv = UV - 0.5;
	float dist = length(uv) * 2.0; // Distance from center (0.0 to 1.0 at edges)
	
	// Create a soft ring using smoothstep for anti-aliasing
	float alpha = smoothstep(ring_radius - thickness, ring_radius, dist) 
				- smoothstep(ring_radius, ring_radius + thickness, dist);
				
	// Fade out the entire effect as it expands towards the edges
	alpha *= (1.0 - ring_radius);
	
	COLOR = vec4(color.rgb, alpha * color.a);
}