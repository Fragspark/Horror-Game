extends Node3D
## Daempft die Lichtreflexion der importierten glTF-Moebel (Poly-Haven-Modelle
## sind fuer Tageslicht gebaut und glaenzen im duesteren Haus zu stark).
## Glas/transparente Materialien bleiben unveraendert.

## Faktor auf die Roughness-Textur (>1 wird auf 1 geklemmt -> matter).
@export var roughness_boost: float = 1.0
## Spiegelungsstaerke der Oberflaeche (Godot-Standard 0.5).
@export var specular: float = 0.12
## Faktor auf die Albedo (<1 dunkelt ab, z. B. fuer zu helles Porzellan).
@export var albedo_tint: Color = Color(1, 1, 1)
## Obergrenze fuer Metallic (Holz/Stoff sollen nie metallisch wirken).
@export var max_metallic: float = 0.35


func _ready() -> void:
	_apply(self)


func _apply(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i) as StandardMaterial3D
				if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					continue
				if mat.resource_name.to_lower().contains("glass"):
					continue
				var copy := mat.duplicate() as StandardMaterial3D
				copy.roughness = clampf(copy.roughness * roughness_boost, 0.0, 1.0)
				copy.metallic_specular = specular
				copy.metallic = minf(copy.metallic, max_metallic)
				copy.albedo_color = copy.albedo_color * albedo_tint
				mi.set_surface_override_material(i, copy)
	for child in node.get_children():
		_apply(child)
