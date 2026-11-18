@tool
extends StaticBody3D
## Wandsegment: unten Holzvertäfelung, oben Tapete (umschaltbar).

@export var upper_material: Material = preload("res://assets/materials/wallpaper_aged.tres"):
	set(value):
		upper_material = value
		_apply()

func _ready() -> void:
	_apply()

func _apply() -> void:
	var m := get_node_or_null("Wallpaper") as MeshInstance3D
	if m:
		m.material_override = upper_material
