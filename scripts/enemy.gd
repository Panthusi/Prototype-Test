class_name Enemy
extends CharacterBody3D

signal health_changed(current: float, max_health: float)
signal died()
signal revived()
signal attack_charged()
signal attack_hit(target: Node3D)

enum State {
	IDLE,
	CHASE,
	CHARGE_UP,
	ATTACK_SWING,
	RECOVERY,
	DEAD
}

@export_group("Stats (Tanky Enemy)")
## Maximum health points. Default 160.0 makes the enemy tankier than the player (100 HP)
@export var max_health: float = 160.0:
	set(val):
		max_health = maxf(val, 1.0)
		current_health = minf(current_health, max_health)
## Current health points
@export var current_health: float = 160.0:
	set(val):
		current_health = clampf(val, 0.0, max_health)

@export_group("Revive Testing")
## When enabled, automatically revives the enemy after 5 seconds for testing
@export var revive_after_death: bool = true
## Delay before reviving (seconds)
@export var revive_delay: float = 5.0

@export_group("Movement")
## Base movement speed when chasing the player
@export var move_speed: float = 3.6
## Turn speed towards target
@export var rotation_speed: float = 7.0
## Downward gravity acceleration
@export var gravity: float = 20.0
## Distance threshold to keep from colliding directly into player
@export var stop_distance: float = 1.4

@export_group("Ground Destruction")
## Radius of player ground color erased around feet when stepping on it
@export var step_erase_radius: float = 1.0
## Radius of ground destroyed when the sword attack strikes
@export var attack_ground_erase_radius: float = 3.2

@export_group("Attack Settings")
## Distance to player at which charge-up begins
@export var attack_range: float = 2.8
## Charge-up wind-up duration before the sword strikes (seconds)
@export var charge_duration: float = 0.8
## Duration of the sword swing animation (seconds)
@export var swing_duration: float = 0.22
## Cooldown delay after attack before moving/attacking again (seconds)
@export var attack_cooldown: float = 1.0
## Damage dealt to player on sword hit
@export var attack_damage: float = 25.0
## Forward lunge momentum impulse during strike
@export var attack_lunge_speed: float = 3.2

var current_state: State = State.CHASE
var player: Player = null
var ground: Ground = null

var _can_attack: bool = true
var _charge_timer: float = 0.0
var _hurt_tween: Tween
var _orig_scale: Vector3 = Vector3.ONE

@onready var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
@onready var body_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
@onready var visor_mesh: MeshInstance3D = get_node_or_null("Visor")
@onready var sword_pivot: Node3D = get_node_or_null("SwordPivot")
@onready var sword_mesh: MeshInstance3D = get_node_or_null("SwordPivot/SwordMesh")
@onready var slash_pivot: Node3D = get_node_or_null("SlashPivot")
@onready var slash_mesh: MeshInstance3D = get_node_or_null("SlashPivot/SlashMesh")
@onready var charge_indicator: MeshInstance3D = get_node_or_null("ChargeIndicator")
@onready var health_bar: HealthBar3D = get_node_or_null("HealthBar3D")

var _slash_material: StandardMaterial3D
var _slash_tween: Tween
var _charge_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("enemy")

	if body_mesh:
		_orig_scale = body_mesh.scale
	current_health = max_health

	_setup_materials_and_meshes()
	_find_references()

	if health_bar:
		health_bar.fill_color = Color(0.95, 0.2, 0.2, 1.0)
		health_bar.label_text = "Enemy"
		health_bar.update_health(current_health, max_health)


func _find_references() -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player") as Player
	if not ground:
		ground = get_tree().get_first_node_in_group("ground") as Ground


func _setup_materials_and_meshes() -> void:
	# 1. Red crescent slash mesh & material
	if slash_mesh:
		slash_mesh.mesh = _create_crescent_arc_mesh(0.8, 3.2, 140.0, 24)
		_slash_material = StandardMaterial3D.new()
		_slash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_slash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_slash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_slash_material.albedo_color = Color(1.0, 0.25, 0.1, 0.95)
		slash_mesh.material_override = _slash_material
	if slash_pivot:
		slash_pivot.visible = false

	# 2. Charge indicator ground circle/ring
	if charge_indicator:
		charge_indicator.visible = false
		_charge_material = StandardMaterial3D.new()
		_charge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_charge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_charge_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_charge_material.albedo_color = Color(1.0, 0.2, 0.1, 0.0)
		charge_indicator.material_override = _charge_material


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if not player or not ground:
		_find_references()

	match current_state:
		State.CHASE:
			_process_chase(delta)
		State.CHARGE_UP:
			_process_charge_up(delta)
		State.ATTACK_SWING:
			_process_attack_swing(delta)
		State.RECOVERY:
			_process_recovery(delta)

	move_and_slide()

	# Stepping over player color destroys it
	if current_state != State.DEAD:
		_erase_ground_under_feet()


# ==============================================================================
# Ground Interaction
# ==============================================================================

## Erase painted color under the enemy's feet when moving over it
func _erase_ground_under_feet() -> void:
	if not ground:
		return
	if ground.has_method("erase_circle"):
		ground.erase_circle(global_position, step_erase_radius)


# ==============================================================================
# State Machine & Movement
# ==============================================================================

func _process_chase(delta: float) -> void:
	if not player:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var diff: Vector3 = player.global_position - global_position
	diff.y = 0.0
	var dist := diff.length()

	# In attack range and attack is ready -> start charge up!
	if dist <= attack_range and _can_attack:
		_start_charge_up()
		return

	# Face towards player
	if diff.length_squared() > 0.01:
		var look_dir := diff.normalized()
		var target_basis := Basis.looking_at(look_dir, Vector3.UP).orthonormalized()
		basis = basis.orthonormalized().slerp(target_basis, rotation_speed * delta).orthonormalized()

	# Move towards player
	if dist > stop_distance:
		var move_dir := diff.normalized()
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * 4.0 * delta)


func _start_charge_up() -> void:
	current_state = State.CHARGE_UP
	_can_attack = false
	velocity.x = 0.0
	velocity.z = 0.0

	# Face directly towards player when initiating charge
	if player:
		var fwd := (player.global_position - global_position)
		fwd.y = 0.0
		if fwd.length_squared() > 0.01:
			basis = Basis.looking_at(fwd.normalized(), Vector3.UP).orthonormalized()

	# 1. Raise / wind back sword into charging stance
	if sword_pivot:
		var wind_tween := create_tween()
		wind_tween.tween_property(sword_pivot, "rotation:x", deg_to_rad(-45.0), charge_duration * 0.5)
		wind_tween.parallel().tween_property(sword_pivot, "rotation:y", deg_to_rad(-60.0), charge_duration * 0.5)

	# 2. Show glowing charge indicator on ground & visor charge glow
	if charge_indicator and _charge_material:
		charge_indicator.visible = true
		charge_indicator.scale = Vector3(0.2, 1.0, 0.2)
		_charge_material.albedo_color = Color(1.0, 0.2, 0.1, 0.1)

		var ind_tween := create_tween().set_parallel(true)
		ind_tween.tween_property(charge_indicator, "scale", Vector3(attack_range * 1.1, 1.0, attack_range * 1.1), charge_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ind_tween.tween_property(_charge_material, "albedo_color:a", 0.75, charge_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# 3. Visor pulsating warning glow
	if visor_mesh:
		var visor_mat := visor_mesh.material_override as StandardMaterial3D
		if visor_mat:
			var orig_energy := visor_mat.emission_energy_multiplier
			var vis_tween := create_tween()
			vis_tween.tween_property(visor_mat, "emission_energy_multiplier", 4.0, charge_duration * 0.5)
			vis_tween.tween_property(visor_mat, "emission_energy_multiplier", orig_energy, charge_duration * 0.5)

	# 4. Timer to trigger the actual attack swing
	get_tree().create_timer(charge_duration).timeout.connect(func():
		if current_state == State.CHARGE_UP:
			_execute_sword_attack()
	)


func _process_charge_up(delta: float) -> void:
	# Decelerate to dead stop during charge
	velocity.x = move_toward(velocity.x, 0.0, 15.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 15.0 * delta)

	# Track player slightly during early wind-up
	if player:
		var diff: Vector3 = player.global_position - global_position
		diff.y = 0.0
		if diff.length_squared() > 0.01:
			var target_basis := Basis.looking_at(diff.normalized(), Vector3.UP).orthonormalized()
			basis = basis.orthonormalized().slerp(target_basis, (rotation_speed * 0.4) * delta).orthonormalized()


# ==============================================================================
# Attack Execution & Ground Destruction
# ==============================================================================

func _execute_sword_attack() -> void:
	current_state = State.ATTACK_SWING
	attack_charged.emit()

	# Hide charge indicator
	if charge_indicator:
		charge_indicator.visible = false

	var forward_dir := -basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()

	# 1. Forward lunge impulse
	velocity += forward_dir * attack_lunge_speed

	# 2. Animate sword forward swing
	if sword_pivot:
		var swing_tween := create_tween()
		swing_tween.tween_property(sword_pivot, "rotation:x", deg_to_rad(45.0), swing_duration * 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		swing_tween.parallel().tween_property(sword_pivot, "rotation:y", deg_to_rad(65.0), swing_duration * 0.6)

	# 3. Animate fiery red slash arc
	_play_slash_animation()

	# 4. Destroy ground where the sword strikes!
	var strike_center := global_position + forward_dir * 1.5
	if ground and ground.has_method("erase_circle"):
		ground.erase_circle(strike_center, attack_ground_erase_radius)

	# 5. Check hit on Player
	_check_attack_hit_on_player(forward_dir)

	# 6. Swing timer -> transition to recovery
	get_tree().create_timer(swing_duration).timeout.connect(func():
		if current_state == State.ATTACK_SWING:
			_enter_recovery()
	)


func _check_attack_hit_on_player(forward_dir: Vector3) -> void:
	if not player:
		return

	var diff: Vector3 = player.global_position - global_position
	diff.y = 0.0
	var dist := diff.length()

	# In strike range
	if dist <= (attack_range + 0.8):
		# Within ~140 degree forward strike cone
		var angle := rad_to_deg(abs(diff.normalized().angle_to(forward_dir)))
		if angle <= 75.0:
			attack_hit.emit(player)
			if player.has_method("take_damage"):
				player.take_damage(attack_damage, self)


func _play_slash_animation() -> void:
	if not slash_pivot or not slash_mesh or not _slash_material:
		return

	if _slash_tween:
		_slash_tween.kill()

	slash_pivot.visible = true
	slash_pivot.rotation.y = deg_to_rad(-70.0)
	slash_pivot.scale = Vector3(0.7, 1.0, 0.7)
	_slash_material.albedo_color.a = 0.95

	_slash_tween = create_tween().set_parallel(true)
	_slash_tween.tween_property(slash_pivot, "rotation:y", deg_to_rad(70.0), swing_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slash_tween.tween_property(slash_pivot, "scale", Vector3(1.3, 1.0, 1.3), swing_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_slash_tween.tween_property(_slash_material, "albedo_color:a", 0.0, swing_duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	_slash_tween.chain().tween_callback(func():
		if slash_pivot:
			slash_pivot.visible = false
	)


func _process_attack_swing(delta: float) -> void:
	# Decelerate lunge
	velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)


func _enter_recovery() -> void:
	current_state = State.RECOVERY

	# Reset sword rotation smoothly
	if sword_pivot:
		var reset_tween := create_tween()
		reset_tween.tween_property(sword_pivot, "rotation", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Recovery cooldown timer
	get_tree().create_timer(attack_cooldown).timeout.connect(func():
		_can_attack = true
		if current_state == State.RECOVERY:
			current_state = State.CHASE
	)


func _process_recovery(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)


# ==============================================================================
# Damage, Death & Revive
# ==============================================================================

## Take damage from player attack, grenades, or hazards
func take_damage(amount: float, _source: Node3D = null) -> void:
	if current_state == State.DEAD:
		return

	current_health = clampf(current_health - amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)

	if health_bar:
		health_bar.update_health(current_health, max_health)

	_play_hurt_feedback()

	if current_health <= 0.0:
		die()


func _play_hurt_feedback() -> void:
	if body_mesh:
		var flash_mat := StandardMaterial3D.new()
		flash_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		flash_mat.emission_enabled = true
		flash_mat.emission = Color(1.0, 0.8, 0.8)
		flash_mat.emission_energy_multiplier = 3.0
		body_mesh.material_override = flash_mat

		var tween := create_tween()
		tween.tween_interval(0.1)
		tween.tween_callback(func():
			if body_mesh:
				body_mesh.material_override = null
		)

	if _hurt_tween:
		_hurt_tween.kill()
	if body_mesh:
		_hurt_tween = create_tween()
		_hurt_tween.tween_property(body_mesh, "scale", _orig_scale * Vector3(1.25, 0.75, 1.25), 0.08)
		_hurt_tween.tween_property(body_mesh, "scale", _orig_scale, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Handle enemy death
func die() -> void:
	if current_state == State.DEAD:
		return

	current_state = State.DEAD
	velocity = Vector3.ZERO
	died.emit()

	# Disable collision so player can pass through
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
		collision_shape.disabled = true

	if charge_indicator:
		charge_indicator.visible = false
	if slash_pivot:
		slash_pivot.visible = false

	# Play collapse / squash death visual
	if body_mesh:
		var death_tween := create_tween()
		death_tween.tween_property(body_mesh, "scale", Vector3(_orig_scale.x * 1.3, 0.05, _orig_scale.z * 1.3), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Check revive setting
	if revive_after_death:
		if health_bar:
			health_bar.update_health(0.0, max_health, "Reviving in 5s...")

		get_tree().create_timer(revive_delay).timeout.connect(func():
			revive()
		)
	else:
		if health_bar:
			health_bar.visible = false


## Revive the enemy to full health and resume chasing
func revive() -> void:
	if current_state != State.DEAD:
		return

	current_health = max_health
	health_changed.emit(current_health, max_health)

	if health_bar:
		health_bar.visible = true
		health_bar.update_health(current_health, max_health, "Enemy")

	# Re-enable collision
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
		collision_shape.disabled = false

	# Revive pop-in animation
	if body_mesh:
		var revive_tween := create_tween()
		revive_tween.tween_property(body_mesh, "scale", _orig_scale, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_can_attack = true
	current_state = State.CHASE
	revived.emit()


# ==============================================================================
# Helpers
# ==============================================================================

func _create_crescent_arc_mesh(inner_r: float, outer_r: float, arc_deg: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_arc := deg_to_rad(arc_deg * 0.5)
	for i in range(segments):
		var t0 := float(i) / float(segments)
		var t1 := float(i + 1) / float(segments)
		var a0 := lerpf(-half_arc, half_arc, t0)
		var a1 := lerpf(-half_arc, half_arc, t1)

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
