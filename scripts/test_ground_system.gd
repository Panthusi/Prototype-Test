extends SceneTree

func _init() -> void:
	print("--- Running Ground Shader, Hard Corners & Blue/Green Boost Tests ---")

	# 1. Load Main scene
	var main_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_scene)

	# Allow a frame to process _ready
	await process_frame

	var ground: Ground = main_scene.get_node("Ground")
	var player: Player = main_scene.get_node("Player")

	assert(ground != null, "Ground node must exist")
	assert(player != null, "Player node must exist")
	assert(ground.mask_image != null, "Mask image must be initialized")
	assert(ground.mask_texture != null, "Mask texture must be initialized")

	# --------------------------------------------------------------------------
	# Test 1: Center patch is permanent & boosted
	# --------------------------------------------------------------------------
	var center_val = ground.get_mask_value(Vector3(0, 0, 0))
	var center_boosted = ground.is_boosted_at(Vector3(0, 0, 0))
	print("Test 1 - Center patch at (0, 0, 0): boosted =", center_boosted, "mask_val =", center_val)
	assert(center_boosted == true, "Center patch must be boosted by default")

	# Move player to center patch
	player.global_position = Vector3(0, 0, 0)
	player._physics_process(0.016)
	print("Test 1 - Player at center is_boosted: ", player.is_boosted())
	assert(player.is_boosted() == true, "Player standing on center patch must be boosted")

	# Point far away from center should NOT be boosted initially
	var far_point = Vector3(15, 0, 15)
	assert(ground.is_boosted_at(far_point) == false, "Far point must not be boosted initially")

	# --------------------------------------------------------------------------
	# Test 2: Player IS fast on the BLUE slash (before it fades)
	# --------------------------------------------------------------------------
	print("Test 2 - Creating blue slash far from center at (15, 0, 15)...")
	# Slash facing -Z from (15, 0, 15)
	ground.paint_slash(Vector3(15, 0, 15), Vector3(0, 0, -1), 0.8, 4.0, 135.0)

	var slashed_far_point = Vector3(15, 0, 13.5)
	var pixel_far = ground.world_to_pixel(slashed_far_point)
	var pixel_col = ground.mask_image.get_pixel(pixel_far.x, pixel_far.y)
	print("Test 2 - Mask pixel color at blue slash: ", pixel_col)

	# Blue slash has R > 0 (visible cyan slash color), G == 0 (disconnected)
	assert(pixel_col.r > 0.0, "Blue slash must have R > 0")
	assert(pixel_col.g == 0.0, "Blue slash must NOT have G == 1.0 (not green)")

	# User request: "make it that u are also fast on the blue"
	assert(ground.is_boosted_at(slashed_far_point) == true, "Player MUST be boosted on active blue ground")

	# Player on blue slash IS boosted!
	player.global_position = slashed_far_point
	player._physics_process(0.016)
	print("Test 2 - Player on blue slash is_boosted: ", player.is_boosted(), " Speed: ", player.get_effective_max_speed())
	assert(player.is_boosted() == true, "Player on blue slash must receive speed boost")
	assert(player.get_effective_max_speed() > player.speed, "Player speed must be higher on blue ground")

	# --------------------------------------------------------------------------
	# Test 3: Connected slash (touches center patch -> turns GREEN & permanent boost)
	# --------------------------------------------------------------------------
	print("Test 3 - Creating connected slash touching the center patch at (0, 0, -2.5)...")
	ground.paint_slash(Vector3(0, 0, -2.5), Vector3(0, 0, -1), 0.5, 4.0, 135.0)

	var connected_point = Vector3(0, 0, -4.5)
	var pixel_conn = ground.world_to_pixel(connected_point)
	var conn_col = ground.mask_image.get_pixel(pixel_conn.x, pixel_conn.y)
	print("Test 3 - Mask pixel color at connected slash: ", conn_col)

	# Connected slash must be GREEN (G == 1.0)
	assert(conn_col.g >= 0.99, "Connected slash must turn GREEN (G == 1.0)")
	assert(ground.is_boosted_at(connected_point) == true, "Connected slash must give speed boost")

	# Player on connected green trail gets speed boost
	player.global_position = connected_point
	player._physics_process(0.016)
	print("Test 3 - Player on connected slash is_boosted: ", player.is_boosted(), " Effective speed: ", player.get_effective_max_speed())
	assert(player.is_boosted() == true, "Player on connected slash must receive speed boost")

	# --------------------------------------------------------------------------
	# Test 4: When blue slash fades away, the buff goes away!
	# --------------------------------------------------------------------------
	print("Test 4 - Simulating 5.1 seconds of fading for blue slash...")
	ground._process(5.1)

	var faded_pixel_col = ground.mask_image.get_pixel(pixel_far.x, pixel_far.y)
	print("Test 4 - Mask pixel color at blue point after 5s: ", faded_pixel_col)
	assert(faded_pixel_col.r == 0.0, "Blue slash must completely fade away (R = 0.0)")

	# User request: "but when i faded away the buff goes away"
	assert(ground.is_boosted_at(slashed_far_point) == false, "Speed buff MUST go away when blue slash has faded")

	player.global_position = slashed_far_point
	player._physics_process(0.016)
	print("Test 4 - Player on faded ground is_boosted: ", player.is_boosted(), " Effective speed: ", player.get_effective_max_speed())
	assert(player.is_boosted() == false, "Player must NOT be boosted once blue ground has faded away")
	assert(is_equal_approx(player.get_effective_max_speed(), player.speed), "Player speed must return to base speed")

	# Center patch and connected green remain intact and boosted!
	assert(ground.is_boosted_at(Vector3(0, 0, 0)) == true, "Center patch must stay permanent forever")
	assert(ground.is_boosted_at(connected_point) == true, "Connected green trail must stay intact and boosted")

	print("--- ALL BLUE / GREEN BOOST TESTS PASSED SUCCESSFULLY! ---")
	quit(0)
