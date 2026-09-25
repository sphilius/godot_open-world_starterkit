// Shared look for both sword-trail renderers (GPU particle ribbon and CPU mesh ribbon).
// Contract: UV.x runs across the ribbon (hilt → tip), UV.y along it (newest → oldest),
// and COLOR carries tint plus the lifetime fade in alpha. HDR energy feeds the glow pass.

uniform float energy = 2.5;
/** How quickly the ribbon thins toward its oldest end. */
uniform float tail_softness : hint_range(0.05, 1.0) = 0.6;

void fragment() {
	float tail = 1.0 - smoothstep(1.0 - tail_softness, 1.0, UV.y);
	float edges = smoothstep(0.0, 0.15, UV.x) * (1.0 - smoothstep(0.8, 1.0, UV.x));
	ALBEDO = COLOR.rgb * energy;
	ALPHA = COLOR.a * tail * edges;
}
