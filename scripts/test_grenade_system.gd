extends SceneTree

func _init() -> void:
	print("--- Running Grenade Throw, Arc, Explosion & Expanding Grass Circle Tests ---")

	# 1. Load Main scene
	var main_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_scene)

	# Wait a frame for _ready
	await process_frame

	var ground: Ground = main_scene.get_node("Ground")
	var player: Player = main_scene.get_node("Player")

	assert(ground != null, "Ground node must exist")
	assert(player != null, "Player node must exist")
	assert(player.can_throw_grenade() == true, "Player must initially be able to throw a grenade")

	# --------------------------------------------------------------------------
	# Test 1: Grenade is thrown in the direction the player is looking at
	# --------------------------------------------------------------------------
	print("Test 1 - Testing throw in facing direction (North / -Z)...")
	# Set player orientation facing -Z (North)
	player.basis = Basis.looking_at(Vector3(0, 0, -1), Vector3.UP).orthonormalized()
	var facing_dir := -player.basis.z
	print("Player facing direction: ", facing_dir)

	var test1_data := {"signal_received": false, "spawned_grenade": null}
	player.grenade_thrown.connect(func(g: Node3D):
		test1_data["signal_received"] = true
		test1_data["spawned_grenade"] = g as Grenade
	)

	var success := player.throw_grenade()
	assert(success == true, "throw_grenade() must return true")
	assert(test1_data["signal_received"] == true, "grenade_thrown signal must be emitted")
	var spawned_grenade: Grenade = test1_data["spawned_grenade"]
	assert(spawned_grenade != null, "Spawned grenade must be valid instance of Grenade")
	assert(spawned_grenade.is_inside_tree(), "Spawned grenade must be added to the scene tree")

	# Check launch velocity direction matches player facing direction
	print("Grenade velocity: ", spawned_grenade.velocity)
	assert(spawned_grenade.velocity.z < -5.0, "Grenade must travel forward in -Z facing direction")
	assert(abs(spawned_grenade.velocity.x) < 0.1, "Grenade X velocity should be approximately zero when facing -Z")
	assert(spawned_grenade.velocity.y > 0.0, "Grenade must have upward arc velocity")

	# --------------------------------------------------------------------------
	# Test 2: Throwing in a different facing direction (East / +X)
	# --------------------------------------------------------------------------
	print("Test 2 - Testing throw in facing direction (East / +X)...")
	# Reset cooldown for testing
	player._can_throw_grenade = true
	# Face East (+X)
	player.basis = Basis.looking_at(Vector3(1, 0, 0), Vector3.UP).orthonormalized()
	var east_facing := -player.basis.z

	var test2_data := {"east_grenade": null}
	player.grenade_thrown.connect(func(g: Node3D):
		test2_data["east_grenade"] = g as Grenade
	, CONNECT_ONE_SHOT)

	player.throw_grenade()
	var east_grenade: Grenade = test2_data["east_grenade"]
	assert(east_grenade != null, "East grenade must spawn")
	print("East grenade velocity: ", east_grenade.velocity)
	assert(east_grenade.velocity.x > 5.0, "Grenade must travel East (+X)")
	assert(abs(east_grenade.velocity.z) < 0.1, "Grenade Z velocity should be approximately zero when facing +X")

	# --------------------------------------------------------------------------
	# Test 3: Grenade explosion creates circle of grass in shader
	# --------------------------------------------------------------------------
	print("Test 3 - Testing explosion creates grass circle in shader...")
	var test_impact_pos := Vector3(16.0, 0.0, 16.0)
	assert(ground.is_boosted_at(test_impact_pos) == false, "Test spot must not be boosted before explosion")

	# Explode east_grenade at test_impact_pos
	east_grenade.global_position = test_impact_pos
	east_grenade.explode()

	assert(ground.is_boosted_at(test_impact_pos) == true, "Center of explosion must be boosted immediately")

	# Wait for expanding circle to grow outward from center
	await create_timer(east_grenade.grow_duration + 0.05).timeout

	# Check points within blast radius
	var inside_point := test_impact_pos + Vector3(2.0, 0.0, 0.0)
	var outside_point := test_impact_pos + Vector3(6.0, 0.0, 0.0)
	assert(ground.is_boosted_at(inside_point) == true, "Point inside blast radius (2m away) must be boosted after growing")
	assert(ground.is_boosted_at(outside_point) == false, "Point outside blast radius (6m away) must NOT be boosted")

	# Check mask pixel color (disconnected grass slash: R > 0)
	var p := ground.world_to_pixel(test_impact_pos)
	var col := ground.mask_image.get_pixel(p.x, p.y)
	print("Test 3 - Mask pixel at grass circle center: ", col)
	assert(col.r > 0.0, "Grass circle must be stamped into mask image (R > 0)")

	# --------------------------------------------------------------------------
	# Test 4: Player moves faster on the grenade grass circle
	# --------------------------------------------------------------------------
	print("Test 4 - Testing player speed boost on grenade grass circle...")
	player.global_position = test_impact_pos
	player._physics_process(0.016)

	print("Player is_boosted on grenade grass: ", player.is_boosted())
	print("Player effective max speed: ", player.get_effective_max_speed(), " (Base speed: ", player.speed, ")")
	assert(player.is_boosted() == true, "Player on grenade grass circle MUST be boosted")
	assert(player.get_effective_max_speed() > player.speed, "Player speed must be higher on grenade grass")
	assert(is_equal_approx(player.get_effective_max_speed(), player.speed * player.ground_boost_multiplier), "Player speed must match ground_boost_multiplier")

	# --------------------------------------------------------------------------
	# Test 5: Growing from center out (paint_expanding_circle)
	# --------------------------------------------------------------------------
	print("Test 5 - Testing expanding circle from center out...")
	var expand_center := Vector3(-16.0, 0.0, -16.0)
	assert(ground.is_boosted_at(expand_center) == false, "Expand center must not be boosted initially")

	var tween := ground.paint_expanding_circle(expand_center, 4.0, 0.2)
	assert(tween != null, "paint_expanding_circle must return a valid Tween")
	# Initial small center stamp is created immediately
	assert(ground.is_boosted_at(expand_center) == true, "Center stamp must be created immediately")

	# Point 3.5m away should NOT be stamped at r = 0.4
	var rim_point := expand_center + Vector3(3.2, 0.0, 0.0)
	assert(ground.is_boosted_at(rim_point) == false, "Outer rim must not be boosted at start of growth")

	# Let the expansion tween complete
	await tween.finished
	print("Tween finished! Checking outer rim at 3.2m...")
	assert(ground.is_boosted_at(rim_point) == true, "Outer rim must be boosted after expanding to full circle")

	# --------------------------------------------------------------------------
	# Test 6: Explosion near Dummy deals damage
	# --------------------------------------------------------------------------
	print("Test 6 - Testing damage to TrainingDummy...")
	var dummy1: TrainingDummy = main_scene.get_node("Targets/Dummy1")
	assert(dummy1 != null, "Dummy1 must exist")
	var dummy_pos := dummy1.global_position

	# Reset player cooldown and face Dummy1
	player._can_throw_grenade = true
	var dir_to_dummy := dummy_pos - player.global_position
	player.throw_grenade(dir_to_dummy)

	# Direct grenade explosion next to dummy
	var dummy_grenade := load("res://scenes/grenade.tscn").instantiate() as Grenade
	main_scene.add_child(dummy_grenade)
	dummy_grenade.global_position = dummy_pos + Vector3(0.5, 0.1, 0.0)
	dummy_grenade.explode()

	print("Dummy wobble mesh scale after explosion: ", dummy1.mesh.scale)
	assert(dummy1.mesh.scale != Vector3.ONE, "Dummy must wobble when damaged by grenade explosion")

	# --------------------------------------------------------------------------
	# Test 7: Connected circle turns permanent GREEN
	# --------------------------------------------------------------------------
	print("Test 7 - Testing connected circle turns permanent GREEN...")
	var near_center := Vector3(0.0, 0.0, -3.2)
	ground.paint_circle(near_center, 2.5)

	var p_conn := ground.world_to_pixel(near_center)
	var col_conn := ground.mask_image.get_pixel(p_conn.x, p_conn.y)
	print("Mask pixel for circle touching center: ", col_conn)
	assert(col_conn.g >= 0.99, "Circle touching center must turn connected GREEN (G == 1.0)")
	assert(ground.is_connected_at(near_center) == true, "Circle touching center must be marked connected")

	print("--- ALL GRENADE & EXPANDING GRASS CIRCLE TESTS PASSED SUCCESSFULLY! ---")
	quit(0)
