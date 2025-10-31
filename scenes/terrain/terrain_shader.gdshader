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
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;

// Blend settings (passed from vertex colors)
uniform bool use_vertex_blend = true;
uniform vec4 default_blend = vec4(1.0, 0.0, 0.0, 0.0);

// Triplanar mapping settings
uniform bool use_triplanar = false;
uniform float triplanar_sharpness : hint_range(1.0, 8.0) = 4.0;

// Stylized lighting controls
uniform int toon_steps : hint_range(1, 6) = 3;
uniform float toon_smoothness : hint_range(0.0, 1.0) = 0.25;
uniform float ambient_intensity : hint_range(0.0, 1.0) = 0.35;
uniform vec4 ambient_color : source_color = vec4(0.45, 0.55, 0.65, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.3;
uniform float rim_power : hint_range(0.5, 8.0) = 2.5;
uniform vec4 rim_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
        world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
        world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float safe_denominator(float value) {
        return max(value, 0.0001);
}

vec3 decode_normal(vec3 sample) {
        if (sample.r + sample.g + sample.b == 0.0) {
                sample = vec3(0.5, 0.5, 1.0);
        }
        vec3 decoded = sample * 2.0 - 1.0;
        return normalize(decoded);
}

vec4 triplanar_texture(sampler2D tex, vec3 pos, vec3 normal, float scale) {
        vec3 blend_weights = pow(abs(normal), vec3(triplanar_sharpness));
        blend_weights /= safe_denominator(blend_weights.x + blend_weights.y + blend_weights.z);

        vec4 x_sample = texture(tex, pos.yz * scale);
        vec4 y_sample = texture(tex, pos.xz * scale);
        vec4 z_sample = texture(tex, pos.xy * scale);

        return x_sample * blend_weights.x +
               y_sample * blend_weights.y +
               z_sample * blend_weights.z;
}

vec3 triplanar_normal_map(sampler2D tex, vec3 pos, vec3 normal, float scale) {
        vec3 blend_weights = pow(abs(normal), vec3(triplanar_sharpness));
        blend_weights /= safe_denominator(blend_weights.x + blend_weights.y + blend_weights.z);

        vec3 x_axis = decode_normal(texture(tex, pos.yz * scale).xyz);
        vec3 y_axis = decode_normal(texture(tex, pos.xz * scale).xyz);
        vec3 z_axis = decode_normal(texture(tex, pos.xy * scale).xyz);

        vec3 oriented_x = vec3(x_axis.z * sign(normal.x), x_axis.x, x_axis.y);
        vec3 oriented_y = vec3(y_axis.x, y_axis.z * sign(normal.y), y_axis.y);
        vec3 oriented_z = vec3(z_axis.x, z_axis.y, z_axis.z * sign(normal.z));

        vec3 blended = oriented_x * blend_weights.x +
                       oriented_y * blend_weights.y +
                       oriented_z * blend_weights.z;

        return normalize(blended);
}

vec3 tangent_to_world(vec3 detail_normal, vec3 normal, vec2 uv) {
        vec3 dp1 = dFdx(world_position);
        vec3 dp2 = dFdy(world_position);
        vec2 duv1 = dFdx(uv);
        vec2 duv2 = dFdy(uv);

        vec3 tangent = dp1 * duv2.y - dp2 * duv1.y;
        vec3 bitangent = dp2 * duv1.x - dp1 * duv2.x;

        tangent = normalize(tangent);
        bitangent = normalize(bitangent);
        normal = normalize(normal);

        mat3 tbn = mat3(tangent, bitangent, normal);
        return normalize(tbn * detail_normal);
}

void fragment() {
        float scale = 1.0 / safe_denominator(texture_scale);
        vec2 uv_scaled = UV * texture_scale;

        vec4 grass_color;
        vec4 dirt_color;
        vec4 rock_color;
        vec4 snow_color;

        vec3 grass_norm;
        vec3 dirt_norm;
        vec3 rock_norm;
        vec3 snow_norm;

        if (use_triplanar) {
                grass_color = triplanar_texture(grass_texture, world_position, world_normal, scale);
                dirt_color = triplanar_texture(dirt_texture, world_position, world_normal, scale);
                rock_color = triplanar_texture(rock_texture, world_position, world_normal, scale);
                snow_color = triplanar_texture(snow_texture, world_position, world_normal, scale);

                grass_norm = triplanar_normal_map(grass_normal, world_position, world_normal, scale);
                dirt_norm = triplanar_normal_map(dirt_normal, world_position, world_normal, scale);
                rock_norm = triplanar_normal_map(rock_normal, world_position, world_normal, scale);
                snow_norm = triplanar_normal_map(snow_normal, world_position, world_normal, scale);
        } else {
                grass_color = texture(grass_texture, uv_scaled);
                dirt_color = texture(dirt_texture, uv_scaled);
                rock_color = texture(rock_texture, uv_scaled);
                snow_color = texture(snow_texture, uv_scaled);

                grass_norm = decode_normal(texture(grass_normal, uv_scaled).rgb);
                dirt_norm = decode_normal(texture(dirt_normal, uv_scaled).rgb);
                rock_norm = decode_normal(texture(rock_normal, uv_scaled).rgb);
                snow_norm = decode_normal(texture(snow_normal, uv_scaled).rgb);
        }

        vec4 blend = use_vertex_blend ? COLOR : default_blend;
        blend = clamp(blend, 0.0, 1.0);
        float weight_sum = blend.r + blend.g + blend.b + blend.a;
        if (weight_sum <= 0.0) {
                blend = vec4(1.0, 0.0, 0.0, 0.0);
                weight_sum = 1.0;
        }
        blend /= weight_sum;

        vec4 final_color = grass_color * blend.r +
                           dirt_color * blend.g +
                           rock_color * blend.b +
                           snow_color * blend.a;

        vec3 combined_normal = grass_norm * blend.r +
                               dirt_norm * blend.g +
                               rock_norm * blend.b +
                               snow_norm * blend.a;

        vec3 base_normal = normalize(world_normal);
        vec3 detail_normal = normalize(combined_normal);

        if (!use_triplanar) {
                detail_normal = tangent_to_world(detail_normal, base_normal, uv_scaled);
        }

        vec3 final_normal = normalize(mix(base_normal, detail_normal, clamp(normal_strength, 0.0, 1.0)));

        ALBEDO = final_color.rgb;
        ROUGHNESS = clamp(roughness, 0.0, 1.0);
        METALLIC = 0.0;
        SPECULAR = 0.0;
        NORMAL = final_normal;
}

void light() {
        vec3 norm = normalize(NORMAL);
        vec3 light_dir = normalize(LIGHT);
        vec3 view_dir = normalize(VIEW);

        float ndotl = max(0.0, dot(norm, light_dir));
        float toon_term = ndotl;

        if (toon_steps > 1) {
                float steps = float(toon_steps - 1);
                float quantized = floor(ndotl * steps + 1e-4) / max(steps, 1.0);
                toon_term = mix(quantized, ndotl, toon_smoothness);
        }

        vec3 diffuse = ALBEDO * LIGHT_COLOR.rgb * toon_term;
        vec3 ambient = ambient_color.rgb * ambient_intensity * ALBEDO;
        float rim_factor = pow(max(0.0, 1.0 - dot(norm, view_dir)), rim_power) * rim_strength;
        vec3 rim = rim_color.rgb * rim_factor;

        DIFFUSE_LIGHT = (diffuse + ambient + rim) * ATTENUATION;
        SPECULAR_LIGHT = vec3(0.0);
}
