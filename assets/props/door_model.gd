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

## Reduzierte Meshes (tools/bake_door_lod.gd). Der Original-Griff hat ~1,5 Mio.
## Dreiecke, gespiegelt ~3 Mio. pro Tuer - das hat die FPS in jedem Raum mit
## offener Tuer und schattenwerfenden Lampen eingebrochen.
const LOWPOLY_MESHES := {
	"Handle_3_001_Torus": preload("res://assets/models/door_lod/Handle_3_001_Torus.res"),
	"Bolt": preload("res://assets/models/door_lod/Bolt.res"),
}


func _ready() -> void:
	var wood := WOOD_MATERIAL.duplicate() as StandardMaterial3D
	wood.uv1_scale = Vector3.ONE * WOOD_UV_SCALE
	for child in get_children():
		if child is MeshInstance3D and LOWPOLY_MESHES.has(String(child.name)):
			child.mesh = LOWPOLY_MESHES[String(child.name)]
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
	_connect_shadow_switch()


## Schattenwurf nur bei geschlossener, ruhender Tuer.
## Eine bewegte Tuer invalidiert jedes Frame den Schatten-Cache aller Lampen in
## Reichweite; jede dieser Lampen rendert dann ihre Schattenkarte mit allen
## CSG-Teilen neu (gemessen: ~2,5k -> 8-16k Draw-Calls waehrend die Tuer schwingt).
## Offen/in Bewegung wirft sie deshalb keinen Schatten; sobald sie wieder zu
## ist, schaltet er einmalig zurueck, damit sie Licht der Nachbarraeume blockt.
var _shadow_gen: int = 0


func _connect_shadow_switch() -> void:
	var door := get_parent()
	if door == null or not door.has_signal("door_state_changed"):
		return
	door.door_state_changed.connect(_on_door_state_changed.bind(door))
	if door.get("is_open"):
		_set_shadows(false)


func _on_door_state_changed(is_open: bool, door: Node) -> void:
	_shadow_gen += 1
	var gen := _shadow_gen
	if is_open:
		_set_shadows(false)
		return
	# Schliessen: Schatten erst wieder an, wenn die Drehung fertig ist.
	var tw = door.get("_rotation_tween")
	if tw is Tween and (tw as Tween).is_valid() and (tw as Tween).is_running():
		await (tw as Tween).finished
	if gen == _shadow_gen:
		_set_shadows(true)


func _set_shadows(on: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = mode
