class_name BeatLighting
extends Resource
## One lighting preset for a beat of the slice (decision D9): golden hour on the approach,
## dusk in the courtyard, night in the sanctum. GameManager blends between presets with
## apply_blend(); only colours and energies change, so the DevHUD quality knobs (SDFGI,
## volumetric fog resolution, shadows) are left alone.

@export var sun_color := Color(1, 0.72, 0.46)
@export var sun_energy := 2.4
## Euler rotation of the sun (radians). The physical sky follows the sun's direction.
@export var sun_rotation := Vector3(-0.14, 3.49, 0)
@export var ambient_color := Color(0.95, 0.72, 0.5)
@export var fog_color := Color(0.93, 0.66, 0.44)
@export var fog_density := 0.0012
@export var volumetric_fog_albedo := Color(1, 0.86, 0.72)
@export var volumetric_fog_density := 0.004
@export var exposure := 0.95
## PhysicalSkyMaterial (Forward+) or ProceduralSkyMaterial (web) energy multiplier.
@export var sky_energy := 1.4
@export var sky_mie_color := Color(0.98, 0.72, 0.48)
@export var sky_rayleigh_color := Color(0.26, 0.41, 0.58)


## Reads the current look of `environment` and `sun` into a new preset (the blend's start).
static func capture(environment: Environment, sun: DirectionalLight3D) -> BeatLighting:
	var preset := BeatLighting.new()
	if sun:
		preset.sun_color = sun.light_color
		preset.sun_energy = sun.light_energy
		preset.sun_rotation = sun.rotation
	if environment:
		preset.ambient_color = environment.ambient_light_color
		preset.fog_color = environment.fog_light_color
		preset.fog_density = environment.fog_density
		preset.volumetric_fog_albedo = environment.volumetric_fog_albedo
		preset.volumetric_fog_density = environment.volumetric_fog_density
		preset.exposure = environment.tonemap_exposure
		var sky_material := environment.sky.sky_material if environment.sky else null
		if sky_material is PhysicalSkyMaterial:
			var physical := sky_material as PhysicalSkyMaterial
			preset.sky_energy = physical.energy_multiplier
			preset.sky_mie_color = physical.mie_color
			preset.sky_rayleigh_color = physical.rayleigh_color
		elif sky_material is ProceduralSkyMaterial:
			preset.sky_energy = (sky_material as ProceduralSkyMaterial).sky_energy_multiplier
	return preset


## Applies the mix of `from` and `to` at `weight` (0 = from, 1 = to).
static func apply_blend(from: BeatLighting, to: BeatLighting, weight: float, environment: Environment, sun: DirectionalLight3D) -> void:
	var t := clampf(weight, 0.0, 1.0)
	if sun:
		sun.light_color = from.sun_color.lerp(to.sun_color, t)
		sun.light_energy = lerpf(from.sun_energy, to.sun_energy, t)
		sun.rotation = Vector3(
			lerp_angle(from.sun_rotation.x, to.sun_rotation.x, t),
			lerp_angle(from.sun_rotation.y, to.sun_rotation.y, t),
			lerp_angle(from.sun_rotation.z, to.sun_rotation.z, t))
	if environment == null:
		return
	environment.ambient_light_color = from.ambient_color.lerp(to.ambient_color, t)
	environment.fog_light_color = from.fog_color.lerp(to.fog_color, t)
	environment.fog_density = lerpf(from.fog_density, to.fog_density, t)
	environment.volumetric_fog_albedo = from.volumetric_fog_albedo.lerp(to.volumetric_fog_albedo, t)
	environment.volumetric_fog_density = lerpf(from.volumetric_fog_density, to.volumetric_fog_density, t)
	environment.tonemap_exposure = lerpf(from.exposure, to.exposure, t)
	var sky_material := environment.sky.sky_material if environment.sky else null
	if sky_material is PhysicalSkyMaterial:
		var physical := sky_material as PhysicalSkyMaterial
		physical.energy_multiplier = lerpf(from.sky_energy, to.sky_energy, t)
		physical.mie_color = from.sky_mie_color.lerp(to.sky_mie_color, t)
		physical.rayleigh_color = from.sky_rayleigh_color.lerp(to.sky_rayleigh_color, t)
	elif sky_material is ProceduralSkyMaterial:
		(sky_material as ProceduralSkyMaterial).sky_energy_multiplier = lerpf(from.sky_energy, to.sky_energy, t)
