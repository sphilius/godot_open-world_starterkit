// Heightmap terrain: meadow soil, slope-driven rock, and a gravel path painted from the
// vertex-colour path mask (COLOR.r, written by scripts/world/heightmap_terrain.gd).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

group_uniforms ground;
uniform vec3 meadow_color : source_color = vec3(0.2, 0.22, 0.08);
uniform vec3 meadow_dry_color : source_color = vec3(0.4, 0.33, 0.15);
uniform vec3 rock_color : source_color = vec3(0.34, 0.31, 0.28);
/** World normal.y where rock is fully exposed (steep)… */
uniform float rock_slope_full = 0.6;
/** …and where it starts showing through the meadow. */
uniform float rock_slope_start = 0.8;
uniform sampler2D variation_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float variation_scale = 0.012;
group_uniforms;

group_uniforms gravel;
uniform vec3 gravel_light : source_color = vec3(0.6, 0.53, 0.44);
uniform vec3 gravel_dark : source_color = vec3(0.36, 0.31, 0.26);
/** Cellular noise: one random tone per pebble. */
uniform sampler2D pebble_tone : hint_default_white, filter_linear_mipmap, repeat_enable;
/** Same cellular pattern as a normal map, so pebbles catch the low sun. */
uniform sampler2D pebble_normal : hint_normal, filter_linear_mipmap, repeat_enable;
/** Pebble texture repeats per metre. */
uniform float pebble_scale = 0.9;
uniform float edge_raggedness = 0.45;
group_uniforms;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	// The generated mesh has no tangents; UVs run along +X/+Z, so derive them from the normal.
	TANGENT = normalize(cross(NORMAL, vec3(0.0, 0.0, 1.0)));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	float variation = texture(variation_noise, xz * variation_scale).r;
	vec3 meadow = mix(meadow_color, meadow_dry_color, smoothstep(0.3, 0.8, variation));
	float rock = 1.0 - smoothstep(rock_slope_full, rock_slope_start, v_world_normal.y);
	vec3 ground = mix(meadow, rock_color * (0.75 + 0.5 * variation), rock);

	// Break up the path edge so the gravel doesn't read as a vector stripe.
	float edge_noise = texture(variation_noise, xz * 0.4).r - 0.5;
	float gravel_mask = smoothstep(0.4, 0.6, COLOR.r + edge_noise * edge_raggedness);
	vec2 pebble_uv = xz * pebble_scale;
	vec3 gravel = mix(gravel_dark, gravel_light, texture(pebble_tone, pebble_uv).r);

	ALBEDO = mix(ground, gravel, gravel_mask);
	ROUGHNESS = mix(0.95, 0.85, gravel_mask);
	SPECULAR = 0.3;                  // dull: stop flat gravel mirroring the blue zenith
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(pebble_normal, pebble_uv).rgb, gravel_mask);
	NORMAL_MAP_DEPTH = 0.8;
}
