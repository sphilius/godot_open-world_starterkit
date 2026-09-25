// Sword-trail ribbon for GPUParticles3D. `particle_trails` lets the RibbonTrailMesh be skinned
// along the particle's recorded world-space path. The look lives in the shared include.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, particle_trails;

#include "res://shaders/sword_trail_common.gdshaderinc"
