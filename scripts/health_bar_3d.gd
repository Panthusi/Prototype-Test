class_name HealthBar3D
extends Node3D

@export var bar_width: float = 1.2
@export var bar_height: float = 0.13
@export var fill_color: Color = Color(0.9, 0.2, 0.2, 1.0)
@export var bg_color: Color = Color(0.08, 0.1, 0.12, 0.9)
@export var label_text: String = ""
@export var show_label: bool = true

var _bg_mesh: MeshInstance3D
var _fill_mesh: MeshInstance3D
var _fill_pivot: Node3D
var _fill_mat: StandardMaterial3D
var _label: Label3D
var _current_ratio: float = 1.0
var _anim_tween: Tween


func _ready() -> void:
	_setup_visuals()


func _setup_visuals() -> void:
	# 1. Background box
	_bg_mesh = MeshInstance3D.new()
	var bg_box := BoxMesh.new()
	bg_box.size = Vector3(bar_width + 0.05, bar_height + 0.04, 0.01)
	_bg_mesh.mesh = bg_box
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = bg_color
	_bg_mesh.material_override = bg_mat
	add_child(_bg_mesh)

	# 2. Left-anchored fill pivot
	_fill_pivot = Node3D.new()
	_fill_pivot.position.x = -bar_width * 0.5
	add_child(_fill_pivot)

	_fill_mesh = MeshInstance3D.new()
	var fill_box := BoxMesh.new()
	fill_box.size = Vector3(bar_width, bar_height, 0.015)
	_fill_mesh.mesh = fill_box
	_fill_mesh.position.x = bar_width * 0.5
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.albedo_color = fill_color
	_fill_mesh.material_override = _fill_mat
	_fill_pivot.add_child(_fill_mesh)

	# 3. Label3D for title / HP value
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 22
	_label.pixel_size = 0.0035
	_label.position = Vector3(0.0, bar_height * 0.5 + 0.14, 0.0)
	_label.modulate = Color(1.0, 1.0, 1.0, 0.95)
	_label.outline_size = 4
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_label.visible = show_label
	if label_text != "":
		_label.text = label_text
	add_child(_label)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_rotation = cam.global_rotation


## Update healthbar fill ratio and label text
func update_health(current: float, max_hp: float, custom_title: String = "") -> void:
	var ratio := clampf(current / maxf(max_hp, 0.001), 0.0, 1.0)

	if _anim_tween:
		_anim_tween.kill()

	_anim_tween = create_tween()
	_anim_tween.tween_method(_apply_fill_scale, _current_ratio, ratio, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if _label:
		var title := custom_title if custom_title != "" else label_text
		if title != "":
			_label.text = "%s: %d/%d" % [title, int(current), int(max_hp)]
		else:
			_label.text = "%d / %d" % [int(current), int(max_hp)]


func _apply_fill_scale(r: float) -> void:
	_current_ratio = r
	if _fill_pivot:
		_fill_pivot.scale.x = maxf(r, 0.0001)
