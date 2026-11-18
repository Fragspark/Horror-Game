extends SceneTree
## Erzeugt reduzierte Meshes fuer die Tuergriffe aus assets/models/door.fbx.
##
## Der Griff "Handle_3_001_Torus" hat im Original ~1,5 Mio. Dreiecke, der
## Riegel "Bolt" ~20.000. door_model.gd spiegelt beide auf die zweite
## Tuerseite, damit kostete jede Tuer ~3 Mio. Dreiecke - im Bild UND in jeder
## Schattenkarte der Lampen in der Naehe. Godots Import-LODs greifen nicht,
## weil das Modell intern winzig skaliert ist (Node-Scale 100).
##
## Das Skript nimmt eine der beim Import erzeugten LOD-Stufen, entfernt alle
## nicht mehr benutzten Vertices und speichert das Ergebnis als eigenes Mesh.
## door_model.gd tauscht die Meshes zur Laufzeit aus.
##
## Aufruf (nach einem Re-Import von door.fbx erneut ausfuehren):
##   godot --headless --path . --script res://tools/bake_door_lod.gd

const SOURCE := "res://assets/models/door.fbx"
const OUT_DIR := "res://assets/models/door_lod"
## Mesh-Name -> gewuenschte maximale Dreieckszahl.
const TARGETS := {
	"Handle_3_001_Torus": 6000,
	"Bolt": 12000,
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene: Node = (load(SOURCE) as PackedScene).instantiate()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if not TARGETS.has(String(mi.name)):
			continue
		var reduced := _reduce(mi.mesh, TARGETS[String(mi.name)])
		var path := "%s/%s.res" % [OUT_DIR, mi.name]
		var err := ResourceSaver.save(reduced, path, ResourceSaver.FLAG_COMPRESS)
		print("door_lod: %s -> %s (%s)" % [mi.name, path, error_string(err)])
	scene.free()
	quit()


func _reduce(mesh: Mesh, max_tris: int) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vcount: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var info: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		var original_tris := indices.size() / 3
		# Feinste LOD-Stufe waehlen, die unter max_tris liegt.
		for lod in info.get("lods", []):
			var lod_idx := _decode_indices(lod["index_data"], vcount)
			if lod_idx.size() / 3 <= max_tris:
				indices = lod_idx
				break
		print("  surface %d: %d -> %d Dreiecke" % [s, original_tris, indices.size() / 3])
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _compact(arrays, indices))
	return out


func _decode_indices(data: PackedByteArray, vcount: int) -> PackedInt32Array:
	if vcount > 65535:
		return data.to_int32_array()
	var res := PackedInt32Array()
	res.resize(data.size() / 2)
	for i in res.size():
		res[i] = data.decode_u16(i * 2)
	return res


## Behaelt nur die Vertices, die von indices referenziert werden.
func _compact(arrays: Array, indices: PackedInt32Array) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var new_idx := PackedInt32Array()
	new_idx.resize(indices.size())
	for i in indices.size():
		var old := indices[i]
		if not remap.has(old):
			remap[old] = order.size()
			order.append(old)
		new_idx[i] = remap[old]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a in Mesh.ARRAY_MAX:
		var src = arrays[a]
		if src == null or a == Mesh.ARRAY_INDEX:
			continue
		var per_vertex := 4 if a == Mesh.ARRAY_TANGENT else 1
		var dst = src.duplicate()
		dst.resize(order.size() * per_vertex)
		for n in order.size():
			for k in per_vertex:
				dst[n * per_vertex + k] = src[order[n] * per_vertex + k]
		out[a] = dst
	out[Mesh.ARRAY_INDEX] = new_idx
	return out
