class_name CornerPeek
extends HorrorEvent
## Nur die Finger greifen um eine Wandecke und zucken blitzschnell zurueck.
##
## Platzierung: BodyAnchor HINTER die Wand (der Koerper muss von der Wand
## verdeckt sein), ReachTarget an die Wandkante, um die die Hand greift.
## Ein BoneAttachment3D am linken Hand-Knochen traegt einen
## VisibleOnScreenNotifier3D: Sobald der Spieler die Hand sieht (und nichts
## dazwischen liegt), zieht sie sich nach `retract_delay` zurueck.
##
## Die Figur wird in der Ruhepose gehalten (keine Animation); nur der linke Arm
## wird per MonsterEntity.point_limb() zum Ziel gestreckt.

@export_group("Ablauf")
@export var reach_time: float = 0.9
## Zeit zwischen "Hand gesehen" und Zurueckzucken.
@export var retract_delay: float = 0.2
@export var retract_time: float = 0.07
## Hand verschwindet, wenn sie nie gesehen wird.
@export var give_up_time: float = 20.0
@export var hand_bone: String = "mixamorig_LeftHand"
@export var forearm_bone: String = "mixamorig_LeftForeArm"
@export var arm_bone: String = "mixamorig_LeftArm"

@onready var trigger_zone: Area3D = $TriggerZone
@onready var body_anchor: Marker3D = $BodyAnchor
@onready var reach_target: Marker3D = $ReachTarget
@onready var sight_ray: RayCast3D = $SightRay

var reach_weight: float = 0.0

var _entity: Node3D
var _hand_notifier: VisibleOnScreenNotifier3D
var _hand_on_screen := false
var _running := false
var _done := false


func _ready() -> void:
	super._ready()
	trigger_zone.body_entered.connect(_on_trigger_entered)
	set_process(false)


func _on_trigger_entered(body: Node3D) -> void:
	if _running or _done or not is_player(body):
		return
	sight_ray.add_exception(body)
	if not request_scare():
		return
	_running = true
	_spawn()


func _spawn() -> void:
	_entity = spawn_entity(self, body_anchor.global_transform)
	if _entity == null:
		cancel_scare()
		_running = false
		return
	# Ruhepose: Fuesse liegen unter dem Ursprung -> Figur um die Fusstiefe anheben.
	var depth = entity_call(_entity, &"get_rest_foot_depth")
	if depth is float:
		_entity.global_position += Vector3.UP * depth
	entity_call(_entity, &"stop_animation")

	var skeleton = entity_call(_entity, &"get_skeleton") as Skeleton3D
	if skeleton == null:
		cancel_scare()
		_entity.queue_free()
		_entity = null
		_running = false
		return

	# BoneAttachment3D am Hand-Knochen + Notifier fuer "Hand im Bild".
	var attachment := BoneAttachment3D.new()
	attachment.name = "HandAttachment"
	attachment.bone_name = hand_bone
	skeleton.add_child(attachment)
	_hand_notifier = VisibleOnScreenNotifier3D.new()
	_hand_notifier.aabb = AABB(Vector3(-0.2, -0.2, -0.2), Vector3(0.4, 0.4, 0.4))
	attachment.add_child(_hand_notifier)
	_hand_notifier.screen_entered.connect(func() -> void: _hand_on_screen = true)
	_hand_notifier.screen_exited.connect(func() -> void: _hand_on_screen = false)

	_apply_reach()
	set_process(true)
	play_sound_at(creak_sound, reach_target.global_position, -8.0, 15.0)
	var tween := create_tween()
	tween.tween_property(self, "reach_weight", 1.0, reach_time).set_trans(Tween.TRANS_SINE)
	_run_sequence()


func _process(_delta: float) -> void:
	_apply_reach()


func _apply_reach() -> void:
	if _entity == null or not is_instance_valid(_entity):
		return
	var shoulder: Vector3 = _entity.get_bone_world_position(arm_bone)
	var dir := reach_target.global_position - shoulder
	if dir.length() < 0.05:
		return
	_entity.point_limb(arm_bone, forearm_bone, dir, reach_weight)
	_entity.point_limb(forearm_bone, hand_bone, dir, reach_weight)


func _run_sequence() -> void:
	var waited := 0.0
	var seen := false
	while not seen and _entity and is_instance_valid(_entity):
		await get_tree().physics_frame
		if _entity == null or not is_instance_valid(_entity):
			return
		waited += get_physics_process_delta_time()
		if waited > give_up_time:
			cancel_scare()
			_cleanup()
			return
		if reach_weight > 0.6 and _hand_on_screen:
			var hand_pos: Vector3 = _entity.get_bone_world_position(hand_bone)
			seen = is_ray_clear(sight_ray, hand_pos)

	await get_tree().create_timer(retract_delay).timeout
	if _entity == null or not is_instance_valid(_entity):
		return
	# Blitzschnell zurueck.
	play_sound_at(step_sound, reach_target.global_position, -2.0, 15.0)
	var tween := create_tween()
	tween.tween_property(self, "reach_weight", 0.0, retract_time)
	await tween.finished
	_cleanup()


func _cleanup() -> void:
	set_process(false)
	if _entity and is_instance_valid(_entity):
		_entity.queue_free()
	_entity = null
	_running = false
	_done = true
