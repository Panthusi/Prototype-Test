class_name Ground
extends StaticBody3D

## Signals
signal mask_updated()
signal textures_toggled(enabled: bool)
signal connectivity_changed(connected_cells_count: int)

@export_group("Mask & Grid Settings")
## Resolution of the internal mask map (power of 2: 128, 256, 512)
@export var mask_resolution: int = 256
## World dimensions of the ground plane (XZ size)
@export var ground_size: Vector2 = Vector2(60.0, 60.0)
## Center offset in world XZ
@export var ground_offset: Vector2 = Vector2(0.0, 0.0)
## Size of the permanent center patch with hard corners (XZ meters)
@export var center_patch_size: Vector2 = Vector2(6.0, 6.0)
@export_group("Ground Creation")
## When enabled, slashes and trails are created on the ground. When disabled, ground creation is ignored.
@export var enable_ground_creation: bool = true
## Deprecated / unused: slashes no longer fade or get removed when disconnected
@export var fade_duration: float = 5.0

@export_group("Colors")
## Color 1: Base ground color
@export var color_base: Color = Color(0.24, 0.27, 0.31, 1.0):
	set(val):
		color_base = val
		_update_shader_params()

## Color 2: Unconnected slash color (fades over 5 seconds)
@export var color_slash: Color = Color(0.12, 0.82, 1.0, 1.0):
	set(val):
		color_slash = val
		_update_shader_params()

## Color 3: Connected to center patch (Permanent green & gives speed boost!)
@export var color_connected: Color = Color(0.15, 0.95, 0.35, 1.0):
	set(val):
		color_connected = val
		_update_shader_params()

@export_group("Textures (Optional Swaps)")
## Texture to replace/tint base ground color
@export var texture_base: Texture2D = null:
	set(val):
		texture_base = val
		_update_shader_params()

## Texture to replace/tint slashed/connected ground
@export var texture_slash: Texture2D = null:
	set(val):
		texture_slash = val
		_update_shader_params()

## Enable texturing for base ground instead of pure color
@export var use_texture_base: bool = false:
	set(val):
		use_texture_base = val
		_update_shader_params()

## Enable texturing for slashed/connected ground instead of pure color
@export var use_texture_slash: bool = false:
	set(val):
		use_texture_slash = val
		_update_shader_params()

## UV tiling scale for base texture
@export var uv_scale_base: Vector2 = Vector2(12.0, 12.0):
	set(val):
		uv_scale_base = val
		_update_shader_params()

## UV tiling scale for slash texture
@export var uv_scale_slash: Vector2 = Vector2(12.0, 12.0):
	set(val):
		uv_scale_slash = val
		_update_shader_params()

@export_group("Visual Polish")
@export var slash_emission_energy: float = 1.0:
	set(val):
		slash_emission_energy = val
		_update_shader_params()

@export var connected_emission_energy: float = 1.8:
	set(val):
		connected_emission_energy = val
		_update_shader_params()

@export var base_roughness: float = 0.85:
	set(val):
		base_roughness = val
		_update_shader_params()

@export var slash_roughness: float = 0.25:
	set(val):
		slash_roughness = val
		_update_shader_params()

# Internal mask data
var mask_image: Image
var mask_texture: ImageTexture
var shader_material: ShaderMaterial

# Grid cell state arrays
var _cell_timers: PackedFloat32Array
var _cell_connected: PackedByteArray
var _cell_is_center: PackedByteArray
var _active_cells: Dictionary = {} # Set of non-center cell indices with timer > 0

var _center_pixel_min := Vector2i.ZERO
var _center_pixel_max := Vector2i.ZERO

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	add_to_group("ground")
	_ensure_default_textures_exist()
	_init_mask_map()
	_setup_material()


func _process(_delta: float) -> void:
	# Disconnected slashes are no longer removed; they stay permanent on the ground.
	pass


# ==============================================================================
# Initialization & Setup
# ==============================================================================

func _init_mask_map() -> void:
	var total_cells := mask_resolution * mask_resolution
	_cell_timers = PackedFloat32Array()
	_cell_timers.resize(total_cells)
	_cell_timers.fill(0.0)

	_cell_connected = PackedByteArray()
	_cell_connected.resize(total_cells)
	_cell_connected.fill(0)

	_cell_is_center = PackedByteArray()
	_cell_is_center.resize(total_cells)
	_cell_is_center.fill(0)

	# Create RGBA8 image for connectivity mask
	# R = Disconnected slash fading intensity (1.0 -> 0.0 over 5s)
	# G = Connected to center (Green!)
	# B = Permanent center patch
	mask_image = Image.create(mask_resolution, mask_resolution, false, Image.FORMAT_RGBA8)
	mask_image.fill(Color(0.0, 0.0, 0.0, 1.0))

	# Initialize permanent center patch with hard 90-degree corners
	var half_sz := center_patch_size * 0.5
	var p_min := world_to_pixel(Vector3(-half_sz.x, 0.0, -half_sz.y))
	var p_max := world_to_pixel(Vector3(half_sz.x, 0.0, half_sz.y))

	_center_pixel_min = Vector2i(mini(p_min.x, p_max.x), mini(p_min.y, p_max.y))
	_center_pixel_max = Vector2i(maxi(p_min.x, p_max.x), maxi(p_min.y, p_max.y))

	for py in range(_center_pixel_min.y, _center_pixel_max.y + 1):
		for px in range(_center_pixel_min.x, _center_pixel_max.x + 1):
			var idx := py * mask_resolution + px
			_cell_is_center[idx] = 1
			_cell_connected[idx] = 1
			# Center patch: G = 1.0 (connected green), B = 1.0 (center marker)
			mask_image.set_pixel(px, py, Color(0.0, 1.0, 1.0, 1.0))

	mask_texture = ImageTexture.create_from_image(mask_image)


func _setup_material() -> void:
	var shader_res = load("res://shaders/ground.gdshader") as Shader
	if not shader_res:
		push_error("Ground: Could not load res://shaders/ground.gdshader")
		return

	shader_material = ShaderMaterial.new()
	shader_material.shader = shader_res

	# Load default textures if not explicitly set
	if not texture_base and ResourceLoader.exists("res://textures/ground_stone.png"):
		texture_base = load("res://textures/ground_stone.png")
	if not texture_slash and ResourceLoader.exists("res://textures/ground_slash.png"):
		texture_slash = load("res://textures/ground_slash.png")

	_update_shader_params()

	if mesh_instance:
		mesh_instance.material_override = shader_material


func _update_shader_params() -> void:
	if not shader_material:
		return

	shader_material.set_shader_parameter("color_base", color_base)
	shader_material.set_shader_parameter("color_slash", color_slash)
	shader_material.set_shader_parameter("color_connected", color_connected)
	shader_material.set_shader_parameter("mask_texture", mask_texture)
	shader_material.set_shader_parameter("ground_size", ground_size)
	shader_material.set_shader_parameter("ground_offset", ground_offset)

	shader_material.set_shader_parameter("use_texture_base", use_texture_base)
	shader_material.set_shader_parameter("use_texture_slash", use_texture_slash)
	if texture_base:
		shader_material.set_shader_parameter("texture_base", texture_base)
	if texture_slash:
		shader_material.set_shader_parameter("texture_slash", texture_slash)

	shader_material.set_shader_parameter("uv_scale_base", uv_scale_base)
	shader_material.set_shader_parameter("uv_scale_slash", uv_scale_slash)
	shader_material.set_shader_parameter("base_roughness", base_roughness)
	shader_material.set_shader_parameter("slash_roughness", slash_roughness)
	shader_material.set_shader_parameter("slash_emission_energy", slash_emission_energy)
	shader_material.set_shader_parameter("connected_emission_energy", connected_emission_energy)


# ==============================================================================
# Public API: Connectivity & Mask Queries
# ==============================================================================

## Convert a world 3D position to normalized UV coordinates (0.0 to 1.0)
func world_to_uv(world_pos: Vector3) -> Vector2:
	var u := (world_pos.x - ground_offset.x) / ground_size.x + 0.5
	var v := (world_pos.z - ground_offset.y) / ground_size.y + 0.5
	return Vector2(u, v)


## Convert a world 3D position to pixel coordinates on the mask image
func world_to_pixel(world_pos: Vector3) -> Vector2i:
	var uv := world_to_uv(world_pos)
	var px := clampi(int(uv.x * mask_resolution), 0, mask_resolution - 1)
	var py := clampi(int(uv.y * mask_resolution), 0, mask_resolution - 1)
	return Vector2i(px, py)


## Returns true if the given world position is boosted (connected green ground, center patch, or active blue slash)
func is_boosted_at(world_pos: Vector3) -> bool:
	if not mask_image or _cell_connected.is_empty():
		return false
	var p := world_to_pixel(world_pos)
	var idx := p.y * mask_resolution + p.x
	if idx < 0 or idx >= _cell_connected.size():
		return false
	# Boosted if on center patch, connected green path, OR active (unfaded) blue slash!
	return _cell_is_center[idx] == 1 or _cell_connected[idx] == 1 or _cell_timers[idx] > 0.0


## Returns true if the position is connected to the permanent center patch (green)
func is_connected_at(world_pos: Vector3) -> bool:
	if not mask_image or _cell_connected.is_empty():
		return false
	var p := world_to_pixel(world_pos)
	var idx := p.y * mask_resolution + p.x
	if idx < 0 or idx >= _cell_connected.size():
		return false
	return _cell_is_center[idx] == 1 or _cell_connected[idx] == 1


## Returns ground type: 0 = normal base ground, 1 = blue slash (fading), 2 = green connected (permanent)
func get_ground_type_at(world_pos: Vector3) -> int:
	if not mask_image or _cell_connected.is_empty():
		return 0
	var p := world_to_pixel(world_pos)
	var idx := p.y * mask_resolution + p.x
	if idx < 0 or idx >= _cell_connected.size():
		return 0
	if _cell_is_center[idx] == 1 or _cell_connected[idx] == 1:
		return 2 # Green / connected permanent
	if _cell_timers[idx] > 0.0:
		return 1 # Blue / fading
	return 0 # Base ground


## Query the mask value at a given world position
## Returns 1.0 if boosted (green or active blue), otherwise 0.0
func get_mask_value(world_pos: Vector3) -> float:
	return 1.0 if is_boosted_at(world_pos) else 0.0


## Paint a crescent slash on the ground.
## Slashes connected to the center patch turn GREEN and stay permanent.
## Unconnected slashes appear cyan and remain permanent on the ground.
func paint_slash(origin: Vector3, forward: Vector3, min_r: float = 0.8, max_r: float = 4.2, arc_deg: float = 135.0, _strength: float = 1.0) -> void:
	if not enable_ground_creation:
		return
	if not mask_image or not mask_texture:
		return

	var fwd_2d := Vector2(forward.x, forward.z).normalized()
	if fwd_2d.is_zero_approx():
		fwd_2d = Vector2(0.0, -1.0)

	var half_arc := deg_to_rad(arc_deg * 0.5)

	# Bounding box in mask coordinates
	var min_world_x := origin.x - max_r
	var max_world_x := origin.x + max_r
	var min_world_z := origin.z - max_r
	var max_world_z := origin.z + max_r

	var p_min := world_to_pixel(Vector3(min_world_x, 0.0, min_world_z))
	var p_max := world_to_pixel(Vector3(max_world_x, 0.0, max_world_z))

	var start_x := mini(p_min.x, p_max.x)
	var end_x := maxi(p_min.x, p_max.x)
	var start_y := mini(p_min.y, p_max.y)
	var end_y := maxi(p_min.y, p_max.y)

	var cells_painted := 0

	for py in range(start_y, end_y + 1):
		var v := (float(py) + 0.5) / float(mask_resolution)
		var wz := (v - 0.5) * ground_size.y + ground_offset.y

		for px in range(start_x, end_x + 1):
			var u := (float(px) + 0.5) / float(mask_resolution)
			var wx := (u - 0.5) * ground_size.x + ground_offset.x

			var diff := Vector2(wx - origin.x, wz - origin.z)
			var dist := diff.length()
			if dist < min_r or dist > max_r:
				continue

			var angle: float = abs(diff.angle_to(fwd_2d))
			if angle > half_arc:
				continue

			var idx := py * mask_resolution + px

			# Do not overwrite the permanent center patch
			if _cell_is_center[idx] == 1:
				continue

			# Hard corner discrete stamp: cell is active!
			_cell_timers[idx] = fade_duration
			_active_cells[idx] = true
			cells_painted += 1

	if cells_painted > 0:
		_recalculate_connectivity()
		_render_active_cells()
		mask_texture.update(mask_image)
		mask_updated.emit()


# ==============================================================================
# Connectivity Engine (Flood-Fill BFS from Center Patch)
# ==============================================================================

func _recalculate_connectivity() -> void:
	# Clear connected flag on all non-center cells
	for idx in _active_cells.keys():
		_cell_connected[idx] = 0

	# BFS queue initialized with all center patch cells
	var queue: Array[int] = []

	for py in range(_center_pixel_min.y, _center_pixel_max.y + 1):
		for px in range(_center_pixel_min.x, _center_pixel_max.x + 1):
			var idx := py * mask_resolution + px
			queue.append(idx)

	# 8-neighbor connectivity offsets for contiguous diagonal & orthogonal trails
	var neighbor_offsets: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1,  0),                  Vector2i(1,  0),
		Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1)
	]

	var head := 0
	var connected_count := 0

	while head < queue.size():
		var cur_idx: int = queue[head]
		head += 1

		var cx := cur_idx % mask_resolution
		var cy := int(float(cur_idx) / float(mask_resolution))

		for off in neighbor_offsets:
			var nx := cx + off.x
			var ny := cy + off.y

			if nx < 0 or nx >= mask_resolution or ny < 0 or ny >= mask_resolution:
				continue

			var n_idx := ny * mask_resolution + nx

			# Skip already connected
			if _cell_connected[n_idx] == 1:
				continue

			# Check if adjacent cell has active paint
			if _cell_timers[n_idx] > 0.0:
				_cell_connected[n_idx] = 1
				connected_count += 1
				queue.append(n_idx)

	connectivity_changed.emit(connected_count)


func _render_active_cells() -> void:
	for idx in _active_cells.keys():
		var px := int(idx) % mask_resolution
		var py := int(float(idx) / float(mask_resolution))

		if _cell_connected[idx] == 1:
			# Connected to center: TURN GREEN!
			mask_image.set_pixel(px, py, Color(0.0, 1.0, 0.0, 1.0))
		else:
			# Disconnected: permanent cyan slash (full intensity, no fading)
			mask_image.set_pixel(px, py, Color(1.0, 0.0, 0.0, 1.0))


## Clear all slashed areas outside the permanent center patch
func clear_mask() -> void:
	if not mask_image or not mask_texture:
		return

	# Reset active cells
	for idx in _active_cells.keys():
		var px := int(idx) % mask_resolution
		var py := int(float(idx) / float(mask_resolution))
		_cell_timers[idx] = 0.0
		_cell_connected[idx] = 0
		mask_image.set_pixel(px, py, Color(0.0, 0.0, 0.0, 1.0))

	_active_cells.clear()

	# Re-ensure center patch is intact
	for py in range(_center_pixel_min.y, _center_pixel_max.y + 1):
		for px in range(_center_pixel_min.x, _center_pixel_max.x + 1):
			var idx := py * mask_resolution + px
			_cell_is_center[idx] = 1
			_cell_connected[idx] = 1
			mask_image.set_pixel(px, py, Color(0.0, 1.0, 1.0, 1.0))

	mask_texture.update(mask_image)
	mask_updated.emit()


## Toggle between 2 colors mode and 2 textures mode
func toggle_textures() -> void:
	var new_state: bool = not (use_texture_base and use_texture_slash)
	use_texture_base = new_state
	use_texture_slash = new_state
	_update_shader_params()
	textures_toggled.emit(new_state)


# ==============================================================================
# Procedural Default Textures Generation
# ==============================================================================

func _ensure_default_textures_exist() -> void:
	var dir := DirAccess.open("res://")
	if not dir.dir_exists("textures"):
		dir.make_dir("textures")

	if not FileAccess.file_exists("res://textures/ground_stone.png"):
		_generate_stone_texture("res://textures/ground_stone.png")
	if not FileAccess.file_exists("res://textures/ground_slash.png"):
		_generate_energy_texture("res://textures/ground_slash.png")


func _generate_stone_texture(path: String) -> void:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var tiles := 4
	var tile_size := int(size / float(tiles))

	for y in range(size):
		var ty := y % tile_size
		for x in range(size):
			var tx := x % tile_size

			# Border groove
			var is_border := (tx < 3 or tx >= tile_size - 3 or ty < 3 or ty >= tile_size - 3)
			var base_val := 0.28
			if is_border:
				base_val = 0.12
			else:
				# Tile variation
				var tile_idx_x := int(x / float(tile_size))
				var tile_idx_y := int(y / float(tile_size))
				var seed_val := sin(float(tile_idx_x * 7 + tile_idx_y * 13)) * 0.04
				var grain := (sin(float(x * 12 + y * 7)) * cos(float(y * 11 - x * 5))) * 0.025
				base_val = clampf(base_val + seed_val + grain, 0.15, 0.45)

			img.set_pixel(x, y, Color(base_val * 0.9, base_val, base_val * 1.05, 1.0))

	img.save_png(path)


func _generate_energy_texture(path: String) -> void:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cell_size := 32

	for y in range(size):
		var cy := y % cell_size
		for x in range(size):
			var cx := x % cell_size

			# Glowing lattice grid lines
			var dist_to_edge := mini(mini(cx, cell_size - cx), mini(cy, cell_size - cy))
			if dist_to_edge <= 2:
				var glow := 1.0 - (float(dist_to_edge) / 3.0)
				img.set_pixel(x, y, Color(0.25 * glow, 0.9 * glow, 1.0 * glow, 1.0))
			else:
				var center_dist := Vector2(cx - cell_size * 0.5, cy - cell_size * 0.5).length()
				var core_glow := clampf(1.0 - center_dist / (cell_size * 0.5), 0.0, 1.0)
				var r := 0.05 + 0.15 * core_glow
				var g := 0.25 + 0.5 * core_glow
				var b := 0.5 + 0.5 * core_glow
				img.set_pixel(x, y, Color(r, g, b, 1.0))

	img.save_png(path)
