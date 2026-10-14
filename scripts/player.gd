class_name Player
extends CharacterBody3D

## Signals for external systems
signal position_changed(new_pos: Vector3)
signal destination_reached()
signal attack_started()
signal attack_finished()
signal attack_hit(target: Node3D)
signal boosted_status_changed(is_boosted: bool, factor: float)

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

@export_group("External Control")
## If true, reads default keyboard (WASD / Arrows / F / J) when external input is zero.
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
	_setup_slash_visual()
	_setup_visor_visual()
	_find_ground()


# ==============================================================================
# Public API (Outside Control)
# ==============================================================================

## Execute a slash attack.
## If target_direction is provided, the player orients towards it before slashing.
## Returns true if the attack successfully initiated.
func slash(target_direction: Vector3 = Vector3.ZERO) -> bool:
	if not _can_attack or is_attacking:
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
	velocity.x = 0.0
	velocity.z = 0.0


## Instantly teleport the player to a target location.
func teleport(target_pos: Vector3) -> void:
	stop()
	global_position = target_pos
	position_changed.emit(global_position)


## Returns current horizontal velocity magnitude.
func get_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Returns true if the player is currently moving.
func is_moving() -> bool:
	return get_speed() > 0.05


## Returns true if the player is currently able to perform an attack.
func can_attack() -> bool:
	return _can_attack and not is_attacking


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

	if move_direction.length_squared() > 0.001:
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

	# 6. Emit position change if moved
	if global_position != prev_pos:
		position_changed.emit(global_position)


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard attack shortcut fallback (F or J)
	if enable_keyboard_fallback and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F or event.keycode == KEY_J:
			slash()


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