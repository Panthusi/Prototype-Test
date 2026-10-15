extends SceneTree

func _init() -> void:
	print("--- Running Dodge Ability, Anti-Slip & Distance Scaling Tests ---")

	# 1. Load Main scene
	var main_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_scene)

	# Wait a frame for _ready
	await process_frame

	var ground: Ground = main_scene.get_node("Ground")
	var player: Player = main_scene.get_node("Player")

	assert(ground != null, "Ground node must exist")
	assert(player != null, "Player node must exist")

	# --------------------------------------------------------------------------
	# Test 1: Initial state
	# --------------------------------------------------------------------------
	print("Test 1 - Initial dodge state...")
	assert(player.can_dodge() == true, "Player must initially be able to dodge")
	assert(player.is_dodging == false, "Player must not be dodging initially")

	# --------------------------------------------------------------------------
	# Test 2: Stationary dodge faces and moves in facing direction
	# --------------------------------------------------------------------------
	print("Test 2 - Stationary dodge in facing direction (North / -Z)...")
	# Place outside center patch so player is on normal ground
	player.global_position = Vector3(15.0, 0.0, 15.0)
	player._physics_process(0.016)
	assert(player.is_boosted() == false, "Player at (15,0,15) should be on normal ground")

	# Face North (-Z)
	player.basis = Basis.looking_at(Vector3(0, 0, -1), Vector3.UP).orthonormalized()
	player.external_input = Vector2.ZERO
	player.velocity = Vector3.ZERO

	var start_pos := player.global_position
	var normal_dodge_distance := player.get_dodge_distance()
	print("Normal dodge distance target: ", normal_dodge_distance, " meters")
	assert(is_equal_approx(normal_dodge_distance, player.base_dodge_distance), "Normal dodge distance should match base_dodge_distance")

	var test2_data := {"started": false, "dir": Vector3.ZERO}
	player.dodge_started.connect(func(dir: Vector3):
		test2_data["started"] = true
		test2_data["dir"] = dir
	)

	var success := player.dodge()
	assert(success == true, "dodge() should succeed")
	assert(player.is_dodging == true, "Player should be dodging")
	assert(player.can_dodge() == false, "can_dodge() should be false while dodging")
	assert(test2_data["started"] == true, "dodge_started signal must be emitted")
	print("Dodge direction: ", test2_data["dir"])
	assert(test2_data["dir"].is_equal_approx(Vector3(0, 0, -1)), "Stationary dodge must be forward in facing direction (-Z)")

	# Check that attack and grenade are blocked during dodge
	assert(player.can_attack() == false, "Attack should be blocked during dodge")
	assert(player.can_throw_grenade() == false, "Grenade should be blocked during dodge")

	# --------------------------------------------------------------------------
	# Test 3: Exact distance traveled & NO SLIPPING after dodge completes
	# --------------------------------------------------------------------------
	print("Test 3 - Exact distance traveled & NO SLIPPING at end of dodge...")
	var test3_finished := {"done": false}
	player.dodge_finished.connect(func():
		test3_finished["done"] = true
	)

	# Wait through the dodge duration using natural physics steps
	while player.is_dodging:
		await physics_frame

	assert(player.is_dodging == false, "Player must no longer be dodging")
	assert(test3_finished["done"] == true, "dodge_finished signal must be emitted")

	var total_distance_moved := (player.global_position - start_pos).length()
	print("Target dodge distance: ", normal_dodge_distance, " | Actual moved: ", total_distance_moved)
	assert(abs(total_distance_moved - normal_dodge_distance) < 0.1, "Total distance moved must match target dodge distance")

	# Check NO SLIPPING: velocity must be ZERO after dodge when no input is active
	print("Player velocity after dodge: ", player.velocity)
	assert(is_zero_approx(player.velocity.x) and is_zero_approx(player.velocity.z), "Horizontal velocity must be zero at end of dodge (NO SLIP!)")

	# Subsequent physics frames without input: position must NOT drift or slip
	var end_pos := player.global_position
	for i in range(10):
		await physics_frame
	print("Position after 10 idle frames: ", player.global_position, " (Was: ", end_pos, ")")
	assert(player.global_position.is_equal_approx(end_pos), "Player must remain stationary with zero sliding/slipping drift")

	# --------------------------------------------------------------------------
	# Test 4: Cooldown prevents instant re-dodge
	# --------------------------------------------------------------------------
	print("Test 4 - Cooldown prevents instant re-dodge...")
	assert(player._can_dodge == false, "_can_dodge must still be false during cooldown")
	var immediate_dodge := player.dodge()
	assert(immediate_dodge == false, "dodge() must return false while on cooldown")

	# Wait until cooldown finishes
	await create_timer(player.dodge_cooldown + 0.05).timeout
	assert(player.can_dodge() == true, "Player must be able to dodge again after cooldown expires")

	# --------------------------------------------------------------------------
	# Test 5: Dodge direction follows active movement input (e.g. West / -X)
	# --------------------------------------------------------------------------
	print("Test 5 - Dodge direction follows movement input (West / -X)...")
	# Keep facing North, but input moving West (-X)
	player.basis = Basis.looking_at(Vector3(0, 0, -1), Vector3.UP).orthonormalized()
	player.set_move_input(Vector2(-1.0, 0.0)) # Input moving left / -X

	var test5_data := {"dir": Vector3.ZERO}
	player.dodge_started.connect(func(dir: Vector3):
		test5_data["dir"] = dir
	)

	var move_dodge_success := player.dodge()
	assert(move_dodge_success == true, "dodge() with movement input should succeed")
	assert(test5_data["dir"].is_equal_approx(Vector3(-1.0, 0.0, 0.0)), "Dodge direction must follow movement input vector (-X)")
	assert(player.velocity.x < -10.0, "Player velocity.x must reflect high dodge speed")

	# Reset dodge state for next test
	player.is_dodging = false
	player._can_dodge = true
	player.external_input = Vector2.ZERO
	player.velocity = Vector3.ZERO

	# --------------------------------------------------------------------------
	# Test 6: Explicit direction parameter override
	# --------------------------------------------------------------------------
	print("Test 6 - Explicit direction parameter override...")
	var explicit_dir := Vector3(1.0, 0.0, 1.0).normalized()
	var test6_data := {"dir": Vector3.ZERO}
	player.dodge_started.connect(func(dir: Vector3):
		test6_data["dir"] = dir
	)

	player.dodge(explicit_dir)
	assert(test6_data["dir"].is_equal_approx(explicit_dir), "Dodge must follow explicit direction passed in argument")

	# Reset dodge state for next test
	player.is_dodging = false
	player._can_dodge = true

	# --------------------------------------------------------------------------
	# Test 7: Faster movespeed (stat) moves further
	# --------------------------------------------------------------------------
	print("Test 7 - Faster base speed moves further...")
	var original_speed := player.speed
	player.speed = 9.0 # Faster speed stat
	var faster_distance := player.get_dodge_distance()
	print("Speed: 6.0 -> Dist: ", normal_dodge_distance, " | Speed: 9.0 -> Dist: ", faster_distance)
	assert(faster_distance > normal_dodge_distance, "Faster player must have greater dodge distance")
	assert(is_equal_approx(faster_distance, player.base_dodge_distance * (9.0 / 6.0)), "Distance must scale proportionally with speed")
	player.speed = original_speed

	# --------------------------------------------------------------------------
	# Test 8: Faster movespeed on boosted ground moves further
	# --------------------------------------------------------------------------
	print("Test 8 - Faster movespeed on boosted ground moves further...")
	player.global_position = Vector3(0.0, 0.0, 0.0) # Center patch
	player._physics_process(0.016)
	assert(player.is_boosted() == true, "Player at center must be boosted")

	var boosted_effective_speed := player.get_effective_max_speed()
	var boosted_dodge_distance := player.get_dodge_distance()
	print("Normal distance: ", normal_dodge_distance, " | Boosted distance: ", boosted_dodge_distance)

	assert(boosted_effective_speed > player.speed, "Effective movespeed must be boosted on center patch")
	assert(boosted_dodge_distance > normal_dodge_distance, "Dodge distance on boosted ground must be larger than on normal ground")
	assert(is_equal_approx(boosted_dodge_distance, player.base_dodge_distance * (boosted_effective_speed / 6.0)), "Boosted dodge distance must scale with boosted movespeed")

	# --------------------------------------------------------------------------
	# Test 9: Space bar input triggers dodge
	# --------------------------------------------------------------------------
	print("Test 9 - Space bar triggers dodge via input...")
	player.is_dodging = false
	player._can_dodge = true

	var space_event := InputEventKey.new()
	space_event.keycode = KEY_SPACE
	space_event.pressed = true
	space_event.echo = false

	# Test player fallback input
	player._unhandled_input(space_event)
	assert(player.is_dodging == true, "Space key in player._unhandled_input must trigger dodge")

	# Reset for main scene input test
	player.is_dodging = false
	player._can_dodge = true

	main_scene._unhandled_input(space_event)
	assert(player.is_dodging == true, "Space key in main_scene._unhandled_input must trigger dodge")

	print("--- ALL DODGE, ANTI-SLIP & DISTANCE SCALING TESTS PASSED SUCCESSFULLY! ---")
	quit(0)
