extends Node3D
## Tuerblatt aus assets/models/door.fbx. Das Modell hat nur auf einer Seite
## Klinke und Schloss; hier werden diese Teile an der Blattmitte gespiegelt
## dupliziert, damit die Tuer von beiden Seiten eine Klinke hat.

## Blattmitte (Dicke) in Modellkoordinaten (z-Achse der FBX).
const LEAF_MID_Z: float = 10.2507


## Die FBX bringt nur ein weisses Material ohne Textur mit; hier kommen die
## Projekt-Materialien drauf. Das Mesh ist winzig (Node-Scale 100, Modell-Scale
## ~0,38), daher muss die Triplanar-Texturskalierung entsprechend hoch sein.
const WOOD_MATERIAL := preload("res://assets/materials/door_fbx_wood.tres")
const METAL_MATERIAL := preload("res://assets/materials/door_knob.tres")
const WOOD_UV_SCALE: float = 30.0


func _ready() -> void:
	var wood := WOOD_MATERIAL.duplicate() as StandardMaterial3D
	wood.uv1_scale = Vector3.ONE * WOOD_UV_SCALE
	for child in get_children():
		if child is MeshInstance3D:
			child.material_override = wood if child.name.begins_with("Door") else METAL_MATERIAL
	var mirror := Transform3D(Basis.from_scale(Vector3(1, 1, -1)), Vector3(0, 0, 2.0 * LEAF_MID_Z))
	for child in get_children():
		if child is MeshInstance3D and (child.name.begins_with("Handle") or child.name.begins_with("Bolt")):
			var copy: MeshInstance3D = child.duplicate()
			copy.name = String(child.name) + "_Mirror"
			add_child(copy)
			copy.transform = mirror * child.transform
