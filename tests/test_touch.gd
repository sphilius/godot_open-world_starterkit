extends "res://tests/test_case.gd"
## Touch controls. Headless has no touchscreen and doesn't dispatch input to the GUI, so these
## build the controls directly and feed events straight into each control's _gui_input().
## The native VirtualJoystick is Godot's own and is left to Godot's tests.


func test_action_buttons_press_and_release_their_actions() -> void:
	await load_world()
	var controls := _controls()
	var attack := controls.buttons["Attack"] as TouchActionButton
	_touch(attack, 3, true)
	await tree.process_frame
	check(attack.is_pressed and Input.is_action_pressed(&"attack"), "ATK didn't press the attack action")
	_touch(attack, 4, true)                              # a second finger can't steal a held button
	_touch(attack, 4, false)
	check(attack.is_pressed, "another finger released ATK")
	_touch(attack, 3, false)
	await tree.process_frame
	check(not attack.is_pressed and not Input.is_action_pressed(&"attack"), "ATK didn't release")

	for button_name: String in ["Heavy", "Dodge"]:
		var button := controls.buttons[button_name] as TouchActionButton
		_touch(button, 9, true)
		await tree.process_frame
		check(Input.is_action_pressed(button.action), "%s didn't press %s" % [button_name, button.action])
		_touch(button, 9, false)
		await tree.process_frame

	var run := controls.buttons["Run"] as TouchActionButton
	_touch(run, 5, true)
	_touch(run, 5, false)
	await tree.process_frame
	check(Input.is_action_pressed(&"sprint"), "RUN should latch sprint on")
	_touch(run, 5, true)
	_touch(run, 5, false)
	await tree.process_frame
	check(not Input.is_action_pressed(&"sprint"), "a second RUN tap should release sprint")


func test_look_pad_turns_the_camera() -> void:
	await load_world()
	var pad := _controls().look_pad
	var yaw_before := player()._target_yaw
	_touch(pad, 6, true)
	_drag(pad, 6, Vector2(100, 0))
	check(is_equal_approx(player()._target_yaw - yaw_before, -100.0 * pad.sensitivity), "dragging the look pad didn't turn the camera")
	var yaw_held := player()._target_yaw
	_drag(pad, 7, Vector2(100, 0))                       # a second finger is ignored
	check_eq(player()._target_yaw, yaw_held, "yaw after a second finger's drag")
	_touch(pad, 6, false)


func test_reset_button_returns_to_spawn() -> void:
	await load_world()
	var spawn := player()._spawn_position
	player().global_position += Vector3(8, 0, 0)
	var reset := _controls().buttons["Reset"] as TouchActionButton
	_touch(reset, 8, true)
	_touch(reset, 8, false)
	check(player().global_position.distance_to(spawn) < 0.3, "RESET didn't return the player to spawn")


func _controls() -> TouchControls:
	var controls := world.get_node("TouchControls") as TouchControls
	if controls.buttons.is_empty():
		controls._build()                                # no touchscreen headless: build the UI directly
	return controls


static func _touch(control: Control, index: int, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = control.size * 0.5
	control._gui_input(event)


static func _drag(control: Control, index: int, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.relative = relative
	event.position = control.size * 0.5 + relative
	control._gui_input(event)
