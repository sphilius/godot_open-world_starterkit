class_name PlayerHUD
extends CanvasLayer
## Gameplay HUD: a health bar that drains smoothly (with a lighter "recent damage" segment),
## a posture bar under it that fills from the centre outward (red when broken), a red flash
## when the player is hit, and a "Defeated" banner until respawn.
## Boss bar: an enemy calls set_boss() (group "boss_hud") when engaged; its name, health and
## posture show at the top centre until it's defeated. Execution prompt: shown while a light
## attack would execute a posture-broken enemy (CombatStateMachine.execution_target()).
## Lock-on gauge (M9b): a small health bar and posture line float over the locked target
## (TargetingSystem), unless it's the boss on the boss bar or it's behind the camera.
## Built in code, and every control ignores input, so touches pass through to TouchControls.

@export var health: HealthComponent
## Optional: shows the posture bar.
@export var posture: PostureComponent
## Optional: shows the execution prompt.
@export var combat: CombatStateMachine
## Optional: shows the lock-on gauge.
@export var targeting: TargetingSystem
## Height above the target's origin where the gauge floats (m).
@export var gauge_height := 2.4
@export var gauge_size := Vector2(84, 6)
@export var boss_bar_size := Vector2(520, 12)
@export var bar_position := Vector2(16, 44)
@export var bar_size := Vector2(300, 14)
## How fast the "recent damage" segment catches up (fraction of the bar per second).
@export var drain_speed := 0.8

var _bar: Control
var _posture_bar: Control
var _boss: Node3D
var _boss_panel: Control
var _boss_label: Label
var _prompt: Label
var _gauge: Control
var _gauge_target: Node3D
var _gauge_point := Vector2.ZERO
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

	if posture:
		_posture_bar = Control.new()
		_posture_bar.position = bar_position + Vector2(0, bar_size.y + 10)
		_posture_bar.size = Vector2(bar_size.x, 6)
		_posture_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_posture_bar.draw.connect(_draw_posture)
		add_child(_posture_bar)
		posture.posture_changed.connect(func(_current: float, _maximum: float) -> void: _posture_bar.queue_redraw())
		posture.posture_recovered.connect(_posture_bar.queue_redraw)

	add_to_group(&"boss_hud")
	_boss_panel = Control.new()
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_panel.position = Vector2(-boss_bar_size.x * 0.5, 24)
	_boss_panel.size = Vector2(boss_bar_size.x, 60)
	_boss_panel.draw.connect(_draw_boss)
	_boss_panel.visible = false
	add_child(_boss_panel)
	_boss_label = _hud_label(20)
	_boss_label.position = Vector2(0, -2)
	_boss_label.size = Vector2(boss_bar_size.x, 24)
	_boss_panel.add_child(_boss_label)
	_gauge = Control.new()
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gauge.draw.connect(_draw_gauge)
	add_child(_gauge)
	_prompt = _hud_label(24)
	_prompt.text = "ATTACK — Execute"
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-160, 90)
	_prompt.size = Vector2(320, 30)
	_prompt.visible = false
	add_child(_prompt)

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


## Shows `boss`'s bars at the top of the screen (null hides them).
func set_boss(boss: Node3D) -> void:
	if _boss and _boss.has_signal(&"defeated") and _boss.is_connected(&"defeated", _on_boss_defeated):
		_boss.disconnect(&"defeated", _on_boss_defeated)
	_boss = boss
	_boss_panel.visible = boss != null
	if boss:
		_boss_label.text = String(boss.get(&"boss_name")) if boss.get(&"boss_name") else String(boss.name)
		if boss.has_signal(&"defeated"):
			boss.connect(&"defeated", _on_boss_defeated)


func showing_boss() -> Node3D:
	return _boss if is_instance_valid(_boss) else null


func _on_boss_defeated() -> void:
	set_boss(null)


func _process(delta: float) -> void:
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 1.2)
	if _boss_panel.visible:
		if not is_instance_valid(_boss):
			set_boss(null)
		else:
			_boss_panel.queue_redraw()
	_prompt.visible = combat != null and combat.execution_target() != null
	_update_gauge()
	if not is_equal_approx(_trail_ratio, _ratio):
		_trail_ratio = move_toward(_trail_ratio, _ratio, delta * drain_speed)
		_bar.queue_redraw()


## The target the lock-on gauge is showing, or null.
func gauge_target() -> Node3D:
	return _gauge_target if is_instance_valid(_gauge_target) else null


func _update_gauge() -> void:
	var target: Node3D = targeting.current_target if targeting and targeting.is_locked() else null
	var camera := get_viewport().get_camera_3d() if target else null
	if target and (target == showing_boss() or camera == null):
		target = null
	if target:
		var head := target.global_position + Vector3.UP * gauge_height
		if camera.is_position_behind(head):
			target = null
		else:
			_gauge_point = camera.unproject_position(head)
	if target != _gauge_target or target:
		_gauge_target = target
		_gauge.queue_redraw()


func _draw_gauge() -> void:
	var target := gauge_target()
	if target == null:
		return
	var target_health := HealthComponent.resolve(target)
	var target_posture := PostureComponent.find_on(target)
	var bar := Rect2(_gauge_point - Vector2(gauge_size.x * 0.5, 0.0), gauge_size)
	_gauge.draw_rect(bar.grow(1.5), Color(0, 0, 0, 0.6))
	if target_health and target_health.max_health > 0.0:
		var ratio := clampf(target_health.current_health / target_health.max_health, 0.0, 1.0)
		_gauge.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color(0.78, 0.14, 0.08))
	if target_posture and target_posture.max_posture > 0.0:
		var ratio := clampf(target_posture.current / target_posture.max_posture, 0.0, 1.0)
		var width := gauge_size.x * ratio
		var line := Rect2(Vector2(_gauge_point.x - width * 0.5, bar.end.y + 3.0), Vector2(width, 3.0))
		_gauge.draw_rect(line, Color(0.9, 0.2, 0.1) if target_posture.is_broken else Color(0.95, 0.7, 0.3))


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


func _draw_posture() -> void:
	var size := _posture_bar.size
	var ratio := clampf(posture.current / posture.max_posture, 0.0, 1.0) if posture.max_posture > 0.0 else 0.0
	_posture_bar.draw_rect(Rect2(Vector2.ZERO, size).grow(2.0), Color(0, 0, 0, 0.45))
	if ratio <= 0.0:
		return
	var width := size.x * ratio
	var fill := Color(0.9, 0.2, 0.1) if posture.is_broken else Color(0.95, 0.75, 0.3).lerp(Color(1.0, 0.45, 0.15), ratio)
	_posture_bar.draw_rect(Rect2(Vector2((size.x - width) * 0.5, 0.0), Vector2(width, size.y)), fill)


func _draw_boss() -> void:
	if not is_instance_valid(_boss):
		return
	var boss_health: HealthComponent = _boss.get(&"health")
	var boss_posture: PostureComponent = _boss.get(&"posture")
	var bar := Rect2(Vector2(0, 26), boss_bar_size)
	_boss_panel.draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.55))
	if boss_health and boss_health.max_health > 0.0:
		var ratio := clampf(boss_health.current_health / boss_health.max_health, 0.0, 1.0)
		_boss_panel.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color(0.72, 0.1, 0.07))
	if boss_posture and boss_posture.max_posture > 0.0:
		var ratio := clampf(boss_posture.current / boss_posture.max_posture, 0.0, 1.0)
		var width := boss_bar_size.x * ratio
		var line := Rect2(Vector2((boss_bar_size.x - width) * 0.5, bar.end.y + 6), Vector2(width, 5))
		_boss_panel.draw_rect(line, Color(0.9, 0.2, 0.1) if boss_posture.is_broken else Color(0.95, 0.7, 0.3))


func _hud_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.88, 0.72))
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override(&"outline_size", 6)
	return label
