// Wind-swept meadow grass for MultiMesh blades (built by scripts/world/grass_field.gd).
//
// Blade mesh contract : UV.y = 0 at the root, 1 at the tip.
// INSTANCE_CUSTOM     : r = dryness (tip colour), g = flutter phase, b = clump, a = unused.
//
// world_vertex_coords → VERTEX / NORMAL arrive in world space, so wind and the player
// push are computed directly in metres.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_burley, specular_schlick_ggx;

// Written every frame by PlayerController (declared in project.godot → [shader_globals]).
global uniform vec3 player_position;

group_uniforms wind;
/** Seamless scrolling noise. FastNoiseLite TYPE_SIMPLEX_SMOOTH is OpenSimplex2S —
    Godot 4's replacement for the removed OpenSimplexNoise class. */
uniform sampler2D wind_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec2 wind_direction = vec2(1.0, 0.35);
/** Noise UV scroll per second — how fast gust fronts travel across the field. */
uniform float wind_speed = 0.05;
/** World metres → noise UV. Smaller = broader gusts. */
uniform float wind_scale = 0.018;
/** Tip lean at a full gust, as a fraction of blade length. */
uniform float wind_strength = 0.65;
/** Constant lean so the field always reads as "downwind". */
uniform float base_lean = 0.08;
uniform float flutter_strength = 0.05;
uniform float flutter_speed = 5.0;
group_uniforms;

group_uniforms player_interaction;
uniform float push_radius = 1.3;
uniform float push_strength = 1.1;
group_uniforms;

group_uniforms look;
uniform vec3 root_color : source_color = vec3(0.06, 0.10, 0.03);
uniform vec3 tip_color : source_color = vec3(0.45, 0.55, 0.17);
uniform vec3 dry_tip_color : source_color = vec3(0.78, 0.62, 0.28);
/** Silvery highlight where gusts flatten the grass — sells the ripple. */
uniform vec3 sheen_color : source_color = vec3(1.0, 0.88, 0.6);
uniform float sheen_strength = 0.3;
/** Light transmitted through blades when backlit by the low sun. */
uniform vec3 translucency : source_color = vec3(0.6, 0.5, 0.18);
group_uniforms;

group_uniforms distance_fade;
uniform float fade_start = 42.0;
uniform float fade_end = 60.0;
group_uniforms;

varying float v_height;
varying float v_gust;
varying float v_dryness;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;               // blade origin (MultiMesh instance xform is folded into MODEL_MATRIX)
	float blade_len = length(MODEL_MATRIX[1].xyz); // instance Y scale = blade height in metres
	float h = UV.y;
	float bend_weight = h * h;                     // roots pinned, tips swing the most
	v_height = h;
	v_dryness = INSTANCE_CUSTOM.r;

	// 1) Directional wind: sample at the ROOT so each blade bends as one piece, and scroll
	//    the noise along the wind so gust fronts visibly ripple across the meadow.
	vec2 dir = normalize(wind_direction);
	vec2 wind_uv = root.xz * wind_scale - dir * (TIME * wind_speed);
	float gust = smoothstep(0.25, 0.85, texture(wind_noise, wind_uv).r);
	v_gust = gust;
	float flutter = sin(TIME * flutter_speed + INSTANCE_CUSTOM.g * 6.2832) * flutter_strength;
	vec2 lean = dir * (base_lean + gust * wind_strength + flutter);

	// 2) Player proximity: push blades radially away from the player's feet
	//    (faded out when the player is well above the grass, e.g. mid-jump).
	vec3 to_blade = root - player_position;
	float dist = length(to_blade.xz);
	float push = 1.0 - smoothstep(push_radius * 0.3, push_radius, dist);
	push *= 1.0 - smoothstep(0.6, 1.6, abs(to_blade.y));
	lean += (to_blade.xz / max(dist, 0.001)) * push * push_strength;

	// Clamp the tip so blades never stretch, then drop it to preserve blade length.
	vec2 tip = lean * blade_len;
	float reach = length(tip);
	float max_reach = blade_len * 0.9;
	if (reach > max_reach) {
		tip *= max_reach / reach;
		reach = max_reach;
	}
	float tip_drop = blade_len - sqrt(blade_len * blade_len - reach * reach);
	vec3 offset = vec3(tip.x, 0.0, tip.y) * bend_weight;
	offset.y = -tip_drop * h;

	// 3) Distance fade: shrink far blades into the ground (cheaper than alpha blending;
	//    the terrain's meadow colour underneath hides the transition).
	float fade = 1.0 - smoothstep(fade_start, fade_end, distance(root, CAMERA_POSITION_WORLD));
	VERTEX = root + (VERTEX + offset - root) * fade;

	// Bias normals upward so the field shades like a soft canopy instead of flat cards.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.6));
}

void fragment() {
	vec3 tip = mix(tip_color, dry_tip_color, smoothstep(0.55, 1.0, v_dryness));
	vec3 col = mix(root_color, tip, smoothstep(0.0, 0.85, v_height));
	col += sheen_color * (v_gust * sheen_strength * v_height);
	ALBEDO = col;
	ROUGHNESS = 0.55;
	SPECULAR = 0.15;             // low: keeps blue sky reflections off the blades
	BACKLIGHT = translucency * v_height;
	AO = mix(0.35, 1.0, v_height);                  // cheap self-occlusion toward the root
	AO_LIGHT_AFFECT = 0.4;
}
