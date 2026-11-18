@tool
extends EditorScript
## Richtet das Monster "Distorted Wand" automatisch ein.
## Ausfuehren im Godot-Editor: Skript oeffnen und Strg+Shift+X druecken.
##
## Erzeugt:
##   res://assets/monster/crawl_fixed.tres      Kriech-Animation mit angepassten Oberarmen
##   res://assets/monster/monster_anims.tres    AnimationLibrary (alle Animationen)
##   res://scenes/monster/distorted_wand.tscn   Monster-Szene (Skin-FBX + AnimationPlayer)
##
## Voraussetzung: Die FBX-Dateien in res://assets/monster/ sind importiert
## (der Editor macht das beim Start automatisch).
##
## SICHERHEIT: Standardmaessig wird KEINE bestehende Datei ueberschrieben.
## Existiert eine Zieldatei schon (z. B. manuell bearbeitet), wird sie
## uebersprungen und unveraendert weiterverwendet. Zum gezielten Neu-Erzeugen
## das passende OVERWRITE_*-Flag auf true setzen; die alte Datei wird dann
## vorher als "<datei>.<zeitstempel>.bak" daneben gesichert (Godot ignoriert .bak).

const OVERWRITE_CRAWL_FIXED := false
const OVERWRITE_LIBRARY := false
const OVERWRITE_SCENE := false

const DIR := "res://assets/monster/"
const SKIN_SCENE := DIR + "running_crawl_skin.fbx"
const ANIM_SOURCES := {
	"Running Crawl": DIR + "running_crawl_noskin.fbx",
	"Zombie Scream": DIR + "zombie_scream_noskin.fbx",
}
const CRAWL_NAME := "Running Crawl"
const CRAWL_FIXED_PATH := DIR + "crawl_fixed.tres"
const LIBRARY_PATH := DIR + "monster_anims.tres"
const SCENE_PATH := "res://scenes/monster/distorted_wand.tscn"
const ENTITY_SCRIPT := "res://scripts/monster_entity.gd"

## Oberarm-Korrektur fuer die Kriech-Animation (Grad). Die Hand soll beim
## Kriechen nicht im Boden versinken: Arme werden nach aussen gespreizt und
## nach oben gehoben. Bei Bedarf hier feinjustieren und das Skript neu starten.
const ARM_OUTWARD_DEG := 18.0
const ARM_LIFT_DEG := 14.0
const ARM_BONES := {
	"mixamorig_LeftArm": 1.0,   # +1 = nach links aussen
	"mixamorig_RightArm": -1.0,  # -1 = nach rechts aussen
}


func _run() -> void:
	print("== setup_monster: Start ==")
	if not ResourceLoader.exists(SKIN_SCENE):
		push_error("setup_monster: %s fehlt (FBX nicht importiert?)." % SKIN_SCENE)
		return

	var skin_inst := (load(SKIN_SCENE) as PackedScene).instantiate()
	var skeleton := skin_inst.find_child("Skeleton3D", true, false) as Skeleton3D

	# 1) Kriech-Korrektur (crawl_fixed.tres) - nur wenn noetig/erlaubt.
	if _may_write(CRAWL_FIXED_PATH, OVERWRITE_CRAWL_FIXED):
		var crawl := _extract_animation(ANIM_SOURCES[CRAWL_NAME])
		if crawl == null:
			push_error("setup_monster: Keine Animation in %s." % ANIM_SOURCES[CRAWL_NAME])
		else:
			var changed := _fix_crawl_arms(crawl, skeleton)
			crawl.resource_name = "crawl_fixed"
			crawl.loop_mode = Animation.LOOP_LINEAR
			var err := ResourceSaver.save(crawl, CRAWL_FIXED_PATH)
			print("  crawl_fixed.tres gespeichert (err=%d, %d Arm-Tracks angepasst)" % [err, changed])

	# 2) AnimationLibrary (monster_anims.tres) - nur wenn noetig/erlaubt.
	if _may_write(LIBRARY_PATH, OVERWRITE_LIBRARY):
		var library := AnimationLibrary.new()
		for anim_name: String in ANIM_SOURCES:
			var anim := _extract_animation(ANIM_SOURCES[anim_name])
			if anim == null:
				push_error("setup_monster: Keine Animation in %s." % ANIM_SOURCES[anim_name])
				continue
			anim.loop_mode = Animation.LOOP_LINEAR if anim_name == CRAWL_NAME else Animation.LOOP_NONE
			library.add_animation(anim_name, anim)
			print("  Animation '%s': %.2f s, %d Tracks" % [anim_name, anim.length, anim.get_track_count()])
		if ResourceLoader.exists(CRAWL_FIXED_PATH):
			# Als externe Ressource einbinden, nicht einbetten.
			library.add_animation("crawl_fixed", ResourceLoader.load(
				CRAWL_FIXED_PATH, "Animation", ResourceLoader.CACHE_MODE_REPLACE))
		var lib_err := ResourceSaver.save(library, LIBRARY_PATH)
		print("  monster_anims.tres gespeichert (err=%d)" % lib_err)

	# 3) Szene (distorted_wand.tscn) - nur wenn noetig/erlaubt. Die Library
	# wird von der Platte geladen, damit die Szene sie extern referenziert.
	if _may_write(SCENE_PATH, OVERWRITE_SCENE):
		var saved_library := ResourceLoader.load(
			LIBRARY_PATH, "AnimationLibrary", ResourceLoader.CACHE_MODE_REPLACE) as AnimationLibrary
		if saved_library == null:
			push_error("setup_monster: %s fehlt - Szene nicht gebaut." % LIBRARY_PATH)
		else:
			_build_scene(saved_library)
	skin_inst.free()
	print("== setup_monster: fertig ==")


## true, wenn `path` geschrieben werden darf. Existiert die Datei und ist
## `overwrite` aus, wird sie uebersprungen. Bei `overwrite` wird vorher eine
## Sicherungskopie angelegt.
func _may_write(path: String, overwrite: bool) -> bool:
	if not FileAccess.file_exists(path):
		return true
	if not overwrite:
		print("  %s existiert - uebersprungen (OVERWRITE-Flag ist aus)." % path.get_file())
		return false
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var backup := "%s.%s.bak" % [path, stamp]
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(path),
		ProjectSettings.globalize_path(backup))
	if err != OK:
		push_error("setup_monster: Sicherung von %s fehlgeschlagen (%d) - nichts ueberschrieben." % [path, err])
		return false
	print("  Sicherung angelegt: %s" % backup.get_file())
	return true


## Holt die erste echte Animation (nicht "RESET") aus einer FBX-Szene.
func _extract_animation(fbx_path: String) -> Animation:
	if not ResourceLoader.exists(fbx_path):
		return null
	var inst := (load(fbx_path) as PackedScene).instantiate()
	var result: Animation = null
	var player := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player:
		for n in player.get_animation_list():
			if n != &"RESET":
				result = player.get_animation(n).duplicate(true) as Animation
				break
	inst.free()
	return result


## Dreht die Oberarm-Rotationstracks leicht nach aussen/oben. Die Drehung wird
## in Weltrichtungen (Skelettraum) definiert und in den Rahmen des Eltern-
## Knochens uebersetzt, damit sie unabhaengig von den Mixamo-Bone-Achsen ist.
## Gibt die Anzahl angepasster Tracks zurueck.
func _fix_crawl_arms(anim: Animation, skeleton: Skeleton3D) -> int:
	var changed := 0
	for bone_name in ARM_BONES:
		var side: float = ARM_BONES[bone_name]
		var track := anim.find_track(NodePath("Skeleton3D:" + bone_name), Animation.TYPE_ROTATION_3D)
		if track < 0:
			push_warning("setup_monster: Kein Rotationstrack fuer %s." % bone_name)
			continue

		# Gewuenschte Drehung im Skelettraum: Arm nach aussen (um Z) und nach
		# vorne-oben (um X). Das Modell schaut im Skelettraum nach +Z.
		var world_rot := Basis(Vector3.BACK, deg_to_rad(ARM_OUTWARD_DEG) * side) \
			* Basis(Vector3.RIGHT, deg_to_rad(-ARM_LIFT_DEG))

		# In den Rahmen des Eltern-Knochens uebersetzen (Ruhepose).
		var local_offset := Quaternion(world_rot)
		if skeleton:
			var bone := skeleton.find_bone(bone_name)
			var parent := skeleton.get_bone_parent(bone)
			if parent >= 0:
				var p := skeleton.get_bone_global_rest(parent).basis.orthonormalized()
				local_offset = (p.inverse() * world_rot * p).get_rotation_quaternion()

		for k in anim.track_get_key_count(track):
			var q: Quaternion = anim.track_get_key_value(track, k)
			anim.track_set_key_value(track, k, (local_offset * q).normalized())
		changed += 1
	return changed


func _build_scene(library: AnimationLibrary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/monster"))

	var root := Node3D.new()
	root.name = "DistortedWand"
	if ResourceLoader.exists(ENTITY_SCRIPT):
		root.set_script(load(ENTITY_SCRIPT))

	# Modell: Skin-FBX als Instanz. Das FBX schaut nach +Z, die Szene nach -Z.
	var model := (load(SKIN_SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	model.name = "Model"
	root.add_child(model)
	model.owner = root
	model.rotation.y = PI

	# AnimationPlayer mit allen Animationen. Die Track-Pfade der FBX-Animationen
	# ("Skeleton3D:mixamorig_...") sind relativ zum Modell-Knoten.
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.owner = root
	player.root_node = NodePath("../Model")
	player.add_animation_library("", library)

	# Stimme/Atmen und Schritte als 3D-Audio (Streams setzen die Events selbst).
	for audio_name in ["Voice", "Steps"]:
		var audio := AudioStreamPlayer3D.new()
		audio.name = audio_name
		audio.bus = &"SFX"
		audio.unit_size = 6.0
		audio.max_distance = 30.0
		root.add_child(audio)
		audio.owner = root

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		push_error("setup_monster: pack() fehlgeschlagen (%d)" % pack_err)
	else:
		var save_err := ResourceSaver.save(packed, SCENE_PATH)
		print("  distorted_wand.tscn gespeichert (err=%d)" % save_err)
	root.free()
