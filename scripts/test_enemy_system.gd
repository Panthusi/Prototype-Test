extends SceneTree

func _init() -> void:
	print("--- Running Enemy Follow, Ground Destruction, Sword Attack, Healthbars & Revive Tests ---")

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
	# Test 1: Enemy Stats, Groups & Tankiness
	# --------------------------------------------------------------------------
	print("Test 1 - Verifying Enemy stats, tankiness, and groups...")
	assert(enemy.is_in_group("damageable"), "Enemy must be in 'damageable' group")
	assert(enemy.is_in_group("enemy"), "Enemy must be in 'enemy' group")
	assert(player.is_in_group("player"), "Player must be in 'player' group")
	assert(player.is_in_group("damageable"), "Player must be in 'damageable' group")

	print("Player Max HP: ", player.max_health, " | Enemy Max HP: ", enemy.max_health)
	assert(enemy.max_health > player.max_health, "Enemy must be tankier than player (Enemy HP > Player HP)")
	assert(enemy.max_health >= 150.0, "Enemy must have at least 150 HP to be tanky")
	assert(enemy.current_health == enemy.max_health, "Enemy should start with full health")
	assert(enemy.revive_after_death == true, "revive_after_death boolean must default to true")
	assert(is_equal_approx(enemy.revive_delay, 5.0), "revive_delay must be 5.0 seconds")

	# --------------------------------------------------------------------------
	# Test 2: Healthbars for Player and Enemy
	# --------------------------------------------------------------------------
	print("Test 2 - Verifying Healthbars...")
	var player_bar: HealthBar3D = player.get_node_or_null("HealthBar3D") as HealthBar3D
	var enemy_bar: HealthBar3D = enemy.get_node_or_null("HealthBar3D") as HealthBar3D

	assert(player_bar != null, "Player must have an overhead HealthBar3D")
	assert(enemy_bar != null, "Enemy must have an overhead HealthBar3D")
	assert(main_scene.get("_player_health_bar") != null, "Main HUD must have Player health bar")

	# Damage player and verify healthbar reacts
	var initial_player_hp := player.current_health
	player.take_damage(20.0)
	print("Player HP after 20 damage: ", player.current_health)
	assert(player.current_health == initial_player_hp - 20.0, "Player health must decrease by 20")

	# Damage enemy and verify healthbar reacts
	var initial_enemy_hp := enemy.current_health
	enemy.take_damage(25.0)
	print("Enemy HP after 25 damage: ", enemy.current_health)
	assert(enemy.current_health == initial_enemy_hp - 25.0, "Enemy health must decrease by 25")

	# Heal back for subsequent tests
	player.current_health = player.max_health
	enemy.current_health = enemy.max_health
	enemy_bar.update_health(enemy.current_health, enemy.max_health)
	player_bar.update_health(player.current_health, player.max_health)

	# --------------------------------------------------------------------------
	# Test 3: Enemy Follows Player
	# --------------------------------------------------------------------------
	print("Test 3 - Verifying Enemy follows the player...")
	player.global_position = Vector3(0.0, 0.0, 0.0)
	enemy.global_position = Vector3(10.0, 0.0, 0.0)
	enemy.current_state = Enemy.State.CHASE

	# Run physics step
	enemy._physics_process(0.05)

	print("Enemy velocity chasing player: ", enemy.velocity)
	assert(enemy.velocity.x < -0.5, "Enemy must move in -X direction towards player at (0, 0, 0)")
	assert(is_equal_approx(enemy.velocity.z, 0.0), "Enemy should have ~0 Z velocity when player is straight along X")

	# --------------------------------------------------------------------------
	# Test 4: Stepping over player color destroys it
	# --------------------------------------------------------------------------
	print("Test 4 - Verifying stepping over player-created color destroys it...")
	var test_paint_pos := Vector3(16.0, 0.0, 16.0)

	# Paint circle at test location
	ground.paint_circle(test_paint_pos, 2.0)
	assert(ground.is_boosted_at(test_paint_pos) == true, "Ground at test position must be boosted initially")
	assert(ground.has_player_color_at(test_paint_pos) == true, "Ground must register player color")

	# Place enemy on the painted color
	enemy.global_position = test_paint_pos
	enemy._physics_process(0.016)

	# Verify the color was destroyed under enemy feet!
	var destroyed := not ground.has_player_color_at(test_paint_pos)
	print("Player color destroyed at enemy feet: ", destroyed)
	assert(destroyed == true, "Player color must be destroyed when enemy steps over it!")
	assert(ground.is_boosted_at(test_paint_pos) == false, "Ground must no longer be boosted after enemy steps on it")

	# Verify permanent center patch at (0, 0, 0) is NOT destroyed
	enemy.global_position = Vector3(0.0, 0.0, 0.0)
	enemy._physics_process(0.016)
	assert(ground.is_boosted_at(Vector3(0.0, 0.0, 0.0)) == true, "Permanent center patch must NOT be destroyed by enemy stepping on it")

	# --------------------------------------------------------------------------
	# Test 5: Charge-up sword attack when in range
	# --------------------------------------------------------------------------
	print("Test 5 - Verifying charge-up sword attack when player in range...")
	# Place player in attack range (e.g. 2.2m from enemy)
	enemy.global_position = Vector3(15.0, 0.0, 15.0)
	player.global_position = Vector3(15.0, 0.0, 13.0) # 2.0m away along -Z
	enemy.current_state = Enemy.State.CHASE
	enemy._can_attack = true

	enemy._physics_process(0.016)
	print("Enemy state when in range: ", enemy.current_state)
	assert(enemy.current_state == Enemy.State.CHARGE_UP, "Enemy must enter CHARGE_UP state when in attack range")
	assert(Vector2(enemy.velocity.x, enemy.velocity.z).length() < 0.05, "Enemy horizontal velocity should be stopped during charge up")
	assert(enemy.charge_indicator.visible == true, "Charge indicator must be visible during charge up")

	# --------------------------------------------------------------------------
	# Test 6: Attack execution damages player & destroys ground
	# --------------------------------------------------------------------------
	print("Test 6 - Verifying attack strike damages player and destroys ground...")
	# Paint ground in front of enemy
	var strike_ground_pos := Vector3(15.0, 0.0, 13.5)
	ground.paint_circle(strike_ground_pos, 2.5)
	assert(ground.has_player_color_at(strike_ground_pos) == true, "Ground in strike zone must be painted")

	var player_hp_before := player.current_health
	# Execute sword strike
	enemy._execute_sword_attack()

	print("Enemy state after executing attack: ", enemy.current_state)
	assert(enemy.current_state == Enemy.State.ATTACK_SWING, "Enemy should be in ATTACK_SWING state")
	assert(player.current_health < player_hp_before, "Player must take damage from sword attack strike")
	print("Player took damage: ", player_hp_before, " -> ", player.current_health)

	# Verify ground in attack area was destroyed
	assert(ground.has_player_color_at(strike_ground_pos) == false, "Ground must be destroyed when enemy sword attacks!")
	print("Ground in sword attack area successfully destroyed: true")

	# --------------------------------------------------------------------------
	# Test 7: Revive after 5 seconds boolean
	# --------------------------------------------------------------------------
	print("Test 7 - Verifying revive system...")
	enemy.revive_after_death = true
	enemy.take_damage(enemy.max_health + 50.0)

	assert(enemy.current_health == 0.0, "Enemy health should be 0 after lethal damage")
	assert(enemy.current_state == Enemy.State.DEAD, "Enemy should be in DEAD state")
	assert(enemy.collision_shape.disabled == true, "Collision must be disabled while dead")

	# Trigger revive (simulating the 5s timer callback)
	print("Triggering revive...")
	enemy.revive()

	assert(enemy.current_health == enemy.max_health, "Enemy health must be fully restored upon revive")
	assert(enemy.current_state == Enemy.State.CHASE, "Enemy state must return to CHASE upon revive")
	assert(enemy.collision_shape.disabled == false, "Collision must be re-enabled upon revive")
	print("Enemy successfully revived with full HP: ", enemy.current_health)

	# Verify revive_after_death boolean toggle: when false, enemy stays dead
	print("Testing revive_after_death = false...")
	enemy.revive_after_death = false
	enemy.take_damage(enemy.max_health + 50.0)
	assert(enemy.current_state == Enemy.State.DEAD, "Enemy should be dead")
	assert(enemy.revive_after_death == false, "revive_after_death should remain false")

	# Restore revive setting to true for interactive play
	enemy.revive_after_death = true
	enemy.revive()

	print("--- ALL ENEMY SYSTEM TESTS PASSED SUCCESSFULLY! ---")
	quit(0)
