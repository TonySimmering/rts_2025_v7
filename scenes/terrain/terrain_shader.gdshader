shader_type spatial;

// Texture inputs
uniform sampler2D grass_texture : source_color;
uniform sampler2D dirt_texture : source_color;
uniform sampler2D rock_texture : source_color;
uniform sampler2D snow_texture : source_color;

// Normal maps (optional)
uniform sampler2D grass_normal : hint_normal;
uniform sampler2D dirt_normal : hint_normal;
uniform sampler2D rock_normal : hint_normal;
uniform sampler2D snow_normal : hint_normal;

// Material properties
uniform float texture_scale = 10.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

// Blend settings (passed from vertex colors)
uniform bool use_vertex_blend = true;

// Triplanar mapping settings
uniform bool use_triplanar = false;
uniform float triplanar_sharpness : hint_range(1.0, 8.0) = 4.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Triplanar mapping function
vec4 triplanar_mapping(sampler2D tex, vec3 pos, vec3 normal, float scale) {
	// Sample texture from 3 planes
	vec4 x_sample = texture(tex, pos.yz * scale);
	vec4 y_sample = texture(tex, pos.xz * scale);
	vec4 z_sample = texture(tex, pos.xy * scale);
	
	// Calculate blend weights based on normal
	vec3 blend_weights = abs(normal);
	blend_weights = pow(blend_weights, vec3(triplanar_sharpness));
	blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z);
	
	// Blend samples
	return x_sample * blend_weights.x + 
	       y_sample * blend_weights.y + 
	       z_sample * blend_weights.z;
}

void fragment() {
	vec4 grass_color;
	vec4 dirt_color;
	vec4 rock_color;
	vec4 snow_color;
	
	vec3 grass_norm;
	vec3 dirt_norm;
	vec3 rock_norm;
	vec3 snow_norm;
	
	if (use_triplanar) {
		// Triplanar mapping (better for steep slopes)
		grass_color = triplanar_mapping(grass_texture, world_position, world_normal, 1.0 / texture_scale);
		dirt_color = triplanar_mapping(dirt_texture, world_position, world_normal, 1.0 / texture_scale);
		rock_color = triplanar_mapping(rock_texture, world_position, world_normal, 1.0 / texture_scale);
		snow_color = triplanar_mapping(snow_texture, world_position, world_normal, 1.0 / texture_scale);
		
		grass_norm = triplanar_mapping(grass_normal, world_position, world_normal, 1.0 / texture_scale).rgb;
		dirt_norm = triplanar_mapping(dirt_normal, world_position, world_normal, 1.0 / texture_scale).rgb;
		rock_norm = triplanar_mapping(rock_normal, world_position, world_normal, 1.0 / texture_scale).rgb;
		snow_norm = triplanar_mapping(snow_normal, world_position, world_normal, 1.0 / texture_scale).rgb;
	} else {
		// Standard UV mapping
		vec2 uv_scaled = UV * texture_scale;
		
		grass_color = texture(grass_texture, uv_scaled);
		dirt_color = texture(dirt_texture, uv_scaled);
		rock_color = texture(rock_texture, uv_scaled);
		snow_color = texture(snow_texture, uv_scaled);
		
		grass_norm = texture(grass_normal, uv_scaled).rgb;
		dirt_norm = texture(dirt_normal, uv_scaled).rgb;
		rock_norm = texture(rock_normal, uv_scaled).rgb;
		snow_norm = texture(snow_normal, uv_scaled).rgb;
	}
	
	// Get blend weights from vertex colors
	vec4 blend = COLOR;
	
	// Blend textures based on vertex colors
	// R channel = grass weight
	// G channel = dirt weight
	// B channel = rock weight
	// A channel = snow weight
	
	vec4 final_color = grass_color * blend.r + 
	                   dirt_color * blend.g + 
	                   rock_color * blend.b + 
	                   snow_color * blend.a;
	
	// Blend normal maps
	vec3 final_normal = grass_norm * blend.r + 
	                    dirt_norm * blend.g + 
	                    rock_norm * blend.b + 
	                    snow_norm * blend.a;
	
	// Convert from [0,1] to [-1,1] range
	final_normal = final_normal * 2.0 - 1.0;
	final_normal = normalize(final_normal);
	
	// Apply to fragment
	ALBEDO = final_color.rgb;
	ROUGHNESS = 1.0 - roughness;
	METALLIC = 0.0;               // Force non-metallic
	SPECULAR = 0.0;  
	NORMAL_MAP = final_normal * normal_strength;
}
