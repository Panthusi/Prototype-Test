class_name TrainingDummy
extends StaticBody3D

@onready var mesh: MeshInstance3D = $MeshInstance3D
var _orig_scale: Vector3 = Vector3.ONE
var _wobble_tween: Tween


func _ready() -> void:
	add_to_group("damageable")
	if mesh:
		_orig_scale = mesh.scale


func take_damage(_amount: float, _source: Node3D = null) -> void:
	# Squash and stretch wobble effect when slashed
	if not mesh:
		return
	if _wobble_tween:
		_wobble_tween.kill()

	mesh.scale = _orig_scale * Vector3(1.4, 0.6, 1.4)
	_wobble_tween = create_tween()
	_wobble_tween.tween_property(mesh, "scale", _orig_scale, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
