class_name MainScene
extends Node3D

@onready var player: Player = $Player
@onready var camera: Camera3D = $Camera3D
@onready var ground: Ground = $Ground
@onready var enemy: Enemy = get_node_or_null("Enemy") as Enemy

@export var camera_offset: Vector3 = Vector3(0, 14, 10)
@export var camera_follow_speed: float = 8.0

var _status_label: Label
var _enemy_status_label: Label
var _player_health_label: Label
var _player_health_bar: ProgressBar
var _help_label: Label


func _ready() -> void:
	if player and camera:
		camera.global_position = player.global_position + camera_offset
		camera.look_at(player.global_position, Vector3.UP)

	if player and ground:
		player.ground = ground

	if not enemy:
		enemy = get_tree().get_first_node_in_group("enemy") as Enemy

	_setup_hud()


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16
	panel.offset_top = 16
	panel.offset_right = 470
	panel.offset_bottom = 190
	canvas.add_child(panel)

	# Margin container for clean padding
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Player Health Bar Row
	var hp_box := HBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 10)
	vbox.add_child(hp_box)

	_player_health_label = Label.new()
	_player_health_label.add_theme_font_size_override("font_size", 14)
	if player:
		_player_health_label.text = "Player HP: %d / %d" % [int(player.current_health), int(player.max_health)]
	else:
		_player_health_label.text = "Player HP: 100 / 100"
	hp_box.add_child(_player_health_label)

	_player_health_bar = ProgressBar.new()
	_player_health_bar.custom_minimum_size = Vector2(170, 16)
	_player_health_bar.show_percentage = false
	if player:
		_player_health_bar.max_value = player.max_health
		_player_health_bar.value = player.current_health

	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.2, 0.85, 0.35, 1.0)
	hp_fill.set_corner_radius_all(4)
	_player_health_bar.add_theme_stylebox_override("fill", hp_fill)

	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.12, 0.15, 0.18, 0.9)
	hp_bg.set_corner_radius_all(4)
	_player_health_bar.add_theme_stylebox_override("background", hp_bg)
	hp_box.add_child(_player_health_bar)

	if player:
		player.health_changed.connect(func(cur: float, max_hp: float):
			if _player_health_bar:
				_player_health_bar.max_value = max_hp
				_player_health_bar.value = cur
			if _player_health_label:
				_player_health_label.text = "Player HP: %d / %d" % [int(cur), int(max_hp)]
		)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_status_label)

	_enemy_status_label = Label.new()
	_enemy_status_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_enemy_status_label)

	_help_label = Label.new()
	_help_label.add_theme_font_size_override("font_size", 12)
	_help_label.text = "Center patch is PERMANENT. Connect grass to center -> GREEN & BOOST!\nEnemy: Follows, destroys color on step/attack, charges sword, revives in 5s\nLMB/F: Slash | Space: Dodge | E/Q: Grenade | WASD: Move | RMB: Move to | T: Textures | C: Clear"
	vbox.add_child(_help_label)


func _process(delta: float) -> void:
	# Smoothly follow the player with the top-down camera
	if player and camera:
		var target_cam_pos := player.global_position + camera_offset
		camera.global_position = camera.global_position.lerp(target_cam_pos, camera_follow_speed * delta)

	_update_hud()


func _update_hud() -> void:
	if not _status_label or not player:
		return

	var spd := player.get_speed()
	var is_boosted := player.is_boosted()
	var creation_str := "ON" if (ground and ground.enable_ground_creation) else "OFF"
	var base_mode := "2 Textures (Active)" if (ground and ground.use_texture_base) else "Colors (Hard Corners)"
	var mode_str := "%s | Ground Creation: %s" % [base_mode, creation_str]

	var ground_type := 0
	if ground and ground.has_method("get_ground_type_at"):
		ground_type = ground.get_ground_type_at(player.global_position)

	if player.is_dodging:
		_status_label.text = "Mode: %s\nSpeed: %.1f m/s  [ DODGING! ]" % [mode_str, spd]
		_status_label.modulate = Color(1.0, 0.9, 0.2)
	elif is_boosted:
		if ground_type == 2:
			_status_label.text = "Mode: %s\nSpeed: %.1f m/s  [ CONNECTED GREEN - PERMANENT BOOST! ]" % [mode_str, spd]
			_status_label.modulate = Color(0.15, 0.95, 0.35)
		else:
			_status_label.text = "Mode: %s\nSpeed: %.1f m/s  [ GRASS BOOST ACTIVE! ]" % [mode_str, spd]
			_status_label.modulate = Color(0.2, 0.85, 0.3)
	else:
		_status_label.text = "Mode: %s\nSpeed: %.1f m/s  (Normal)" % [mode_str, spd]
		_status_label.modulate = Color(0.9, 0.9, 0.9)

	if not enemy:
		enemy = get_tree().get_first_node_in_group("enemy") as Enemy

	if _enemy_status_label and enemy:
		if enemy.current_state == Enemy.State.DEAD:
			_enemy_status_label.text = "Enemy: DEAD (Reviving in %.1fs...)" % [enemy.revive_delay]
			_enemy_status_label.modulate = Color(0.6, 0.6, 0.6)
		elif enemy.current_state == Enemy.State.CHARGE_UP:
			_enemy_status_label.text = "Enemy: [ CHARGING SWORD ATTACK! ]  HP: %d / %d" % [int(enemy.current_health), int(enemy.max_health)]
			_enemy_status_label.modulate = Color(1.0, 0.3, 0.1)
		elif enemy.current_state == Enemy.State.ATTACK_SWING:
			_enemy_status_label.text = "Enemy: [ SWORD SLASH! Ground Cleared! ]  HP: %d / %d" % [int(enemy.current_health), int(enemy.max_health)]
			_enemy_status_label.modulate = Color(1.0, 0.1, 0.1)
		else:
			_enemy_status_label.text = "Enemy: Chasing Player  HP: %d / %d" % [int(enemy.current_health), int(enemy.max_health)]
			_enemy_status_label.modulate = Color(0.95, 0.45, 0.45)


func _unhandled_input(event: InputEvent) -> void:
	if not player or not camera:
		return

	if event is InputEventMouseButton and event.pressed:
		var ground_point = _get_ground_click_position(event.position)
		if ground_point != null:
			if event.button_index == MOUSE_BUTTON_LEFT:
				# External control: Command player to face mouse cursor and slash!
				var slash_direction: Vector3 = ground_point - player.global_position
				slash_direction.y = 0.0
				player.slash(slash_direction)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				# External control: Command player to walk to clicked destination
				player.move_to(ground_point)
			elif event.button_index == MOUSE_BUTTON_MIDDLE:
				# Middle click: Throw grenade towards clicked direction
				var throw_direction: Vector3 = ground_point - player.global_position
				throw_direction.y = 0.0
				player.throw_grenade(throw_direction)

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			player.dodge()
		elif event.keycode == KEY_E or event.keycode == KEY_Q:
			player.throw_grenade()
		elif event.keycode == KEY_T:
			if ground:
				ground.toggle_textures()
		elif event.keycode == KEY_C:
			if ground:
				ground.clear_mask()
		elif event.keycode == KEY_G:
			if ground:
				ground.enable_ground_creation = not ground.enable_ground_creation
				if player:
					player.enable_ground_creation = ground.enable_ground_creation


func _get_ground_click_position(mouse_pos: Vector2) -> Variant:
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = camera.project_ray_normal(mouse_pos)
	var ground_plane := Plane(Vector3.UP, 0.0)
	return ground_plane.intersects_ray(ray_origin, ray_normal)
