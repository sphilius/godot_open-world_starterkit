extends CanvasLayer
## Dev overlay and graphics quality presets.
##
##   F2  : cycle quality LOW → MEDIUM → HIGH (integrated GPUs start on MEDIUM)
##   F12 : save a screenshot to user://screenshots/
##   Esc : release the mouse (click to recapture)
##
## Command line (after `--`):
##   --quality=low|medium|high
##   --capture=<png path> [--capture-delay=<seconds>]   renders, saves one frame, quits
##   e.g.  godot --path . -- --capture=C:/tmp/shot.png

enum Quality { LOW, MEDIUM, HIGH }
const QUALITY_NAMES: Array[String] = ["LOW", "MEDIUM", "HIGH"]

## Per-tier knobs, measured on an Intel UHD G1 (i5-1035G1) iGPU.
## LOW    : SDFGI and volumetric fog off, for frame rate.
## MEDIUM : SDFGI and volumetric fog stay on but lean (half-res GI, 3 cascades, small
##          froxel grid). Soft PCF replaces PCSS contact-hardening shadows.
## HIGH   : the full look (PCSS, 4 shadow splits, dense grass). Aimed at discrete GPUs.
const PRESETS := {
	Quality.LOW: {
		sdfgi = false, sdfgi_cascades = 3, sdfgi_rays = RenderingServer.ENV_SDFGI_RAY_COUNT_8,
		sdfgi_converge = RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES, gi_half_res = true,
		volumetric_fog = false, froxels = Vector2i(48, 32), ssao = false,
		shadow_atlas = 2048, shadow_splits = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		shadow_distance = 60.0, shadow_filter = RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, pcss = false,
		grass_density = 0.35, grass_distance = 30.0, render_scale = 0.6,
	},
	Quality.MEDIUM: {
		sdfgi = true, sdfgi_cascades = 3, sdfgi_rays = RenderingServer.ENV_SDFGI_RAY_COUNT_8,
		sdfgi_converge = RenderingServer.ENV_SDFGI_CONVERGE_IN_30_FRAMES, gi_half_res = true,
		volumetric_fog = true, froxels = Vector2i(48, 32), ssao = false,
		shadow_atlas = 2048, shadow_splits = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		shadow_distance = 90.0, shadow_filter = RenderingServer.SHADOW_QUALITY_SOFT_LOW, pcss = false,
		grass_density = 0.5, grass_distance = 40.0, render_scale = 0.67,
	},
	Quality.HIGH: {
		sdfgi = true, sdfgi_cascades = 4, sdfgi_rays = RenderingServer.ENV_SDFGI_RAY_COUNT_32,
		sdfgi_converge = RenderingServer.ENV_SDFGI_CONVERGE_IN_20_FRAMES, gi_half_res = false,
		volumetric_fog = true, froxels = Vector2i(128, 96), ssao = true,
		shadow_atlas = 4096, shadow_splits = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		shadow_distance = 140.0, shadow_filter = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, pcss = true,
		grass_density = 1.0, grass_distance = 60.0, render_scale = 1.0,
	},
}

@export var world_environment: WorldEnvironment
@export var grass: GrassField
@export var sun: DirectionalLight3D

@onready var _label: Label = $Label

var _quality := Quality.HIGH
var _sun_angular_distance := 0.0   # scene-authored PCSS softness, restored on HIGH


func _ready() -> void:
	_sun_angular_distance = sun.light_angular_distance
	var args := _parse_user_args()
	if args.has("quality") and QUALITY_NAMES.has(String(args["quality"]).to_upper()):
		_quality = QUALITY_NAMES.find(String(args["quality"]).to_upper()) as Quality
	elif GpuInfo.is_integrated():
		_quality = Quality.MEDIUM
	_apply_quality()
	if args.has("capture"):
		_capture_and_quit(String(args["capture"]), float(args.get("capture-delay", "6")))


func _process(_delta: float) -> void:
	_label.text = "%d FPS  ·  %s quality [F2]  ·  LMB/J attack (3-hit combo)  ·  F12 screenshot  ·  Esc frees mouse" % [
		Engine.get_frames_per_second(), QUALITY_NAMES[_quality]]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F2:
			_quality = ((_quality + 1) % Quality.size()) as Quality
			_apply_quality()
		KEY_F12:
			var stamp := Time.get_datetime_string_from_system().replace(":", "-")
			_save_screenshot("user://screenshots/shot_%s.png" % stamp)


func _apply_quality() -> void:
	var p: Dictionary = PRESETS[_quality]
	var env := world_environment.environment

	# Global illumination
	env.sdfgi_enabled = p.sdfgi
	env.sdfgi_cascades = p.sdfgi_cascades
	RenderingServer.environment_set_sdfgi_ray_count(p.sdfgi_rays)
	RenderingServer.environment_set_sdfgi_frames_to_converge(p.sdfgi_converge)
	RenderingServer.gi_set_use_half_resolution(p.gi_half_res)
	env.ssao_enabled = p.ssao

	# Atmosphere
	env.volumetric_fog_enabled = p.volumetric_fog
	RenderingServer.environment_set_volumetric_fog_volume_size(p.froxels.x, p.froxels.y)

	# Sun shadows: PCSS (angular distance) gives contact-hardening softness but is the priciest filter.
	RenderingServer.directional_shadow_atlas_set_size(p.shadow_atlas, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(p.shadow_filter)
	sun.directional_shadow_mode = p.shadow_splits
	sun.directional_shadow_max_distance = p.shadow_distance
	sun.light_angular_distance = _sun_angular_distance if p.pcss else 0.0

	# Grass + render resolution (FSR 1 upscales when below native).
	if grass:
		grass.set_density_scale(p.grass_density)
		grass.set_draw_distance(p.grass_distance)
	var viewport := get_viewport()
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if p.render_scale >= 1.0 else Viewport.SCALING_3D_MODE_FSR
	viewport.scaling_3d_scale = p.render_scale
	viewport.fsr_sharpness = 1.0   # 0 = sharpest; softer avoids halos around thin grass blades


func _capture_and_quit(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	_save_screenshot(path)
	get_tree().quit()


func _save_screenshot(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var err := get_viewport().get_texture().get_image().save_png(absolute)
	print("Screenshot %s: %s" % ["saved" if err == OK else "FAILED (%s)" % error_string(err), absolute])


static func _parse_user_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			out[parts[0]] = parts[1] if parts.size() > 1 else ""
	return out
