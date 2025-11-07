shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded, depth_prepass_alpha;

// Visibility texture - R channel contains visibility data
// 0 = unexplored (black), 127 = explored (grey), 255 = visible (transparent)
uniform sampler2D visibility_map : filter_linear;

// Map dimensions
uniform vec2 map_size = vec2(128.0, 128.0);

// Fog colors
uniform vec4 unexplored_color : source_color = vec4(0.0, 0.0, 0.0, 1.0); // Black
uniform vec4 explored_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);   // Semi-transparent black/grey
uniform float visible_alpha = 0.0; // Fully transparent when visible

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Convert world position to UV coordinates (0-1 range)
	vec2 uv = vec2(world_pos.x / map_size.x, world_pos.z / map_size.y);

	// Clamp UV to valid range
	uv = clamp(uv, vec2(0.0), vec2(1.0));

	// Sample visibility map (R channel contains visibility state)
	float visibility = texture(visibility_map, uv).r;

	// Determine fog color and alpha based on visibility value
	// 0.0 - 0.4 = unexplored (black fog)
	// 0.4 - 0.9 = explored (grey fog)
	// 0.9 - 1.0 = visible (no fog)

	vec4 fog_color;
	if (visibility < 0.4) {
		// Unexplored - full black
		fog_color = unexplored_color;
	} else if (visibility < 0.9) {
		// Explored - grey fog (semi-transparent)
		fog_color = explored_color;
	} else {
		// Visible - no fog (fully transparent)
		fog_color = vec4(0.0, 0.0, 0.0, visible_alpha);
	}

	ALBEDO = fog_color.rgb;
	ALPHA = fog_color.a;
}
