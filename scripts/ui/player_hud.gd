class_name PlayerHUD
extends CanvasLayer
## Gameplay HUD: a health bar that drains smoothly (with a lighter "recent damage" segment),
## a red flash when the player is hit, and a "Defeated" banner until respawn.
## Built in code, and every control ignores input, so touches pass through to TouchControls.

@export var health: HealthComponent
@export var bar_position := Vector2(16, 44)
@export var bar_size := Vector2(300, 14)
## How fast the "recent damage" segment catches up (fraction of the bar per second).
@export var drain_speed := 0.8

var _bar: Control
var _flash: ColorRect
var _banner: Label
var _ratio := 1.0          # current health
var _trail_ratio := 1.0    # lags behind to show the chunk just lost


func _ready() -> void:
	_flash = ColorRect.new()
	_flash.color = Color(0.75, 0.05, 0.02, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)

	_bar = Control.new()
	_bar.position = bar_position
	_bar.size = bar_size
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)

	_banner = Label.new()
	_banner.text = "Defeated — returning to the path…"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_font_size_override(&"font_size", 42)
	_banner.add_theme_color_override(&"font_color", Color(1.0, 0.86, 0.7))
	_banner.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_banner.add_theme_constant_override(&"outline_size", 8)
	_banner.visible = false
	add_child(_banner)

	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(func(_hit: HitInfo) -> void: _flash.color.a = 0.35)
	health.died.connect(func(_hit: HitInfo) -> void: _banner.visible = true)


func _process(delta: float) -> void:
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 1.2)
	if not is_equal_approx(_trail_ratio, _ratio):
		_trail_ratio = move_toward(_trail_ratio, _ratio, delta * drain_speed)
		_bar.queue_redraw()


func _on_health_changed(current: float, maximum: float) -> void:
	_ratio = current / maximum if maximum > 0.0 else 0.0
	if _ratio > _trail_ratio:
		_trail_ratio = _ratio              # healing or respawn: no drain animation
	if not health.is_dead:
		_banner.visible = false
	_bar.queue_redraw()


func _draw_bar() -> void:
	var rect := Rect2(Vector2.ZERO, bar_size)
	_bar.draw_rect(rect.grow(2.0), Color(0, 0, 0, 0.55))
	_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar_size.x * _trail_ratio, bar_size.y)), Color(1.0, 0.9, 0.75, 0.8))
	var fill := Color(0.78, 0.12, 0.08).lerp(Color(0.95, 0.72, 0.3), _ratio)
	_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar_size.x * _ratio, bar_size.y)), fill)
