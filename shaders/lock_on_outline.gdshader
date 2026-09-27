// Lock-on highlight (TargetingSystem): drawn over the target's meshes as a material_overlay.
// A faint red rim (fresnel) that breathes; `boost` briefly brightens it on a hit or parry.
// Additive and unshaded, so it reads in dark scenes without hiding the silhouette.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 rim_color : source_color = vec4(1.0, 0.12, 0.06, 1.0);
// Rim width: higher = thinner edge.
uniform float rim_power = 2.2;
// Strength at the dimmest and brightest point of the pulse.
uniform vec2 intensity = vec2(0.35, 0.9);
// Pulses per second.
uniform float pulse_rate = 1.4;
// Extra strength added on a hit (tweened back to 0).
uniform float boost = 0.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float pulse = mix(intensity.x, intensity.y, 0.5 + 0.5 * sin(TIME * TAU * pulse_rate));
	ALBEDO = rim_color.rgb * rim * (pulse + boost) * rim_color.a;
}
