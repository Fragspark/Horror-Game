class_name MonsterEntity
extends Node3D
## Huelle um ein animiertes Wesen (Monster "Distorted Wand", spaeter z. B. ein
## Kind-Modell auf Map 2). Die Horror-Events sprechen nur diese kleine API an,
## nicht das konkrete Modell. Ein anderes Modell funktioniert, wenn die Szene
## einen Knoten "Model" (mit Skeleton3D), einen "AnimationPlayer" und optional
## einen "Voice" (AudioStreamPlayer3D) enthaelt.
##
## Konvention: Vorne = -Z (Godot-Standard). Das FBX-Modell schaut nach +Z und
## ist in distorted_wand.tscn deshalb um 180 Grad gedreht.

signal animation_done(anim_name: StringName)

## Hoehe des Wesens in Metern (fuer Sichtpruefungen / Notifier-AABB).
@export var body_height: float = 1.8
@export var body_width: float = 0.7

@onready var anim_player: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var model: Node3D = get_node_or_null("Model")
@onready var voice: AudioStreamPlayer3D = get_node_or_null("Voice")

var _skeleton: Skeleton3D


func _ready() -> void:
	if anim_player:
		anim_player.animation_finished.connect(func(n: StringName) -> void: animation_done.emit(n))


## Das Skelett des Modells (oder null).
func get_skeleton() -> Skeleton3D:
	if _skeleton == null and model != null:
		_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	return _skeleton


func has_animation(anim_name: StringName) -> bool:
	return anim_player != null and anim_player.has_animation(anim_name)


## Spielt eine Animation. Gibt die effektive Dauer in Sekunden zurueck
## (0.0, wenn die Animation nicht existiert).
func play_animation(anim_name: StringName, speed: float = 1.0, loop: bool = false,
		blend: float = 0.1) -> float:
	if not has_animation(anim_name):
		push_warning("MonsterEntity: Animation '%s' nicht gefunden." % anim_name)
		return 0.0
	var anim := anim_player.get_animation(anim_name)
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	anim_player.play(anim_name, blend, speed)
	return anim.length / maxf(absf(speed), 0.01)


## Friert die Figur im ersten Bild (oder bei `time`) einer Animation ein, z. B.
## "Zombie Scream" bei 0.0 s als stehende Pose.
func hold_pose(anim_name: StringName, time: float = 0.0) -> void:
	if not has_animation(anim_name):
		return
	anim_player.play(anim_name)
	anim_player.seek(time, true)
	anim_player.pause()


## Hoehe der Fuss-Spitzen unter dem Modell-Ursprung in der Ruhepose. Wird ohne
## Animation gearbeitet (z. B. Eckenspaeher), muss der Knoten um diesen Wert
## angehoben werden, damit die Figur auf dem Boden steht.
func get_rest_foot_depth() -> float:
	var sk := get_skeleton()
	if sk == null:
		return 0.0
	var lowest := 0.0
	for bone_name in ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]:
		var idx := sk.find_bone(bone_name)
		if idx >= 0:
			lowest = minf(lowest, _chain_pose(sk, idx).origin.y)
	return -lowest


func stop_animation() -> void:
	if anim_player:
		anim_player.stop()


## Spielt einen Sound ueber den "Voice"-Player (3D) ab.
func play_voice(stream: AudioStream, volume_db: float = 0.0) -> void:
	if voice == null or stream == null:
		return
	voice.stream = stream
	voice.volume_db = volume_db
	voice.play()


## Setzt die Render-Layer aller Meshes (z. B. nur Layer 2 fuer den Spiegel).
func set_render_layers(mask: int) -> void:
	for node in find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = mask


## Dreht das Wesen um die Hochachse so, dass es auf `world_pos` schaut.
func face_point(world_pos: Vector3) -> void:
	var flat := Vector3(world_pos.x, global_position.y, world_pos.z)
	if flat.distance_to(global_position) > 0.01:
		look_at(flat, Vector3.UP)


## Weltposition eines Knochens (z. B. "mixamorig_Head"); Fallback: Koerpermitte.
func get_bone_world_position(bone_name: String) -> Vector3:
	var sk := get_skeleton()
	if sk != null:
		var idx := sk.find_bone(bone_name)
		if idx >= 0:
			return sk.global_transform * _chain_pose(sk, idx).origin
	return global_position + Vector3(0.0, body_height * 0.6, 0.0)


## Mitte des Koerpers in Weltkoordinaten (Ziel fuer Sichtstrahlen).
func get_chest_position() -> Vector3:
	return global_position + global_transform.basis.y * (body_height * 0.7)


## Dreht den Knochen `bone_name` so, dass die Verbindung zum Kindknochen
## `child_name` in `world_dir` zeigt. `weight` 0..1 blendet von der aktuellen
## Pose (0) zur Zielpose (1). Funktioniert achsenunabhaengig (kein IK-Setup
## noetig); die Animation sollte dabei gestoppt sein.
func point_limb(bone_name: String, child_name: String, world_dir: Vector3,
		weight: float = 1.0) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var bone := sk.find_bone(bone_name)
	var child := sk.find_bone(child_name)
	if bone < 0 or child < 0:
		return
	var dir := (sk.global_transform.basis.inverse() * world_dir).normalized()
	if dir.length_squared() < 0.5:
		return

	var parent := sk.get_bone_parent(bone)
	var parent_pose := _chain_pose(sk, parent) if parent >= 0 else Transform3D.IDENTITY
	var rest_local := sk.get_bone_rest(bone)
	var bone_pose := parent_pose * rest_local
	var child_pose := bone_pose * sk.get_bone_rest(child)
	var cur_dir := (child_pose.origin - bone_pose.origin).normalized()
	if cur_dir.length_squared() < 0.5:
		return

	var delta := Quaternion(cur_dir, dir)
	var target_basis := Basis(delta) * bone_pose.basis
	var target_local := parent_pose.affine_inverse() * Transform3D(target_basis, bone_pose.origin)
	var target_q := target_local.basis.get_rotation_quaternion()
	var rest_q := rest_local.basis.get_rotation_quaternion()
	sk.set_bone_pose_rotation(bone, rest_q.slerp(target_q, clampf(weight, 0.0, 1.0)))


## Setzt alle Knochen zurueck auf die Ruhepose.
func reset_pose() -> void:
	var sk := get_skeleton()
	if sk:
		sk.reset_bone_poses()


## Globale Pose (im Skelettraum) aus den lokalen Posen, immer aktuell.
static func _chain_pose(sk: Skeleton3D, bone: int) -> Transform3D:
	var pose := Transform3D.IDENTITY
	var idx := bone
	while idx >= 0:
		pose = sk.get_bone_pose(idx) * pose
		idx = sk.get_bone_parent(idx)
	return pose
