class_name TelegraphGlint
extends Node3D
## Attack telegraph: a star flare (a soft core plus two crossed streaks, additive and
## billboarded) with a short light pop. Gold for blockable strikes, red for unblockable ones.
## Built in code, so it needs no textures; EnemyCombatController parents it to the weapon's
## Socket_Telegraph_Glint marker and calls flash().

const GOLD := Color(1.0, 0.78, 0.3)
const RED := Color(1.0, 0.16, 0.08)

## Seconds the flare takes to bloom and fade.
@export var duration := 0.4
@export var size := 0.55
@export var light_energy := 3.0

var last_color := Color.TRANSPARENT
var flashes := 0
var _core: Sprite3D
var _streaks: Array[Sprite3D] = []
var _light: OmniLight3D
var _tween: Tween

static var _texture: GradientTexture2D


func _ready() -> void:
	if _texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		_texture = GradientTexture2D.new()
		_texture.gradient = gradient
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(0.5, 0.0)
		_texture.width = 64
		_texture.height = 64
	_core = _sprite(Vector2(1.0, 1.0))
	_streaks = [_sprite(Vector2(3.2, 0.12)), _sprite(Vector2(0.12, 3.2))]
	_light = OmniLight3D.new()
	_light.omni_range = 3.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)
	visible = false


## Blooms the flare: red if `unblockable`, gold otherwise.
func flash(unblockable: bool) -> void:
	last_color = RED if unblockable else GOLD
	flashes += 1
	for sprite: Sprite3D in [_core] + _streaks:
		sprite.modulate = last_color
	_light.light_color = last_color
	visible = true
	scale = Vector3.ONE * 0.2
	if _tween:
		_tween.kill()
	_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(self, ^"scale", Vector3.ONE * size, duration * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_light, ^"light_energy", light_energy, duration * 0.35)
	_tween.tween_property(self, ^"scale", Vector3.ONE * 0.05, duration * 0.65).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_light, ^"light_energy", 0.0, duration * 0.65)
	_tween.tween_callback(hide)


func _sprite(stretch: Vector2) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = _texture
	sprite.pixel_size = 1.0 / 64.0
	sprite.scale = Vector3(stretch.x, stretch.y, 1.0)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.no_depth_test = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.render_priority = 10
	var material := StandardMaterial3D.new()                # additive: glows over anything
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	material.albedo_texture = _texture
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sprite.material_override = material
	add_child(sprite)
	return sprite
