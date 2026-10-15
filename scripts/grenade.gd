class_name Grenade
extends Area3D

signal exploded(explosion_pos: Vector3)

@export_group("Blast Settings")
## Radius of the grass circle created on detonation
@export var blast_radius: float = 4.0
## Damage dealt to damageable targets in blast radius
@export var blast_damage: float = 50.0
## Duration for the circle to expand from the center outward (seconds)
@export var grow_duration: float = 0.35
## Forward throw speed
@export var forward_speed: float = 12.0
## Upward launch speed for arcing trajectory
@export var upward_speed: float = 5.5
## Downward gravity acceleration
@export var throw_gravity: float = 20.0
## Maximum flight time before automatic detonation (seconds)
@export var max_fuse_time: float = 2.0

var velocity: Vector3 = Vector3.ZERO
var ground: Ground = null
var thrower: Node3D = null

var _is_exploding: bool = false
var _fuse_timer: float = 0.0
var _tumble_axis: Vector3 = Vector3.RIGHT
var _tumble_speed: float = 14.0

@onready var grenade_mesh: Node3D = get_node_or_null("GrenadeVisual")
@onready var trail_particles: CPUParticles3D = get_node_or_null("TrailParticles")
@onready var explosion_holder: Node3D = get_node_or_null("ExplosionEffect")
@onready var shockwave_mesh: MeshInstance3D = get_node_or_null("ExplosionEffect/ShockwaveRing")
@onready var burst_particles: CPUParticles3D = get_node_or_null("ExplosionEffect/BurstParticles")
@onready var explosion_light: OmniLight3D = get_node_or_null("ExplosionEffect/ExplosionLight")


func _ready() -> void:
	if explosion_holder:
		explosion_holder.visible = false
	if not ground:
		_find_ground()


## Launch the grenade in the specified horizontal direction.
func launch(direction: Vector3, custom_forward_speed: float = -1.0, custom_upward_speed: float = -1.0) -> void:
	var f_spd := custom_forward_speed if custom_forward_speed > 0.0 else forward_speed
	var u_spd := custom_upward_speed if custom_upward_speed > 0.0 else upward_speed

	var horiz_dir := Vector3(direction.x, 0.0, direction.z).normalized()
	if horiz_dir.is_zero_approx():
		horiz_dir = Vector3(0.0, 0.0, -1.0)

	velocity = horiz_dir * f_spd + Vector3.UP * u_spd

	# Choose tumble axis perpendicular to throw direction
	var side := horiz_dir.cross(Vector3.UP).normalized()
	_tumble_axis = side.rotated(horiz_dir, randf_range(-0.4, 0.4)).normalized()


## Launch the grenade so it lands exactly at target_pos using a ballistic arc.
## Solves for the required horizontal speed given the fixed upward_speed and throw_gravity.
func launch_to_target(target_pos: Vector3) -> void:
	var spawn_pos := global_position
	var diff := Vector3(target_pos.x - spawn_pos.x, 0.0, target_pos.z - spawn_pos.z)
	var horiz_dist := diff.length()

	var horiz_dir := diff.normalized() if horiz_dist > 0.05 else Vector3(0.0, 0.0, -1.0)

	# Ballistic time-of-flight: solve y(t) = spawn_y + u*t - 0.5*g*t^2 = 0 (ground plane)
	# => t = (u + sqrt(u^2 + 2*g*spawn_y)) / g
	var u := upward_speed
	var g := throw_gravity
	var spawn_y := spawn_pos.y  # height above ground (ground is y=0)
	var discriminant := u * u + 2.0 * g * spawn_y
	var flight_time: float
	if discriminant >= 0.0:
		flight_time = (u + sqrt(discriminant)) / g
	else:
		# Fallback: symmetric arc time
		flight_time = 2.0 * u / g

	# Clamp so grenade doesn't overshoot the fuse time
	flight_time = minf(flight_time, max_fuse_time * 0.95)

	var h_speed := horiz_dist / maxf(flight_time, 0.001)
	velocity = horiz_dir * h_speed + Vector3.UP * u

	# Choose tumble axis perpendicular to throw direction
	var side := horiz_dir.cross(Vector3.UP).normalized()
	_tumble_axis = side.rotated(horiz_dir, randf_range(-0.4, 0.4)).normalized()


func _physics_process(delta: float) -> void:
	if _is_exploding:
		return

	_fuse_timer += delta
	if _fuse_timer >= max_fuse_time:
		explode()
		return

	velocity.y -= throw_gravity * delta
	var motion := velocity * delta

	# Continuous collision raycast along motion vector
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + motion)
	var excludes: Array[RID] = [get_rid()]
	if thrower:
		excludes.append(thrower.get_rid())
	query.exclude = excludes

	var hit := space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		explode()
		return

	global_position += motion

	# Ground level collision check (top of ground plane is at y = 0.0)
	if global_position.y <= 0.08 and velocity.y < 0.0:
		global_position.y = 0.05
		explode()
		return

	# Tumble visual in flight
	if grenade_mesh:
		grenade_mesh.rotate(_tumble_axis, _tumble_speed * delta)


## Detonate the grenade: plays explosion, deals damage, and creates expanding grass circle on ground.
func explode() -> void:
	if _is_exploding:
		return
	_is_exploding = true
	velocity = Vector3.ZERO

	var explosion_pos := Vector3(global_position.x, 0.0, global_position.z)
	exploded.emit(explosion_pos)

	# 1. Hide the flying grenade visual & stop flight trail
	if grenade_mesh:
		grenade_mesh.visible = false
	if trail_particles:
		trail_particles.emitting = false

	# 2. Paint growing circle of grass on the ground shader
	if not ground:
		_find_ground()

	if ground:
		if ground.has_method("paint_expanding_circle"):
			ground.paint_expanding_circle(explosion_pos, blast_radius, grow_duration)
		elif ground.has_method("paint_circle"):
			ground.paint_circle(explosion_pos, blast_radius)

	# 3. Apply explosion damage to nearby targets
	_apply_damage(explosion_pos)

	# 4. Spawn and play visual explosion effects
	_play_explosion_effects(explosion_pos)


func _find_ground() -> void:
	ground = get_tree().get_first_node_in_group("ground") as Ground
	if not ground and get_parent():
		ground = get_parent().get_node_or_null("Ground") as Ground


func _apply_damage(explosion_pos: Vector3) -> void:
	var hit_targets: Array[Node3D] = []

	# Check all damageable nodes in scene
	for node in get_tree().get_nodes_in_group("damageable"):
		if node is Node3D and node != thrower and not hit_targets.has(node):
			var node3d := node as Node3D
			var diff: Vector3 = node3d.global_position - explosion_pos
			diff.y = 0.0
			if diff.length() <= blast_radius:
				hit_targets.append(node)
				if node.has_method("take_damage"):
					node.take_damage(blast_damage, self)

	# Also check overlapping bodies
	for body in get_overlapping_bodies():
		if body is Node3D and body != thrower and not hit_targets.has(body):
			var diff: Vector3 = body.global_position - explosion_pos
			diff.y = 0.0
			if diff.length() <= blast_radius:
				hit_targets.append(body)
				if body.has_method("take_damage"):
					body.take_damage(blast_damage, self)


func _play_explosion_effects(explosion_pos: Vector3) -> void:
	if not explosion_holder:
		get_tree().create_timer(grow_duration + 0.1).timeout.connect(queue_free)
		return

	explosion_holder.visible = true
	explosion_holder.global_position = Vector3(explosion_pos.x, 0.05, explosion_pos.z)

	var tween := create_tween().set_parallel(true)

	# 1. Shockwave ring expanding from center out in sync with ground grass growth
	if shockwave_mesh:
		shockwave_mesh.visible = true
		shockwave_mesh.scale = Vector3(0.1, 1.0, 0.1)
		var mat := shockwave_mesh.material_override as StandardMaterial3D
		if not mat:
			mat = StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.albedo_color = Color(0.25, 0.95, 0.4, 0.85)
			shockwave_mesh.material_override = mat

		mat.albedo_color.a = 0.85
		tween.tween_property(shockwave_mesh, "scale", Vector3(blast_radius, 1.0, blast_radius), grow_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(mat, "albedo_color:a", 0.0, grow_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 2. Burst particles
	if burst_particles:
		burst_particles.restart()
		burst_particles.emitting = true

	# 3. Flash light
	if explosion_light:
		explosion_light.light_energy = 3.5
		tween.tween_property(explosion_light, "light_energy", 0.0, grow_duration * 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Clean up after all particles and effects finish
	tween.chain().tween_callback(func():
		var delay := 0.4
		if burst_particles:
			delay = maxf(delay, burst_particles.lifetime)
		get_tree().create_timer(delay).timeout.connect(queue_free)
	)
