extends Node3D
## Sichtbarer Spielerkoerper (Mixamo-Modell) als Kind von Player/Body.
##
## Spielt die Geh-Animation in Schleife, skaliert ihr Tempo mit der echten
## Bewegungsgeschwindigkeit und blendet den Kopf aus, damit die Kamera nicht
## im Schaedel steckt. Beim Runterschauen sieht man Torso, Arme und Beine;
## Lampen und Spiegel werfen/zeigen den Koerper ebenfalls.

## Name der Geh-Animation im FBX.
const WALK_ANIM := &"mixamo_com"
## Geschwindigkeit (m/s), bei der die Animation mit Originaltempo laeuft.
const ANIM_REF_SPEED: float = 1.4
## Unter dieser Geschwindigkeit steht der Koerper still (Animation pausiert).
const MIN_SPEED: float = 0.3
## Hoehe der Fuesse relativ zum Player-Ursprung (Standkapsel: 0.15 - 1.9 / 2).
const FEET_OFFSET_Y: float = -0.8
## Koerper leicht hinter die Kamera ruecken, damit die Brust nicht im Near-Clip liegt.
const BACK_OFFSET_Z: float = 0.25
## Aufrichtungs-Skalierung beim Ducken (Koerper sackt zusammen).
const CROUCH_SCALE_Y: float = 0.62

## Render-Layer: Kopflose Ich-Kopie sieht nur die Spielerkamera (Layer 3),
## die Kopie mit Kopf nur die Spiegelkamera (Layer 2, fuer Spieler ausgeblendet).
const FIRST_PERSON_LAYER: int = 3
const MIRROR_LAYER: int = 2
const MODEL_SCENE := preload("res://assets/player/Standard Walk_withSkin.fbx")

@onready var _model: Node3D = $Model

var _anim: AnimationPlayer
var _mirror_anim: AnimationPlayer

var _player: CharacterBody3D


func _ready() -> void:
	_player = get_parent().get_parent() as CharacterBody3D
	position = Vector3(0.0, FEET_OFFSET_Y, BACK_OFFSET_Z)
	# Ich-Kopie (ohne Kopf) nur fuer die Spielerkamera.
	_anim = _setup_copy(_model, FIRST_PERSON_LAYER, true)
	# Spiegel-Kopie (mit Kopf) nur fuer die Spiegelkamera.
	var mirror_copy := MODEL_SCENE.instantiate() as Node3D
	mirror_copy.name = "MirrorModel"
	mirror_copy.transform = _model.transform
	add_child(mirror_copy)
	_mirror_anim = _setup_copy(mirror_copy, MIRROR_LAYER, false)


## Richtet eine Modellkopie ein: Render-Layer, Schleifen-Animation, optional ohne Kopf.
func _setup_copy(model: Node3D, layer: int, hide_head: bool) -> AnimationPlayer:
	for mesh in model.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).layers = 1 << (layer - 1)
		if not hide_head:
			(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim and anim.has_animation(WALK_ANIM):
		anim.get_animation(WALK_ANIM).loop_mode = Animation.LOOP_LINEAR
		anim.play(WALK_ANIM)
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if hide_head and skeleton:
		var hider := HeadHider.new()
		hider.name = "HeadHider"
		skeleton.add_child(hider)
	return anim


func _process(delta: float) -> void:
	if _player == null or _anim == null:
		return
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var moving := speed > MIN_SPEED and _player.is_on_floor()
	var anim_speed := clampf(speed / ANIM_REF_SPEED, 0.0, 2.5) if moving else 0.0
	_anim.speed_scale = anim_speed
	if _mirror_anim:
		_mirror_anim.speed_scale = anim_speed
	var crouching: bool = _player.get("is_crouching") == true
	var target_y := CROUCH_SCALE_Y if crouching else 1.0
	scale.y = lerpf(scale.y, target_y, clampf(10.0 * delta, 0.0, 1.0))


## Skaliert den Kopf-Knochen nach der Animation auf ~0 (Kopf unsichtbar).
class HeadHider extends SkeletonModifier3D:
	var _head: int = -1

	func _process_modification() -> void:
		var skel := get_skeleton()
		if skel == null:
			return
		if _head < 0:
			_head = skel.find_bone("mixamorig_Head")
			if _head < 0:
				return
		skel.set_bone_pose_scale(_head, Vector3.ONE * 0.001)
