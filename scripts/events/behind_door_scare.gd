class_name BehindDoorScare
extends HorrorEvent
## Figur versteckt sich hinter dem geoeffneten Tuerfluegel.
##
## Ablauf:
##   1. Spieler betritt RoomInsideZone -> Director wird gefragt (request_scare).
##   2. Bei Freigabe wartet das Event, bis der Spieler vom SpawnPoint WEGschaut,
##      und setzt die Figur dann (verborgen hinter dem Tuerfluegel) ab.
##   3. Geht der Spieler in die ExitHallwayZone und die Figur kommt ins Bild
##      (VisibleOnScreenNotifier3D + freier RayCast3D), reagiert sie nach 0.25 s:
##      Sound + Schrei-/Rueckzugsanimation, danach queue_free().
##
## Platzierung: Szene in den Raum ziehen, RoomInsideZone ueber den Raum,
## ExitHallwayZone ueber den Flur vor der Tuer, SpawnPoint hinter den
## geoeffneten Tuerfluegel (SpawnPoint -Z = Blickrichtung der Figur).

enum State { IDLE, ARMED, SPAWNED, REACTING, DONE }

@export_group("Ablauf")
## Pause zwischen "Figur im Bild" und der Reaktion.
@export var reaction_delay: float = 0.25
## Winkel (Grad) um die Blickrichtung, ab dem der SpawnPoint als "weggeschaut" gilt
## zusaetzlich zur Frustum-Pruefung.
@export_range(30.0, 180.0, 1.0) var look_away_angle: float = 70.0
## Dauer der Schrei-Reaktion, bevor sich die Figur zurueckzieht.
@export var react_time: float = 0.45
## Rueckzugsweg relativ zum SpawnPoint (+Z = nach hinten, weg von der Blickrichtung).
@export var retreat_offset: Vector3 = Vector3(0.0, 0.0, 2.0)
@export var retreat_time: float = 0.9
## Entfernung zum Spieler, ab der ein wartendes/verstecktes Wesen verworfen wird.
@export var abort_distance: float = 25.0
@export var breathe_when_hidden: bool = true
@export_range(-40.0, 0.0, 1.0) var breath_volume_db: float = -16.0

var state: State = State.IDLE

@onready var room_zone: Area3D = $RoomInsideZone
@onready var hallway_zone: Area3D = $ExitHallwayZone
@onready var spawn_point: Marker3D = $SpawnPoint
@onready var sight_ray: RayCast3D = $SightRay

var _in_room := false
var _in_hallway := false
var _rolled_this_visit := false
var _entity: Node3D
var _notifier: VisibleOnScreenNotifier3D
var _on_screen := false


func _ready() -> void:
	super._ready()
	room_zone.body_entered.connect(_on_room_entered)
	room_zone.body_exited.connect(_on_room_exited)
	hallway_zone.body_entered.connect(_on_hallway_entered)
	hallway_zone.body_exited.connect(_on_hallway_exited)


func _on_room_entered(body: Node3D) -> void:
	if not is_player(body):
		return
	_in_room = true
	sight_ray.add_exception(body)
	if state == State.IDLE and not _rolled_this_visit:
		_rolled_this_visit = true
		if request_scare():
			state = State.ARMED


func _on_room_exited(body: Node3D) -> void:
	if not is_player(body):
		return
	_in_room = false
	_rolled_this_visit = false
	# Spieler ist weg, bevor die Figur spawnen konnte: Freigabe zuruecknehmen.
	if state == State.ARMED and not _in_hallway:
		state = State.IDLE
		cancel_scare()


func _on_hallway_entered(body: Node3D) -> void:
	if is_player(body):
		_in_hallway = true
		sight_ray.add_exception(body)


func _on_hallway_exited(body: Node3D) -> void:
	if is_player(body):
		_in_hallway = false


func _physics_process(_delta: float) -> void:
	match state:
		State.ARMED:
			if _in_room and _player_looks_away_from(spawn_point.global_position):
				_spawn()
		State.SPAWNED:
			_check_reveal()


## true, wenn der Spieler vom Punkt weg schaut (nicht im Frustum UND Winkel).
func _player_looks_away_from(world_pos: Vector3) -> bool:
	var cam := get_camera()
	if cam == null:
		return false
	var to_point := (world_pos - cam.global_position).normalized()
	var forward := -cam.global_transform.basis.z
	var angle := rad_to_deg(forward.angle_to(to_point))
	return is_out_of_view(world_pos) and angle > look_away_angle


func _spawn() -> void:
	_entity = spawn_entity(self, spawn_point.global_transform)
	if _entity == null:
		state = State.IDLE
		cancel_scare()
		return
	# Stehende Pose, Figur steht hinter dem Tuerfluegel und atmet leise.
	entity_call(_entity, &"hold_pose", [idle_animation, 0.0])
	_notifier = attach_notifier(_entity)
	_notifier.screen_entered.connect(func() -> void: _on_screen = true)
	_notifier.screen_exited.connect(func() -> void: _on_screen = false)
	if breathe_when_hidden:
		entity_call(_entity, &"play_voice", [breath_sound, breath_volume_db])
	state = State.SPAWNED


func _check_reveal() -> void:
	if _entity == null or not is_instance_valid(_entity):
		state = State.DONE
		return
	var player := get_player()
	if player and player.global_position.distance_to(_entity.global_position) > abort_distance:
		_discard()
		return
	if not (_in_hallway and _on_screen):
		return
	var chest: Vector3 = _entity.global_position + Vector3(0.0, 1.3, 0.0)
	if is_ray_clear(sight_ray, chest):
		state = State.REACTING
		_play_reaction()


func _play_reaction() -> void:
	await get_tree().create_timer(reaction_delay).timeout
	if _entity == null or not is_instance_valid(_entity):
		state = State.DONE
		return

	var player := get_player()
	if player:
		entity_call(_entity, &"face_point", [player.global_position])
	entity_call(_entity, &"play_voice", [roar_sound, 0.0])
	entity_call(_entity, &"play_animation", [react_animation, 1.0, false, 0.05])
	await get_tree().create_timer(react_time).timeout
	if _entity == null or not is_instance_valid(_entity):
		state = State.DONE
		return

	# Rueckzug: kriechend nach hinten, weg vom Spieler, dann verschwinden.
	entity_call(_entity, &"play_animation", [crawl_animation, 1.2, true, 0.1])
	var target := spawn_point.global_transform * retreat_offset
	var tween := create_tween()
	tween.tween_property(_entity, "global_position", target, retreat_time)
	await tween.finished
	_discard()
	state = State.DONE


func _discard() -> void:
	if _entity and is_instance_valid(_entity):
		_entity.queue_free()
	_entity = null
	if state != State.REACTING:
		state = State.DONE
