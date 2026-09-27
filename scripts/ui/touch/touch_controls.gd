class_name TouchControls
extends CanvasLayer
## On-screen playtest controls for phones and tablets (built for a Pixel Tablet in landscape).
## Shown automatically when a touchscreen is present; `--touch` (desktop) or `?touch` (web URL)
## forces them on, and on a desktop the mouse then acts as a single finger.
##
##   Left side  : floating thumbstick (built-in VirtualJoystick, move)       Anywhere else : drag to look
##   Bottom right: ATK (light: tap, keep tapping for the combo) · HVY (heavy) · DODGE · JUMP ·
##                 GUARD (hold; tap just before a hit to parry) · RUN (sprint toggle) ·
##                 LOCK (lock-on toggle) · NEXT (next target)
##   Top right  : FULL (fullscreen) · QUAL (cycle quality) · RESET (back to the last checkpoint) ·
##                PAUSE (the pause menu)

@export var player: PlayerController
@export var dev_hud: DevHUD

var joystick: VirtualJoystick
var look_pad: TouchLookPad
var buttons := {}   # name -> TouchActionButton


func _ready() -> void:
	layer = 5
	var enabled := is_touch_mode()
	visible = enabled
	if not enabled:
		return
	if not DisplayServer.is_touchscreen_available():
		Input.emulate_touch_from_mouse = true    # desktop testing: the mouse is one finger
	player.mouse_capture_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if dev_hud:
		dev_hud.touch_mode = true
	_build()


## True on touchscreens, or when forced with `--touch` / `?touch`.
static func is_touch_mode() -> bool:
	return DisplayServer.is_touchscreen_available() or DevHUD.launch_args().has("touch")


func _build() -> void:
	# Look pad first so everything added after it sits on top and wins the touch.
	look_pad = TouchLookPad.new()
	look_pad.name = "LookPad"
	look_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	look_pad.look_dragged.connect(player.add_look_input)
	add_child(look_pad)

	# Godot 4.7's built-in VirtualJoystick: dynamic mode centres the stick under the thumb
	# anywhere in its zone and drives the move_* actions with analog strength.
	joystick = VirtualJoystick.new()
	joystick.name = "Joystick"
	joystick.joystick_mode = VirtualJoystick.JOYSTICK_DYNAMIC
	joystick.deadzone_ratio = 0.15
	joystick.joystick_size = 220.0
	joystick.tip_size = 95.0
	joystick.initial_offset_ratio = Vector2(0.3, 0.7)
	joystick.action_left = &"move_left"
	joystick.action_right = &"move_right"
	joystick.action_up = &"move_forward"
	joystick.action_down = &"move_back"
	joystick.anchor_top = 0.3
	joystick.anchor_right = 0.42
	joystick.anchor_bottom = 1.0
	add_child(joystick)

	# Bottom-right cluster (offsets measured from the corner, in UI pixels).
	_add_button("Attack", &"attack", "ATK", Rect2(-260, -260, 200, 200), false, Color(1.0, 0.78, 0.6), 34)
	_add_button("Jump", &"jump", "JUMP", Rect2(-430, -190, 130, 130), false)
	_add_button("Run", &"sprint", "RUN", Rect2(-235, -410, 120, 120), true)
	_add_button("Heavy", &"attack_heavy", "HVY", Rect2(-400, -360, 120, 120), false, Color(1.0, 0.7, 0.55), 24)
	_add_button("Dodge", &"dodge", "DODGE", Rect2(-575, -170, 130, 130), false, Color(0.75, 0.9, 1.0), 22)
	_add_button("Guard", &"guard", "GUARD", Rect2(-560, -330, 120, 120), false, Color(0.8, 0.85, 1.0), 20)
	_add_button("Lock", &"lock_on", "LOCK", Rect2(-100, -400, 90, 90), false, Color(1.0, 0.85, 0.55), 18)
	_add_button("Next", &"target_next", "NEXT", Rect2(-100, -510, 90, 90), false, Color(1.0, 0.85, 0.55), 18)

	# Top-right utilities.
	_add_button("Fullscreen", &"", "FULL", Rect2(-110, 20, 88, 88), false, Color(1, 1, 1), 18, true) \
			.activated.connect(_toggle_fullscreen)
	_add_button("Quality", &"", "QUAL", Rect2(-210, 20, 88, 88), false, Color(1, 1, 1), 18, true) \
			.activated.connect(_cycle_quality)
	_add_button("Reset", &"", "RESET", Rect2(-310, 20, 88, 88), false, Color(1, 1, 1), 16, true) \
			.activated.connect(player.respawn)
	_add_button("Pause", &"pause", "PAUSE", Rect2(-410, 20, 88, 88), false, Color(1, 1, 1), 15, true)


func _add_button(node_name: String, action: StringName, text: String, rect: Rect2, toggle: bool,
		tint := Color(1.0, 0.92, 0.8), font_size := 26, top_anchor := false) -> TouchActionButton:
	var button := TouchActionButton.new()
	button.name = node_name
	button.action = action
	button.label = text
	button.toggle = toggle
	button.tint = tint
	button.font_size = font_size
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 0.0 if top_anchor else 1.0
	button.anchor_bottom = button.anchor_top
	button.offset_left = rect.position.x
	button.offset_top = rect.position.y
	button.offset_right = rect.end.x
	button.offset_bottom = rect.end.y
	add_child(button)
	buttons[node_name] = button
	return button


func _cycle_quality() -> void:
	if dev_hud:
		dev_hud.cycle_quality()


func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
