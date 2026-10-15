extends SceneTree

func _init() -> void:
	print("--- Running Player Cursor Rotation & Controls Test ---")

	# 1. Load Main scene
	var main_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_scene)

	# Wait a frame for _ready
	await process_frame

	var player: Player = main_scene.get_node_or_null("Player") as Player
	assert(player != null, "Player node must exist")

	# --------------------------------------------------------------------------
	# Test 1: Player Rotates Towards Cursor (aim_target) when Stationary
	# --------------------------------------------------------------------------
	print("Test 1 - Player rotates towards aim_target when stationary...")
	player.global_position = Vector3(12.0, 0.0, 12.0)
	# Initially face North (-Z)
	player.basis = Basis.looking_at(Vector3(0, 0, -1), Vector3.UP).orthonormalized()
	player.external_input = Vector2.ZERO
	player.velocity = Vector3.ZERO

	# Set aim_target to the East (+X relative to player)
	var cursor_east := player.global_position + Vector3(10.0, 0.0, 0.0)
	player.aim_target = cursor_east

	# Simulate physics process frames for turning
	for i in range(30):
		player._physics_process(0.016)

	var current_facing := -player.basis.z
	print("Facing after aiming East: ", current_facing)
	assert(current_facing.dot(Vector3(1, 0, 0)) > 0.95, "Player must face East towards aim_target")

	# --------------------------------------------------------------------------
	# Test 2: Player Maintains Aim Towards Cursor While Moving in Another Direction
	# --------------------------------------------------------------------------
	print("Test 2 - Player maintains aim towards cursor while moving with WASD (strafing/backing up)...")
	# Moving South (+Z) while cursor is East (+X)
	var start_pos := player.global_position
	player.external_input = Vector2(0, 1) # South
	for i in range(15):
		player._physics_process(0.016)

	current_facing = -player.basis.z
	var expected_dir := (cursor_east - player.global_position)
	expected_dir.y = 0.0
	print("Facing while moving South with aim East: ", current_facing, " expected: ", expected_dir.normalized())
	print("Player pos: ", player.global_position, " (was ", start_pos, ") velocity: ", player.velocity)
	assert(current_facing.dot(expected_dir.normalized()) > 0.95, "Player must track the aim_target position while moving South")
	assert(player.global_position.z > start_pos.z, "Player position must advance South (+Z)")
	assert(player.velocity.z > 0.0, "Player must have positive South velocity (+Z)")

	# Stop movement
	player.external_input = Vector2.ZERO
	player.velocity = Vector3.ZERO

	# --------------------------------------------------------------------------
	# Test 3: Attack With Left Click (MOUSE_BUTTON_LEFT) & Left Stick
	# --------------------------------------------------------------------------
	print("Test 3 - Attack with Left Click & Left Stick...")
	player.is_attacking = false
	player._can_attack = true

	var test3_data := {"left_click_fired": false, "joy_stick_fired": false}
	player.attack_started.connect(func():
		if not test3_data["left_click_fired"]:
			test3_data["left_click_fired"] = true
		else:
			test3_data["joy_stick_fired"] = true
	)

	var left_click := InputEventMouseButton.new()
	left_click.button_index = MOUSE_BUTTON_LEFT
	left_click.pressed = true
	left_click.position = Vector2(400, 300)

	main_scene._unhandled_input(left_click)
	assert(test3_data["left_click_fired"] == true, "Left Click in main_scene must trigger attack_started")
	assert(player.is_attacking == true, "Player must be in attacking state")

	# Reset attack state for joypad stick test
	player.is_attacking = false
	player._can_attack = true

	# Test Joypad left stick button attack
	var joy_left_stick := InputEventJoypadButton.new()
	joy_left_stick.button_index = JOY_BUTTON_LEFT_STICK
	joy_left_stick.pressed = true

	main_scene._unhandled_input(joy_left_stick)
	assert(test3_data["joy_stick_fired"] == true, "Joypad Left Stick button must trigger attack_started")

	# --------------------------------------------------------------------------
	# Test 4: Throw Grenade With Right Click (MOUSE_BUTTON_RIGHT)
	# --------------------------------------------------------------------------
	print("Test 4 - Throw grenade with Right Click...")
	player.is_attacking = false
	player._can_throw_grenade = true

	var test4_data := {"grenade_thrown": false}
	player.grenade_thrown.connect(func(_g):
		test4_data["grenade_thrown"] = true
	)

	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = Vector2(400, 300)

	main_scene._unhandled_input(right_click)
	assert(test4_data["grenade_thrown"] == true, "Right Click in main_scene must trigger grenade_thrown")

	# --------------------------------------------------------------------------
	# Test 5: Dash With Space (KEY_SPACE)
	# --------------------------------------------------------------------------
	print("Test 5 - Dash with Space...")
	player.is_dodging = false
	player._can_dodge = true

	var test5_data := {"dash_fired": false}
	player.dodge_started.connect(func(_dir):
		test5_data["dash_fired"] = true
	)

	var space_key := InputEventKey.new()
	space_key.keycode = KEY_SPACE
	space_key.pressed = true
	space_key.echo = false

	main_scene._unhandled_input(space_key)
	assert(test5_data["dash_fired"] == true, "Space key in main_scene must trigger dash (dodge_started)")
	assert(player.is_dodging == true, "Player must be in dodging state")

	# Finish dash
	player._finish_dodge()
	player.is_dodging = false
	player._can_dodge = true

	# --------------------------------------------------------------------------
	# Test 6: Grapple With E (KEY_E)
	# --------------------------------------------------------------------------
	print("Test 6 - Grapple with E key...")
	# Place player near permanent center patch so hook has valid target
	player.global_position = Vector3(6.0, 0.0, 6.0)
	player.is_hooking = false
	player._can_hook = true

	var test6_data := {"hook_fired": false}
	player.hook_started.connect(func(_pos, _node):
		test6_data["hook_fired"] = true
	)

	var e_key := InputEventKey.new()
	e_key.keycode = KEY_E
	e_key.pressed = true
	e_key.echo = false

	# Aim towards center patch (0, 0, 0)
	player.aim_target = Vector3(0, 0, 0)
	main_scene._unhandled_input(e_key)

	assert(test6_data["hook_fired"] == true, "E key in main_scene must trigger hook_started")
	assert(player.is_hooking == true, "Player must be in hooking state")

	print("--- ALL PLAYER CONTROLS & ROTATION TESTS PASSED SUCCESSFULLY! ---")
	quit(0)
