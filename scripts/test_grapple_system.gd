extends SceneTree

func _init() -> void:
	print("--- Running Grappling Hook System Tests ---")

	# 1. Load Main scene
	var main_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_scene)

	# Wait a frame for _ready
	await process_frame

	var ground: Ground = main_scene.get_node_or_null("Ground") as Ground
	var player: Player = main_scene.get_node_or_null("Player") as Player
	var enemy: Enemy = main_scene.get_node_or_null("Enemy") as Enemy

	assert(ground != null, "Ground node must exist in main.tscn")
	assert(player != null, "Player node must exist in main.tscn")
	assert(enemy != null, "Enemy node must exist in main.tscn")

	# --------------------------------------------------------------------------
	# Test 1: Grappling Hook Properties and Export Variables
	# --------------------------------------------------------------------------
	print("Test 1 - Verifying Grappling Hook exported properties...")
	assert("hook_can_target_enemies" in player, "Player must have hook_can_target_enemies property")
	assert(player.hook_can_target_enemies == true, "hook_can_target_enemies should default to true")
	assert(player.hook_max_range >= 10.0, "hook_max_range should be at least 10.0m")
	assert(player.hook_pull_speed >= 10.0, "hook_pull_speed should be high for snappy pull")
	assert(player.can_grapple() == true, "Player should initially be able to grapple")
	assert(player.is_hooking == false, "Player should initially not be hooking")

	# --------------------------------------------------------------------------
	# Test 2: Cannot Hook to Unpainted Base Ground
	# --------------------------------------------------------------------------
	print("Test 2 - Verifying Hook fails on unpainted plain ground...")
	# Place player at (0, 0, 0)
	player.global_position = Vector3(0.0, 0.0, 0.0)
	# Far unpainted position (35, 0, 35) is outside center patch and unpainted
	var unpainted_pos := Vector3(25.0, 0.0, 25.0)
	assert(player.is_ground_hookable_at(unpainted_pos) == false, "Unpainted ground must not be hookable")

	# Attempt to hook specifically to unpainted pos with no enemies around
	player.hook_can_target_enemies = false
	var hooked_plain := player.grapple_hook(unpainted_pos)
	assert(hooked_plain == false, "grapple_hook to unpainted ground must return false")
	assert(player.is_hooking == false, "Player should not enter hooking state for unpainted ground")

	# --------------------------------------------------------------------------
	# Test 3: Hook to Permanent Center Patch Ground
	# --------------------------------------------------------------------------
	print("Test 3 - Verifying Hook attaches to permanent center patch...")
	player.hook_can_target_enemies = true
	# Center patch is between (-3, -3) and (+3, +3). Diagonal approach clears Dummy1-4
	player.global_position = Vector3(7.0, 0.0, 7.0)
	var center_pos := Vector3(1.0, 0.0, 1.0)
	assert(player.is_ground_hookable_at(center_pos) == true, "Center patch must be hookable")

	var test3_data := {"signal_fired": false, "target_pos": Vector3.ZERO}
	player.hook_started.connect(func(pos, _node):
		test3_data["signal_fired"] = true
		test3_data["target_pos"] = pos
	)

	var hook_center_success := player.grapple_hook(center_pos)
	assert(hook_center_success == true, "grapple_hook to center patch must succeed")
	assert(player.is_hooking == true, "Player should be in hooking state")
	assert(test3_data["signal_fired"] == true, "hook_started signal must be emitted")
	var target_vector: Vector3 = test3_data["target_pos"]
	assert(target_vector.is_equal_approx(center_pos), "Target pos must match hook point")

	# Run physics process while hooking to verify player moves towards center patch
	var prev_dist := player.global_position.distance_to(center_pos)
	player._physics_process(0.1)
	var new_dist := player.global_position.distance_to(center_pos)
	print("Player distance to center before step: ", prev_dist, " | after step: ", new_dist)
	assert(new_dist < prev_dist, "Player must be pulled towards the hook point")

	# Wait until hook finishes
	var timeout_steps := 100
	while player.is_hooking and timeout_steps > 0:
		player._physics_process(0.05)
		timeout_steps -= 1
		if timeout_steps % 10 == 0:
			print("Step remaining: ", timeout_steps, " | Pos: ", player.global_position, " | dist: ", player.global_position.distance_to(center_pos))

	print("Final player pos: ", player.global_position, " | is_hooking: ", player.is_hooking)
	assert(player.is_hooking == false, "Hook must finish upon arriving at target")
	assert(player.global_position.distance_to(center_pos) <= player.hook_arrival_threshold + 0.5, "Player should arrive near center pos")
	print("Successfully hooked and pulled to center patch!")

	# Reset cooldown for subsequent tests
	player._can_hook = true

	# --------------------------------------------------------------------------
	# Test 4: Hook to Slash / Bomb Painted Ground (Color Ground)
	# --------------------------------------------------------------------------
	print("Test 4 - Verifying Hook attaches to player-painted slash & bomb ground...")
	player.global_position = Vector3(12.0, 0.0, 12.0)
	var painted_pos := Vector3(20.0, 0.0, 12.0)

	# Paint circle at painted_pos (simulating bomb/slash color)
	ground.paint_circle(painted_pos, 3.0)
	assert(player.is_ground_hookable_at(painted_pos) == true, "Painted ground must be hookable")

	var hook_paint_success := player.grapple_hook(painted_pos)
	assert(hook_paint_success == true, "grapple_hook to painted ground must succeed")
	assert(player.is_hooking == true, "Player should be in hooking state")

	# Wait until hook finishes
	timeout_steps = 100
	while player.is_hooking and timeout_steps > 0:
		player._physics_process(0.05)
		timeout_steps -= 1
		if timeout_steps % 10 == 0:
			print("Test 4 Step: ", timeout_steps, " | Pos: ", player.global_position, " | dist: ", player.global_position.distance_to(painted_pos))
	print("Test 4 End: Pos: ", player.global_position, " | is_hooking: ", player.is_hooking)
	assert(player.is_hooking == false, "Hook should finish")
	assert(player.global_position.distance_to(painted_pos) <= player.hook_arrival_threshold + 0.5, "Player should arrive at painted ground")
	print("Successfully hooked and pulled to painted color ground!")

	player._can_hook = true

	# --------------------------------------------------------------------------
	# Test 5: Hook to Enemies (when hook_can_target_enemies is true)
	# --------------------------------------------------------------------------
	print("Test 5 - Verifying Hook attaches to Enemy when hook_can_target_enemies = true...")
	player.hook_can_target_enemies = true
	player.global_position = Vector3(0.0, 0.0, 0.0)
	enemy.global_position = Vector3(10.0, 0.0, 10.0)

	# Enemy is placed on unpainted ground (10, 0, 10)
	var enemy_pos := enemy.global_position

	var test5_data := {"latched_node": null}
	player.hook_started.connect(func(_pos, node):
		test5_data["latched_node"] = node
	)

	var hook_enemy_success := player.grapple_hook(enemy_pos)
	assert(hook_enemy_success == true, "grapple_hook to enemy must succeed when hook_can_target_enemies = true")
	assert(player.is_hooking == true, "Player should be hooking towards enemy")
	assert(test5_data["latched_node"] == enemy, "Hook should have latched directly onto Enemy node")

	# Pull towards enemy
	timeout_steps = 100
	while player.is_hooking and timeout_steps > 0:
		player._physics_process(0.05)
		timeout_steps -= 1

	assert(player.is_hooking == false, "Hook should finish upon reaching enemy")
	assert(player.global_position.distance_to(enemy.global_position) <= player.hook_arrival_threshold + 1.0, "Player should arrive near enemy")
	print("Successfully hooked and pulled to enemy!")

	player._can_hook = true

	# --------------------------------------------------------------------------
	# Test 6: hook_can_target_enemies = false disables hooking onto enemies
	# --------------------------------------------------------------------------
	print("Test 6 - Verifying hook_can_target_enemies = false disables hooking to enemy...")
	player.hook_can_target_enemies = false
	player.global_position = Vector3(0.0, 0.0, 0.0)
	# Move enemy to an unpainted location (so ground beneath isn't hookable)
	var far_enemy_pos := Vector3(-15.0, 0.0, -15.0)
	enemy.global_position = far_enemy_pos
	assert(player.is_ground_hookable_at(far_enemy_pos) == false, "Ground beneath far enemy must not be painted")

	var hook_enemy_disabled := player.grapple_hook(far_enemy_pos)
	assert(hook_enemy_disabled == false, "Hook must fail when enemy targeting is disabled and ground is unpainted")
	assert(player.is_hooking == false, "Player must not hook to enemy when hook_can_target_enemies is false")
	print("Correctly prevented hooking onto enemy when hook_can_target_enemies = false!")

	# Restore hook_can_target_enemies = true
	player.hook_can_target_enemies = true

	print("--- ALL GRAPPLING HOOK SYSTEM TESTS PASSED SUCCESSFULLY! ---")
	quit(0)
