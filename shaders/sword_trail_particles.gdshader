// Sword-trail particle process. The single particle is glued to the emitter (the blade) every
// frame. With local_coords off, GPUParticles3D records its world-space path, and the
// RibbonTrailMesh (width = blade length) is skinned along that path, which draws the swept arc.
shader_type particles;
render_mode disable_velocity, disable_force;

uniform vec4 trail_color : source_color = vec4(1.0, 0.8, 0.55, 1.0);
/** Fraction of the particle's life after which the ribbon fades out. */
uniform float fade_start : hint_range(0.0, 1.0) = 0.55;

void start() {
	TRANSFORM = EMISSION_TRANSFORM;
	CUSTOM = vec4(0.0);
	COLOR = trail_color;
}

void process() {
	TRANSFORM = EMISSION_TRANSFORM;
	CUSTOM.y += DELTA;
	float age = clamp(CUSTOM.y / LIFETIME, 0.0, 1.0);
	COLOR = vec4(trail_color.rgb, trail_color.a * (1.0 - smoothstep(fade_start, 1.0, age)));
}
