class_name CommsRippleVFX
extends ColorRect

## Spawns a rippling radio wave effect driven by a shader and tween.

@export var duration: float = 1.2
@export var max_radius: float = 1.0

## Color override for the ripple effect. Set before adding to the scene tree.
var ripple_color: Variant = null

func _ready() -> void:
	position -= size * 0.5
	
	material = material.duplicate()
	
	if ripple_color is Color:
		(material as ShaderMaterial).set_shader_parameter("color", ripple_color)
	
	var tween: Tween = create_tween()
	tween.tween_method(_update_shader_radius, 0.0, max_radius, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)
		
	tween.finished.connect(queue_free)

func _update_shader_radius(value: float) -> void:
	(material as ShaderMaterial).set_shader_parameter("ring_radius", value)
