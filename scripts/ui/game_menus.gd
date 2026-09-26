class_name GameMenus
extends CanvasLayer
## Title, pause and victory screens, the checkpoint toast and the fade in from black (M9).
## Built in code like the HUD, and it keeps running while the tree is paused.
##
## Title   : shown while GameManager is in START_MENU (the world waits, paused, behind it).
## Pause   : the `pause` action (Esc, P, gamepad Start, the touch PAUSE button) toggles it
##           during play. Resume · Return to shrine · Quit to title.
## Victory : GameManager's `victory`: time, parries and deaths, then Return to title.
## Death   : `death_fade_delay` real seconds after the player dies the screen fades to black,
##           and it fades back in once they're back on their feet at the checkpoint.
## The first button of each screen takes focus, so ui_up/ui_down and ui_accept (Enter, gamepad
## A) work without a mouse.

@export var game: GameManager
## Real seconds after death before the fade to black (the slow motion plays first).
@export var death_fade_delay := 1.3
@export var fade_time := 0.4

const TEXT := Color(1.0, 0.88, 0.72)
const CONTROLS_HINT := "Move WASD · Light J / LMB · Heavy K / RMB · Dodge L / C · Guard F (tap to parry)\nLock on Q / MMB · Next target E · Sprint Shift · Pause Esc"

var _dim: ColorRect
var _fade: ColorRect
var _title: Control
var _pause: Control
var _victory: Control
var _stats: Label
var _toast: Label
var _toast_tween: Tween
var _fade_tween: Tween


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.01, 0.02, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_title = _screen(ProjectSettings.get_setting("application/config/name", "Vertical Slice"),
			"Walk the valley at golden hour. Survive the courtyard at dusk. Face the Gatekeeper at night.")
	_add_button(_title, "Begin", _on_begin)
	if not OS.has_feature("web"):
		_add_button(_title, "Quit", get_tree().quit)
	_add_label(_title, CONTROLS_HINT, 15, Color(TEXT, 0.75))

	_pause = _screen("Paused", "")
	_add_button(_pause, "Resume", set_paused.bind(false))
	_add_button(_pause, "Return to shrine", _on_return_to_checkpoint)
	_add_button(_pause, "Quit to title", game.return_to_title)

	_victory = _screen("Victory", "The Gatekeeper has fallen.")
	_stats = _add_label(_victory, "", 22, TEXT)
	_add_button(_victory, "Return to title", game.return_to_title)

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -300.0
	_toast.offset_right = 300.0
	_toast.offset_top = -150.0
	_toast.offset_bottom = -110.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_label(_toast, 26, TEXT)
	_toast.modulate.a = 0.0
	add_child(_toast)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	game.state_changed.connect(_on_state_changed)
	game.checkpoint_reached.connect(func(_shrine: CheckpointShrine) -> void: show_toast("Checkpoint saved"))
	game.victory.connect(_show_victory)
	var health := HealthComponent.resolve(game.player) if game.player else null
	if health:
		health.died.connect(_on_player_died)
		health.health_changed.connect(func(_current: float, _maximum: float) -> void:
			if not health.is_dead and _fade.color.a > 0.0 and game.is_playing():
				_fade_to(0.0, fade_time * 2.0))
	_show(_title if game.state == GameManager.GameState.START_MENU else null)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"pause") and game.is_playing():
		set_paused(not is_paused())


## Opens or closes the pause menu (pausing the tree).
func set_paused(on: bool) -> void:
	if on == is_paused() or not game.is_playing():
		return
	get_tree().paused = on
	_show(_pause if on else null)
	if not on and game.player:
		game.player.capture_mouse()


func is_paused() -> bool:
	return _pause.visible


## The screen on display: "title", "pause", "victory" or "" (none).
func current_screen() -> String:
	if _title.visible:
		return "title"
	if _pause.visible:
		return "pause"
	if _victory.visible:
		return "victory"
	return ""


## How black the screen is (0 clear, 1 black): the Begin fade and the death fade.
func fade_alpha() -> float:
	return _fade.color.a


## Shows `text` near the bottom of the screen for a few seconds.
func show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, ^"modulate:a", 1.0, 0.3)
	_toast_tween.tween_interval(2.2)
	_toast_tween.tween_property(_toast, ^"modulate:a", 0.0, 0.6)


## m:ss.
static func format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]


func _on_begin() -> void:
	_fade.color.a = 1.0
	_show(null)
	game.begin_play()
	_fade_to(0.0, 1.2)


func _on_player_died(_hit: HitInfo) -> void:
	await get_tree().create_timer(death_fade_delay, true, false, true).timeout
	var health := HealthComponent.resolve(game.player)
	if health and health.is_dead:
		_fade_to(1.0, fade_time)


func _fade_to(alpha: float, duration: float) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_ignore_time_scale()
	_fade_tween.tween_property(_fade, ^"color:a", alpha, duration)


func _on_return_to_checkpoint() -> void:
	set_paused(false)
	game.return_to_checkpoint()


func _on_state_changed(_previous: GameManager.GameState, current: GameManager.GameState) -> void:
	if current == GameManager.GameState.START_MENU:
		_show(_title)


func _show_victory() -> void:
	var stats := game.stats()
	_stats.text = "Time  %s\nParries  %d\nDeaths  %d" % [format_time(stats[&"time"]), stats[&"parries"], stats[&"deaths"]]
	_show(_victory)


func _show(screen: Control) -> void:
	for each in [_title, _pause, _victory]:
		(each as Control).visible = each == screen
	_dim.visible = screen != null
	if screen:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var first := _first_button(screen)
		if first:
			first.grab_focus.call_deferred()


# --- Building --------------------------------------------------------------------------------

func _screen(heading: String, subtitle: String) -> VBoxContainer:
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE          # touches reach TouchControls in play
	add_child(centre)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 14)
	centre.add_child(column)
	_add_label(column, heading, 56, TEXT)
	if subtitle != "":
		_add_label(column, subtitle, 20, Color(TEXT, 0.85))
	var gap := Control.new()                               # a little space before the buttons
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)
	column.visible = false
	return column


func _add_label(screen: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(label, font_size, color)
	screen.add_child(label)
	return label


func _add_button(screen: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 52)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override(&"font_size", 24)
	button.pressed.connect(action)
	screen.add_child(button)
	return button


func _first_button(screen: Control) -> Button:
	for child in screen.get_children():
		if child is Button:
			return child
	return null


func _style_label(label: Label, font_size: int, color: Color) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override(&"outline_size", 6)
