class_name Player
extends CharacterBody3D

## Signals for external systems
signal position_changed(new_pos: Vector3)
signal destination_reached()
signal attack_started()
signal attack_finished()
signal attack_hit(target: Node3D)
signal boosted_status_changed(is_boosted: bool, factor: float)
signal grenade_thrown(grenade: Node3D)
signal dodge_started(direction: Vector3)
signal dodge_finished()
signal health_changed(current: float, max_health: float)
signal died()
signal hook_started(target_pos: Vector3, target_node: Variant)
signal hook_finished()

@export_group("Health Settings")
## Maximum health points of the player
@export var max_health: float = 100.0:
	set(val):
		max_health = maxf(val, 1.0)
		current_health = minf(current_health, max_health)
## Current health points of the player
@export var current_health: float = 100.0:
	set(val):
		current_health = clampf(val, 0.0, max_health)

@export_group("Movement Settings")
## Maximum walking speed on the plane
@export var speed: float = 6.0
## Acceleration rate when starting movement
@export var acceleration: float = 20.0
## Friction / deceleration rate when stopping
@export var friction: float = 25.0
## Speed of turning to face movement direction
@export var rotation_speed: float = 12.0
## Gravity applied when not grounded
@export var gravity: float = 20.0

@export_group("Ground Boost Settings")
## Multiplier for movement speed when moving over slashed ground
@export var ground_boost_multiplier: float = 1.75
## Acceleration multiplier when on boosted ground for snappy response
@export var ground_boost_accel_multiplier: float = 1.5
## Optional reference to Ground node (auto-found if not set)
@export var ground: Node = null
## Enables or disables creating marks/slashes on the ground during attacks
@export var enable_ground_creation: bool = true

@export_group("Attack Settings")
## Damage dealt by the slash attack
@export var attack_damage: float = 25.0
## Duration of the active slash animation (seconds)
@export var attack_duration: float = 0.16
## Minimum delay between consecutive attacks (seconds)
@export var attack_cooldown: float = 0.18
## Slight forward momentum impulse applied during a slash
@export var attack_lunge_speed: float = 2.8
## Inner radius of the slash blade arc
@export var slash_inner_radius: float = 1.0
## Outer radius of the slash blade arc (makes the slash bigger)
@export var slash_outer_radius: float = 3.4
## Sweep angle of the slash arc in degrees (wider sweep)
@export var slash_arc_degrees: float = 135.0

@export_group("Grenade Settings")
## Scene to instantiate when throwing a grenade
@export var grenade_scene: PackedScene = null
## Forward throw speed
@export var grenade_throw_speed: float = 12.0
## Upward launch speed for arcing trajectory
@export var grenade_upward_speed: float = 5.5
## Radius of the grass circle created by grenade explosion
@export var grenade_blast_radius: float = 4.0
## Duration for the circle to expand from the center outward (seconds)
@export var grenade_grow_duration: float = 0.35
## Minimum delay between consecutive grenade throws (seconds)
@export var grenade_cooldown: float = 0.8
## Damage dealt by the grenade explosion
@export var grenade_damage: float = 50.0
## Enables or disables creating grass on the ground during grenade explosion
@export var enable_grenade_ground_creation: bool = true

@export_group("Dodge Settings")
## Base distance (in meters) covered by the dodge at normal movement speed
@export var base_dodge_distance: float = 2.2
## Duration of the dodge action (seconds)
@export var dodge_duration: float = 0.16
## Minimum delay between consecutive dodges (seconds)
@export var dodge_cooldown: float = 0.35
## Multiplier applied to effective movement speed during dodge (compat)
@export var dodge_speed_multiplier: float = 2.2

@export_group("Grappling Hook Settings")
## Enable or disable grappling onto enemies
@export var hook_can_target_enemies: bool = true
## Maximum range of the grappling hook (meters)
@export var hook_max_range: float = 24.0
## Pull / travel speed towards the hooked target (meters/second)
@export var hook_pull_speed: float = 22.0
## Minimum delay between consecutive grappling hook uses (seconds)
@export var hook_cooldown: float = 0.5
## Distance threshold to consider arrival at grappling target
@export var hook_arrival_threshold: float = 1.2
## Slight impulse / momentum boost forward upon finishing hook pull
@export var hook_finish_boost: float = 4.0

@export_group("External Control")
## If true, reads default keyboard (WASD / Arrows / Space / F / J / E / Q / R / Shift) when external input is zero.
@export var enable_keyboard_fallback: bool = true

## External directional input vector (X = right/left, Y = down/up).
## Set this directly from outside, or use set_move_input().
var external_input: Vector2 = Vector2.ZERO

## Target position on plane if using destination-based movement
var target_destination: Variant = null
var destination_arrival_threshold: float = 0.2

## Attack state
var is_attacking: bool = false
var _can_attack: bool = true

## Grenade state
var _can_throw_grenade: bool = true

## Dodge state
var is_dodging: bool = false
var _can_dodge: bool = true
var _dodge_direction: Vector3 = Vector3.ZERO
var _current_dodge_speed: float = 0.0
var _dodge_distance_target: float = 0.0
var _dodge_distance_traveled: float = 0.0

## Grappling Hook state
var is_hooking: bool = false
var _can_hook: bool = true
var _hook_target_pos: Vector3 = Vector3.ZERO
var _hook_target_node: Node3D = null
var _hook_line_mesh: ImmediateMesh
var _hook_line_instance: MeshInstance3D

## Ground boost tracking
var current_boost_factor: float = 0.0
var is_on_slash_ground: bool = false

@onready var slash_hitbox: Area3D = $SlashHitbox
@onready var slash_pivot: Node3D = $SlashPivot
@onready var slash_mesh: MeshInstance3D = $SlashPivot/SlashMesh
@onready var visor: MeshInstance3D = $Visor

var _slash_material: StandardMaterial3D
var _slash_tween: Tween
var _visor_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	_setup_slash_visual()
	_setup_visor_visual()
	_setup_hook_visual()
	_find_ground()

	var health_bar: HealthBar3D = get_node_or_null("HealthBar3D") as HealthBar3D
	if health_bar:
		health_bar.fill_color = Color(0.2, 0.85, 0.35, 1.0)
		health_bar.label_text = "Player"
		health_bar.update_health(current_health, max_health)
		health_changed.connect(func(cur: float, max_hp: float):
			health_bar.update_health(cur, max_hp)
		)


# ==============================================================================
# Public API (Outside Control)
# ==============================================================================

## Execute a slash attack.
## If target_direction is provided, the player orients towards it before slashing.
## Returns true if the attack successfully initiated.
func slash(target_direction: Vector3 = Vector3.ZERO) -> bool:
	if not _can_attack or is_attacking or is_dodging:
		return false

	is_attacking = true
	_can_attack = false

	# If a specific attack direction was requested from outside, face that direction
	if target_direction.length_squared() > 0.001:
		target_direction.y = 0.0
		var look_basis := Basis.looking_at(target_direction.normalized(), Vector3.UP)
		basis = look_basis.orthonormalized()

	attack_started.emit()
	_execute_slash()
	return true


## Set the 2D movement input from an external controller.
## input_vector: X = left(-1) / right(+1), Y = forward(-1) / backward(+1)
func set_move_input(input_vector: Vector2) -> void:
	external_input = input_vector
	target_destination = null # Clear destination if manual vector is given


## Command the player to walk to a specific 3D destination on the plane.
func move_to(target_pos: Vector3, arrival_threshold: float = 0.2) -> void:
	target_destination = target_pos
	destination_arrival_threshold = arrival_threshold
	external_input = Vector2.ZERO


## Stop all movement and clear inputs/destinations.
func stop() -> void:
	external_input = Vector2.ZERO
	target_destination = null
	if is_dodging:
		_finish_dodge()
	if is_hooking:
		_finish_hook()
	velocity.x = 0.0
	velocity.z = 0.0


## Instantly teleport the player to a target location.
func teleport(target_pos: Vector3) -> void:
	stop()
	global_position = target_pos
	position_changed.emit(global_position)


## Take damage from attacks or hazards
func take_damage(amount: float, _source: Node3D = null) -> void:
	if current_health <= 0.0:
		return

	current_health = clampf(current_health - amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)
	_play_hurt_feedback()

	if current_health <= 0.0:
		died.emit()
		_on_death()


## Restore health points
func heal(amount: float) -> void:
	if current_health <= 0.0:
		return
	current_health = clampf(current_health + amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)


func _on_death() -> void:
	# Auto-restore player after 3 seconds for continuous playtesting
	get_tree().create_timer(3.0).timeout.connect(func():
		if current_health <= 0.0:
			current_health = max_health
			health_changed.emit(current_health, max_health)
	)


func _play_hurt_feedback() -> void:
	var body_mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if body_mesh:
		var flash_mat := StandardMaterial3D.new()
		flash_mat.albedo_color = Color(1.0, 0.2, 0.2, 1.0)
		flash_mat.emission_enabled = true
		flash_mat.emission = Color(1.0, 0.1, 0.1)
		flash_mat.emission_energy_multiplier = 2.0
		body_mesh.material_override = flash_mat

		var tween := create_tween()
		tween.tween_interval(0.12)
		tween.tween_callback(func():
			if body_mesh:
				body_mesh.material_override = null
		)

		var wobble := create_tween()
		wobble.tween_property(body_mesh, "scale", Vector3(1.2, 0.8, 1.2), 0.08)
		wobble.tween_property(body_mesh, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Returns current horizontal velocity magnitude.
func get_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Returns true if the player is currently moving.
func is_moving() -> bool:
	return get_speed() > 0.05


## Returns true if the player is currently able to perform an attack.
func can_attack() -> bool:
	return _can_attack and not is_attacking and not is_dodging and not is_hooking


## Returns true if the player is currently able to perform a dodge.
func can_dodge() -> bool:
	return _can_dodge and not is_dodging and not is_hooking


## Returns effective dodge distance (meters).
## Base distance at normal speed (6.0 m/s); moves further when faster (ground boost / higher speed stat).
func get_dodge_distance() -> float:
	var speed_ratio := get_effective_max_speed() / 6.0
	return base_dodge_distance * speed_ratio


## Returns current dodge speed so that dodge covers get_dodge_distance() in dodge_duration.
func get_dodge_speed() -> float:
	return get_dodge_distance() / maxf(dodge_duration, 0.001)


## Execute a quick dodge dash.
## If target_direction is provided, dodges in that direction.
## Otherwise dodges in the current movement input direction, or facing direction if stationary.
## Returns true if the dodge successfully initiated.
func dodge(target_direction: Vector3 = Vector3.ZERO) -> bool:
	if not _can_dodge or is_dodging:
		return false

	_can_dodge = false
	is_dodging = true

	# Interrupt active attack if mid-slash
	if is_attacking:
		is_attacking = false
		if _slash_tween:
			_slash_tween.kill()
		if slash_pivot:
			slash_pivot.visible = false
		attack_finished.emit()

	# Determine dodge direction
	var dodge_dir := _determine_dodge_direction(target_direction)
	_dodge_direction = dodge_dir

	# Distance and speed scaling: faster speed = moves further
	_dodge_distance_target = get_dodge_distance()
	_dodge_distance_traveled = 0.0
	_current_dodge_speed = get_dodge_speed()

	# Snap facing rotation to dodge direction
	if _dodge_direction.length_squared() > 0.001:
		var look_basis := Basis.looking_at(_dodge_direction, Vector3.UP)
		basis = look_basis.orthonormalized()

	# Apply initial dodge velocity
	velocity.x = _dodge_direction.x * _current_dodge_speed
	velocity.z = _dodge_direction.z * _current_dodge_speed

	dodge_started.emit(_dodge_direction)
	_play_dodge_feedback()

	return true


func _finish_dodge() -> void:
	if not is_dodging:
		return
	is_dodging = false

	# Eliminate lingering momentum so player doesn't slip/slide after dodge
	var input_vec := external_input
	if input_vec.is_zero_approx() and enable_keyboard_fallback:
		input_vec = _read_keyboard_input()

	if not input_vec.is_zero_approx():
		# Instantly resume standard running speed in input direction (no sliding deceleration)
		var move_dir := Vector3(input_vec.x, 0.0, input_vec.y).normalized()
		var cur_speed := get_effective_max_speed()
		velocity.x = move_dir.x * cur_speed
		velocity.z = move_dir.z * cur_speed
	else:
		# Instantly stop dead - no slipping!
		velocity.x = 0.0
		velocity.z = 0.0

	dodge_finished.emit()

	# Cooldown timer begins after dodge finishes
	get_tree().create_timer(dodge_cooldown).timeout.connect(func():
		_can_dodge = true
	)


## Throw a grenade in the direction the player is looking at.
## If target_direction is provided, the player orients towards it before throwing.
## Returns true if the grenade was successfully thrown.
func throw_grenade(target_direction: Vector3 = Vector3.ZERO) -> bool:
	if not _can_throw_grenade or is_dodging:
		return false

	_can_throw_grenade = false

	# If a specific throw direction was requested, face that direction
	if target_direction.length_squared() > 0.001:
		target_direction.y = 0.0
		var look_basis := Basis.looking_at(target_direction.normalized(), Vector3.UP)
		basis = look_basis.orthonormalized()

	# Throw in the direction the player is looking at
	var throw_dir := -basis.z

	if not grenade_scene:
		if ResourceLoader.exists("res://scenes/grenade.tscn"):
			grenade_scene = load("res://scenes/grenade.tscn")

	if not grenade_scene:
		push_error("Player: Could not load grenade_scene")
		_can_throw_grenade = true
		return false

	var grenade := grenade_scene.instantiate() as Grenade
	if not grenade:
		push_error("Player: Instantiated grenade is not of type Grenade")
		_can_throw_grenade = true
		return false

	if not ground:
		_find_ground()

	grenade.thrower = self
	grenade.ground = ground as Ground
	grenade.blast_radius = grenade_blast_radius
	grenade.blast_damage = grenade_damage
	grenade.grow_duration = grenade_grow_duration
	grenade.forward_speed = grenade_throw_speed
	grenade.upward_speed = grenade_upward_speed

	# Add grenade to parent / scene tree first so it is inside tree
	var parent_node := get_parent()
	if not parent_node:
		parent_node = get_tree().current_scene
	if parent_node:
		parent_node.add_child(grenade)
	else:
		add_sibling(grenade)

	# Spawn grenade slightly in front of player at chest height
	var spawn_pos := global_position + Vector3(0.0, 1.1, 0.0) + throw_dir * 0.5
	grenade.global_position = spawn_pos

	# Launch grenade with ballistic arc
	grenade.launch(throw_dir, grenade_throw_speed, grenade_upward_speed)

	grenade_thrown.emit(grenade)
	_play_throw_feedback()

	# Cooldown timer
	get_tree().create_timer(grenade_cooldown).timeout.connect(func():
		_can_throw_grenade = true
	)

	return true


## Returns true if the player is currently able to throw a grenade.
func can_throw_grenade() -> bool:
	return _can_throw_grenade and not is_dodging and not is_hooking


# ==============================================================================
# Grappling Hook Mechanics
# ==============================================================================

## Returns true if the player is currently able to fire the grappling hook.
func can_grapple() -> bool:
	return _can_hook and not is_hooking and not is_dodging


## Check if a given world position on the ground is hookable (has color from slashes, bombs, or center patch).
func is_ground_hookable_at(world_pos: Vector3) -> bool:
	if not ground:
		_find_ground()
	if not ground:
		return false
	if ground.has_method("is_boosted_at") and ground.is_boosted_at(world_pos):
		return true
	if ground.has_method("has_player_color_at") and ground.has_player_color_at(world_pos):
		return true
	if ground.has_method("is_connected_at") and ground.is_connected_at(world_pos):
		return true
	return false


## Check if a given node is an enemy and hookable according to hook_can_target_enemies.
func is_enemy_hookable(target: Node3D) -> bool:
	if not hook_can_target_enemies:
		return false
	if not is_instance_valid(target):
		return false
	if target.is_in_group("enemy"):
		return true
	return false


## Fire grappling hook towards a target 3D point or direction.
## If target_direction is provided and target_override_pos is not set, casts a ray/search along that direction.
## If target_override_pos is provided (e.g. from mouse click), attempts to latch to enemy or painted ground at that location.
## Returns true if the hook successfully latched and started pulling.
func grapple_hook(target_override_pos: Variant = null, target_direction: Vector3 = Vector3.ZERO) -> bool:
	if not can_grapple():
		return false

	var latch_pos: Vector3 = Vector3.ZERO
	var latched_node: Node3D = null
	var found_latch := false

	# 1. Check if specific world destination was provided (e.g. mouse click on ground or entity)
	if target_override_pos != null and target_override_pos is Vector3:
		var candidate_pos: Vector3 = target_override_pos
		var dist_to_candidate := global_position.distance_to(candidate_pos)

		if dist_to_candidate <= hook_max_range:
			# Check for nearby enemy first if enemy targeting is enabled
			if hook_can_target_enemies:
				var candidate_enemy := _find_enemy_near(candidate_pos, 2.0)
				if candidate_enemy:
					latch_pos = candidate_enemy.global_position
					latched_node = candidate_enemy
					found_latch = true

			# If no enemy latched, check for painted ground
			if not found_latch:
				candidate_pos.y = 0.0
				if is_ground_hookable_at(candidate_pos):
					latch_pos = candidate_pos
					found_latch = true

	# 2. If no direct latch found and no specific destination was given, search along aim direction
	if not found_latch and target_override_pos == null:
		var aim_dir := target_direction
		if aim_dir.length_squared() < 0.001:
			var input_vec := external_input
			if input_vec.is_zero_approx() and enable_keyboard_fallback:
				input_vec = _read_keyboard_input()
			if not input_vec.is_zero_approx():
				aim_dir = Vector3(input_vec.x, 0.0, input_vec.y).normalized()
			else:
				aim_dir = -basis.z

		aim_dir.y = 0.0
		aim_dir = aim_dir.normalized()

		# Check for enemies along aim line
		if hook_can_target_enemies:
			var best_enemy := _find_best_enemy_in_direction(aim_dir, hook_max_range)
			if best_enemy:
				latch_pos = best_enemy.global_position
				latched_node = best_enemy
				found_latch = true

		# If no enemy found along line, ray march ground cells along aim direction for painted color
		if not found_latch:
			var ground_hit: Variant = _find_hookable_ground_in_direction(aim_dir, hook_max_range)
			if ground_hit != null:
				latch_pos = ground_hit
				found_latch = true

	if not found_latch:
		# Play a quick fail "dry fire" visor flicker
		_play_hook_fail_feedback()
		return false

	# Successfully latched!
	_start_hook(latch_pos, latched_node)
	return true


func _find_enemy_near(pos: Vector3, search_radius: float) -> Node3D:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	var best_enemy: Node3D = null
	var best_dist: float = search_radius

	for e in enemies:
		if e is Node3D and is_instance_valid(e):
			var node_3d := e as Node3D
			var d: float = pos.distance_to(node_3d.global_position)
			if d < best_dist:
				best_dist = d
				best_enemy = node_3d

	return best_enemy


func _find_best_enemy_in_direction(dir: Vector3, max_range: float) -> Node3D:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	var best_enemy: Node3D = null
	var best_score: float = -999.0

	for e in enemies:
		if e is Node3D and is_instance_valid(e):
			var node_3d := e as Node3D
			var diff: Vector3 = node_3d.global_position - global_position
			diff.y = 0.0
			var dist: float = diff.length()
			if dist <= 0.5 or dist > max_range:
				continue
			var ndiff: Vector3 = diff.normalized()
			var dot: float = dir.dot(ndiff)
			# Only enemies roughly in front (cone of ~100 degrees)
			if dot > 0.35:
				var score: float = dot * (1.0 - (dist / max_range) * 0.4)
				if score > best_score:
					best_score = score
					best_enemy = node_3d

	return best_enemy


func _find_hookable_ground_in_direction(dir: Vector3, max_range: float) -> Variant:
	# Raymarch outward along dir looking for painted ground
	var step := 0.6
	var d := 1.2
	var best_point: Variant = null

	while d <= max_range:
		var check_pos := global_position + dir * d
		check_pos.y = 0.0
		if is_ground_hookable_at(check_pos):
			best_point = check_pos
		elif best_point != null:
			# Found painted ground previously; stop at edge or keep point
			break
		d += step

	return best_point


func _start_hook(target_pos: Vector3, target_node: Variant) -> void:
	is_hooking = true
	_can_hook = false
	_hook_target_pos = target_pos
	_hook_target_node = target_node

	# Interrupt active attack
	if is_attacking:
		is_attacking = false
		if _slash_tween:
			_slash_tween.kill()
		if slash_pivot:
			slash_pivot.visible = false
		attack_finished.emit()

	# Clear movement inputs
	target_destination = null
	external_input = Vector2.ZERO

	# Face towards hook target
	var face_dir := _hook_target_pos - global_position
	face_dir.y = 0.0
	if face_dir.length_squared() > 0.001:
		var look_basis := Basis.looking_at(face_dir.normalized(), Vector3.UP)
		basis = look_basis.orthonormalized()

	hook_started.emit(target_pos, target_node)
	_play_hook_start_feedback()
	_update_hook_rope()


func _finish_hook() -> void:
	if not is_hooking:
		return

	is_hooking = false
	var final_dir := _hook_target_pos - global_position
	final_dir.y = 0.0

	# Hide hook rope
	if _hook_line_mesh:
		_hook_line_mesh.clear_surfaces()
	if _hook_line_instance:
		_hook_line_instance.visible = false

	# Apply slight finish momentum impulse forward
	if final_dir.length_squared() > 0.01:
		velocity.x = final_dir.normalized().x * hook_finish_boost
		velocity.z = final_dir.normalized().z * hook_finish_boost
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	_hook_target_node = null
	hook_finished.emit()

	# Cooldown timer
	get_tree().create_timer(hook_cooldown).timeout.connect(func():
		_can_hook = true
	)


func _setup_hook_visual() -> void:
	if not _hook_line_instance:
		_hook_line_mesh = ImmediateMesh.new()
		_hook_line_instance = MeshInstance3D.new()
		_hook_line_instance.mesh = _hook_line_mesh
		_hook_line_instance.top_level = true # Render in global coordinates

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.2, 0.9, 1.0, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.9, 1.0)
		mat.emission_energy_multiplier = 2.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_hook_line_instance.material_override = mat
		_hook_line_instance.visible = false
		add_child(_hook_line_instance)


func _update_hook_rope() -> void:
	if not is_hooking or not _hook_line_mesh or not _hook_line_instance:
		return

	var start_pos := global_position + Vector3(0.0, 0.9, 0.0)
	var end_pos := _hook_target_pos
	if is_instance_valid(_hook_target_node):
		end_pos = _hook_target_node.global_position + Vector3(0.0, 0.8, 0.0)
		_hook_target_pos = _hook_target_node.global_position

	_hook_line_instance.visible = true
	_hook_line_mesh.clear_surfaces()
	_hook_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_hook_line_mesh.surface_add_vertex(start_pos)
	_hook_line_mesh.surface_add_vertex(end_pos)
	_hook_line_mesh.surface_end()


func _play_hook_start_feedback() -> void:
	if visor and _visor_material:
		var orig_color: Color = _visor_material.albedo_color
		var tween := create_tween()
		tween.tween_property(_visor_material, "albedo_color", Color(0.2, 0.9, 1.0), 0.06)
		tween.tween_property(_visor_material, "albedo_color", orig_color, 0.15)


func _play_hook_fail_feedback() -> void:
	if visor and _visor_material:
		var orig_color: Color = _visor_material.albedo_color
		var tween := create_tween()
		tween.tween_property(_visor_material, "albedo_color", Color(0.9, 0.2, 0.2), 0.06)
		tween.tween_property(_visor_material, "albedo_color", orig_color, 0.12)


func _play_throw_feedback() -> void:
	if visor and _visor_material:
		var orig_color: Color = _visor_material.albedo_color
		var tween := create_tween()
		tween.tween_property(_visor_material, "albedo_color", Color(0.25, 0.95, 0.4), 0.08)
		tween.tween_property(_visor_material, "albedo_color", orig_color, 0.12)


func _play_dodge_feedback() -> void:
	if visor and _visor_material:
		var orig_color: Color = _visor_material.albedo_color
		var tween := create_tween()
		tween.tween_property(_visor_material, "albedo_color", Color(1.0, 0.9, 0.2), 0.06)
		tween.tween_property(_visor_material, "albedo_color", orig_color, dodge_duration - 0.06)

	var body_mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if body_mesh:
		var mesh_tween := create_tween()
		mesh_tween.tween_property(body_mesh, "scale", Vector3(0.9, 0.75, 1.15), dodge_duration * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		mesh_tween.tween_property(body_mesh, "scale", Vector3.ONE, dodge_duration * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _determine_dodge_direction(requested_dir: Vector3 = Vector3.ZERO) -> Vector3:
	if requested_dir.length_squared() > 0.001:
		requested_dir.y = 0.0
		return requested_dir.normalized()

	# Movement input vector (keyboard or external)
	var input_vec := external_input
	if input_vec.is_zero_approx() and enable_keyboard_fallback:
		input_vec = _read_keyboard_input()

	if not input_vec.is_zero_approx():
		var dir := Vector3(input_vec.x, 0.0, input_vec.y)
		return dir.normalized()

	# Target destination if actively walking to a point
	if target_destination != null:
		var diff: Vector3 = target_destination - global_position
		diff.y = 0.0
		if diff.length_squared() > 0.01:
			return diff.normalized()

	# Current horizontal velocity direction if moving
	var horiz_vel := Vector3(velocity.x, 0.0, velocity.z)
	if horiz_vel.length_squared() > 0.1:
		return horiz_vel.normalized()

	# Fallback to player facing direction
	var facing := -basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.001:
		return facing.normalized()

	return Vector3.FORWARD


# ==============================================================================
# Attack Execution & Hit Detection
# ==============================================================================

func _execute_slash() -> void:
	# 1. Forward lunge impulse
	var forward_dir := -basis.z
	velocity += forward_dir * attack_lunge_speed

	# 2. Animate visual slash arc
	_play_slash_animation()

	# 3. Check hitbox overlap for hits
	_check_slash_hits()

	# 4. Paint slash mark onto the ground shader mask map
	_paint_ground_slash(forward_dir)

	# 5. Attack duration timer
	get_tree().create_timer(attack_duration).timeout.connect(func():
		is_attacking = false
		attack_finished.emit()
	)

	# 6. Cooldown timer
	get_tree().create_timer(attack_cooldown).timeout.connect(func():
		_can_attack = true
	)


func _check_slash_hits() -> void:
	if not slash_hitbox:
		return

	# Query overlapping bodies and areas
	var hit_targets: Array[Node3D] = []

	for body in slash_hitbox.get_overlapping_bodies():
		if body == self or hit_targets.has(body):
			continue
		hit_targets.append(body)
		_apply_hit_to_target(body)

	for area in slash_hitbox.get_overlapping_areas():
		if area == slash_hitbox or hit_targets.has(area):
			continue
		hit_targets.append(area)
		_apply_hit_to_target(area)


func _apply_hit_to_target(target: Node3D) -> void:
	attack_hit.emit(target)
	if target.has_method("take_damage"):
		target.take_damage(attack_damage, self)


func _setup_slash_visual() -> void:
	if slash_pivot:
		slash_pivot.visible = false

	if slash_mesh:
		# Create bigger curved crescent mesh based on exported dimensions
		slash_mesh.mesh = _create_crescent_arc_mesh(slash_inner_radius, slash_outer_radius, slash_arc_degrees, 24)

		# Glowing translucent material
		_slash_material = StandardMaterial3D.new()
		_slash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_slash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_slash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_slash_material.albedo_color = Color(0.3, 0.85, 1.0, 0.9)
		slash_mesh.material_override = _slash_material


func _play_slash_animation() -> void:
	if not slash_pivot or not slash_mesh or not _slash_material:
		return

	if _slash_tween:
		_slash_tween.kill()

	slash_pivot.visible = true
	slash_pivot.rotation.y = deg_to_rad(-65.0)
	slash_pivot.scale = Vector3(0.75, 1.0, 0.75)
	_slash_material.albedo_color.a = 0.95

	_slash_tween = create_tween().set_parallel(true)
	_slash_tween.tween_property(slash_pivot, "rotation:y", deg_to_rad(65.0), attack_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slash_tween.tween_property(slash_pivot, "scale", Vector3(1.25, 1.0, 1.25), attack_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_slash_tween.tween_property(_slash_material, "albedo_color:a", 0.0, attack_duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	_slash_tween.chain().tween_callback(func():
		slash_pivot.visible = false
	)


func _create_crescent_arc_mesh(inner_r: float, outer_r: float, arc_deg: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_arc := deg_to_rad(arc_deg * 0.5)
	for i in range(segments):
		var t0 := float(i) / float(segments)
		var t1 := float(i + 1) / float(segments)
		var a0 := lerpf(-half_arc, half_arc, t0)
		var a1 := lerpf(-half_arc, half_arc, t1)

		# Taper ends to points for a blade look
		var taper0 := sin(t0 * PI)
		var taper1 := sin(t1 * PI)
		var cur_outer0 := inner_r + (outer_r - inner_r) * taper0
		var cur_outer1 := inner_r + (outer_r - inner_r) * taper1

		var p0_in := Vector3(sin(a0) * inner_r, 0.0, -cos(a0) * inner_r)
		var p0_out := Vector3(sin(a0) * cur_outer0, 0.0, -cos(a0) * cur_outer0)
		var p1_in := Vector3(sin(a1) * inner_r, 0.0, -cos(a1) * inner_r)
		var p1_out := Vector3(sin(a1) * cur_outer1, 0.0, -cos(a1) * cur_outer1)

		st.set_normal(Vector3.UP)
		st.add_vertex(p0_in)
		st.set_normal(Vector3.UP)
		st.add_vertex(p0_out)
		st.set_normal(Vector3.UP)
		st.add_vertex(p1_out)

		st.set_normal(Vector3.UP)
		st.add_vertex(p0_in)
		st.set_normal(Vector3.UP)
		st.add_vertex(p1_out)
		st.set_normal(Vector3.UP)
		st.add_vertex(p1_in)

	return st.commit()


# ==============================================================================
# Ground Interaction & Mask Querying
# ==============================================================================

func _find_ground() -> void:
	if ground:
		return
	ground = get_tree().get_first_node_in_group("ground")
	if not ground and get_parent():
		ground = get_parent().get_node_or_null("Ground")


func _paint_ground_slash(forward_dir: Vector3) -> void:
	if not enable_ground_creation:
		return
	if not ground:
		_find_ground()
	if ground and ground.has_method("paint_slash"):
		# Center slash arc slightly forward so it sweeps on the ground directly under the blade
		var slash_center := global_position + forward_dir * 0.5
		ground.paint_slash(slash_center, forward_dir, slash_inner_radius * 0.7, slash_outer_radius * 1.25, slash_arc_degrees)


func _setup_visor_visual() -> void:
	if visor:
		_visor_material = StandardMaterial3D.new()
		_visor_material.albedo_color = Color(0.1, 0.15, 0.25, 1.0)
		_visor_material.metallic = 0.5
		_visor_material.roughness = 0.2
		visor.material_override = _visor_material


## Returns true if the player is currently standing on boosted (slashed) ground
func is_boosted() -> bool:
	return is_on_slash_ground


## Returns current maximum horizontal speed factoring in ground speed boost
func get_effective_max_speed() -> float:
	return speed * (1.0 + (ground_boost_multiplier - 1.0) * current_boost_factor)


# ==============================================================================
# Physics Processing
# ==============================================================================

func _physics_process(delta: float) -> void:
	# 1. Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# 2. Query Ground Mask for Speed Boost
	if not ground:
		_find_ground()

	var mask_val := 0.0
	var ground_type := 0
	if ground:
		if ground.has_method("is_boosted_at"):
			mask_val = 1.0 if ground.is_boosted_at(global_position) else 0.0
		elif ground.has_method("get_mask_value"):
			mask_val = ground.get_mask_value(global_position)

		if ground.has_method("get_ground_type_at"):
			ground_type = ground.get_ground_type_at(global_position)

	var prev_boosted := is_on_slash_ground
	is_on_slash_ground = mask_val > 0.05
	current_boost_factor = mask_val

	if prev_boosted != is_on_slash_ground:
		boosted_status_changed.emit(is_on_slash_ground, mask_val)

	# Visor glowing visual feedback matching ground color:
	# Green on permanent connected ground, Cyan/Blue on fading blue slash!
	if _visor_material:
		if is_on_slash_ground:
			_visor_material.emission_enabled = true
			if ground_type == 2:
				_visor_material.emission = Color(0.15, 0.95, 0.35) # Green
			else:
				_visor_material.emission = Color(0.12, 0.82, 1.0)  # Cyan/Blue
			_visor_material.emission_energy_multiplier = lerpf(0.8, 2.5, mask_val)
		else:
			_visor_material.emission_enabled = false

	# 3. Determine horizontal movement direction
	var move_direction := Vector3.ZERO

	if target_destination != null:
		# Destination-based movement
		var diff: Vector3 = target_destination - global_position
		diff.y = 0.0 # Stay on plane
		var dist := diff.length()

		if dist <= destination_arrival_threshold:
			target_destination = null
			destination_reached.emit()
		else:
			move_direction = diff.normalized()
	else:
		# Vector-based movement
		var input_vec := external_input

		# Fallback to keyboard input if enabled and external input is zero
		if input_vec.is_zero_approx() and enable_keyboard_fallback:
			input_vec = _read_keyboard_input()

		if not input_vec.is_zero_approx():
			input_vec = input_vec.limit_length(1.0)
			# Convert 2D input (X: right, Y: down/forward) to 3D world direction on XZ plane
			move_direction = Vector3(input_vec.x, 0.0, input_vec.y).normalized()

	# 4. Calculate horizontal velocity with boosted speed & acceleration
	var effective_speed := speed * (1.0 + (ground_boost_multiplier - 1.0) * mask_val)
	var effective_accel := acceleration * (1.0 + (ground_boost_accel_multiplier - 1.0) * mask_val)

	var horizontal_vel := Vector3(velocity.x, 0.0, velocity.z)
	var target_vel := move_direction * effective_speed
	var should_finish_dodge_this_frame := false
	var should_finish_hook_this_frame := false

	if is_hooking:
		# Update target position if tracking a living enemy
		if is_instance_valid(_hook_target_node):
			_hook_target_pos = _hook_target_node.global_position

		var to_target := _hook_target_pos - global_position
		to_target.y = 0.0
		var dist_to_target := to_target.length()

		if dist_to_target <= hook_arrival_threshold:
			should_finish_hook_this_frame = true
			horizontal_vel = Vector3.ZERO
		else:
			var pull_dir := to_target.normalized()
			var step_dist := hook_pull_speed * delta
			if step_dist >= dist_to_target:
				# Target reached in this step
				horizontal_vel = pull_dir * (dist_to_target / maxf(delta, 0.0001))
				should_finish_hook_this_frame = true
			else:
				horizontal_vel = pull_dir * hook_pull_speed
				# Keep facing hook destination
				var look_basis := Basis.looking_at(pull_dir, Vector3.UP)
				basis = basis.slerp(look_basis, rotation_speed * 1.5 * delta).orthonormalized()
				_update_hook_rope()
	elif is_dodging:
		var step_dist := _current_dodge_speed * delta
		var remaining_dist := _dodge_distance_target - _dodge_distance_traveled
		if step_dist >= remaining_dist:
			# Final physics step: travel the exact remaining distance to hit target distance
			var final_speed := remaining_dist / maxf(delta, 0.0001)
			horizontal_vel = _dodge_direction * final_speed
			_dodge_distance_traveled = _dodge_distance_target
			should_finish_dodge_this_frame = true
		else:
			horizontal_vel = _dodge_direction * _current_dodge_speed
			_dodge_distance_traveled += step_dist
	elif move_direction.length_squared() > 0.001:
		horizontal_vel = horizontal_vel.move_toward(target_vel, effective_accel * delta)
		# Smoothly rotate to face movement direction if not currently mid-slash
		if not is_attacking:
			var look_basis := Basis.looking_at(move_direction, Vector3.UP)
			basis = basis.slerp(look_basis, rotation_speed * delta).orthonormalized()
	else:
		horizontal_vel = horizontal_vel.move_toward(Vector3.ZERO, friction * delta)

	velocity.x = horizontal_vel.x
	velocity.z = horizontal_vel.z

	# 5. Perform movement
	var prev_pos := global_position
	move_and_slide()

	# If dodge reached its target distance this frame, finish immediately (stops slipping)
	if should_finish_dodge_this_frame:
		_finish_dodge()

	# If hook reached target this frame or post-move, finish hook
	if is_hooking:
		var post_to_target := _hook_target_pos - global_position
		post_to_target.y = 0.0
		if should_finish_hook_this_frame or post_to_target.length() <= hook_arrival_threshold + 0.6:
			_finish_hook()

	# 6. Emit position change if moved
	if global_position != prev_pos:
		position_changed.emit(global_position)


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard shortcuts fallback: Space = Dodge, F/J = Slash, E/Q = Grenade, R/Shift = Grapple
	if enable_keyboard_fallback and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			dodge()
		elif event.keycode == KEY_F or event.keycode == KEY_J:
			slash()
		elif event.keycode == KEY_E or event.keycode == KEY_Q:
			throw_grenade()
		elif event.keycode == KEY_R or event.keycode == KEY_SHIFT:
			grapple_hook()


func _read_keyboard_input() -> Vector2:
	var vec := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		vec.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		vec.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		vec.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		vec.x += 1.0
	return vec.normalized()