shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 5.0) = 2.0;
uniform vec4 tint_color : source_color = vec4(0.1, 0.1, 0.15, 0.7);
uniform float edge_brightness : hint_range(0.0, 2.0) = 1.2;

void fragment() {
	// Sample background with blur
	vec2 uv = SCREEN_UV;
	vec4 blur_sum = vec4(0.0);
	float samples = 9.0;
	float blur_size = blur_amount * SCREEN_PIXEL_SIZE.x;
	
	for(float x = -1.0; x <= 1.0; x += 1.0) {
		for(float y = -1.0; y <= 1.0; y += 1.0) {
			blur_sum += texture(SCREEN_TEXTURE, uv + vec2(x, y) * blur_size);
		}
	}
	
	vec4 blurred = blur_sum / samples;
	
	// Add tint and transparency
	vec4 glass = mix(blurred, tint_color, tint_color.a);
	
	// Edge glow
	vec2 edge_dist = abs(UV - vec2(0.5)) * 2.0;
	float edge = max(edge_dist.x, edge_dist.y);
	float glow = smoothstep(0.85, 1.0, edge) * edge_brightness;
	glass.rgb += vec3(glow) * 0.1;
	
	COLOR = glass;
}
