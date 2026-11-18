class_name ScarePoint
extends HorrorEvent
## Frei platzierbarer Schreckpunkt mit vier umschaltbaren Varianten.
##
##   GLIMPSE_VANISH  Figur steht im Dunkeln und verschwindet kurz nach Blickkontakt.
##   CROSS_HALLWAY   Figur krabbelt (crawl_fixed) von PathStart nach PathEnd und verschwindet.
##   BEHIND_PLAYER   Figur erscheint hinter dem Spieler, sobald er wegschaut.
##   FAKE_OUT        Nur Schritte/Knarzen/Roar, keine sichtbare Figur.
##
## Der Event startet, wenn der Spieler die TriggerZone betritt und der Director
## (Phase/Chance/Cooldown) zustimmt.

enum Mode { GLIMPSE_VANISH, CROSS_HALLWAY, BEHIND_PLAYER, FAKE_OUT }

@export var event_type: Mode = Mode.GLIMPSE_VANISH

@export_group("Glimpse / Behind Player")
## Zeit zwischen Blickkontakt und Verschwinden.
@export var vanish_delay: float = 0.3
## Blickkontakt = Figur liegt innerhalb dieses Winkels (Grad) zur Blickrichtung.
@export_range(5.0, 90.0, 1.0) var contact_angle: float = 40.0
## Wartezeit, nach der eine nie gesehene Figur verschwindet.
@export var give_up_time: float = 25.0
## Abstand hinter dem Spieler (BEHIND_PLAYER).
@export var behind_distance: float = 2.2
@export var look_away_angle: float = 70.0

@export_group("Cross Hallway")
@export var crawl_speed: float = 3.2

@export_group("Fake Out")
@export var fake_step_count: Vector2i = Vector2i(3, 6)
@export var fake_step_interval: Vector2 = Vector2(0.55, 0.9)
@export_range(0.0, 1.0, 0.05) var fake_creak_chance: float = 0.6
@export_range(0.0, 1.0, 0.05) var fake_roar_chance: float = 0.35

@onready var trigger_zone: Area3D = $TriggerZone
@onready var path_start: Marker3D = $PathStart
@onready var path_end: Marker3D = $PathEnd
@onready var sight_ray: RayCast3D = $SightRay

var _running := false
var _done := false
var _entity: Node3D
var _on_screen := false
var _waiting_for_look_away := false


func _ready() -> void:
	super._ready()
	trigger_zone.body_entered.connect(_on_trigger_entered)
	# Die Hilfsmarker sind nur im Editor relevant.
	path_start.visible = event_type == Mode.CROSS_HALLWAY
	path_end.visible = event_type == Mode.CROSS_HALLWAY


func _on_trigger_entered(body: Node3D) -> void:
	if _running or _done or not is_player(body):
		return
	sight_ray.add_exception(body)
	if not request_scare():
		return
	_running = true
	match event_type:
		Mode.GLIMPSE_VANISH:
			_start_glimpse(global_transform)
		Mode.CROSS_HALLWAY:
			_start_cross()
		Mode.BEHIND_PLAYER:
			_waiting_for_look_away = true
			_wait_for_look_away()
		Mode.FAKE_OUT:
			_start_fake_out()


func _finish() -> void:
	_running = false
	_done = true
	if _entity and is_instance_valid(_entity):
		_entity.queue_free()
	_entity = null


# --- GLIMPSE_VANISH / BEHIND_PLAYER (Figur wartet, bis sie gesehen wird) -------

func _start_glimpse(xform: Transform3D) -> void:
	_entity = spawn_entity(self, xform)
	if _entity == null:
		cancel_scare()
		_running = false
		return
	var player := get_player()
	if player:
		entity_call(_entity, &"face_point", [player.global_position])
	entity_call(_entity, &"hold_pose", [idle_animation, 0.0])
	var notifier := attach_notifier(_entity)
	notifier.screen_entered.connect(func() -> void: _on_screen = true)
	notifier.screen_exited.connect(func() -> void: _on_screen = false)
	_watch_for_contact()


func _watch_for_contact() -> void:
	var waited := 0.0
	while _entity and is_instance_valid(_entity):
		await get_tree().physics_frame
		if _entity == null or not is_instance_valid(_entity):
			return
		waited += get_physics_process_delta_time()
		if waited > give_up_time:
			cancel_scare()   # nie gesehen: zaehlt nicht als Event
			_finish()
			return
		if _has_eye_contact():
			await get_tree().create_timer(vanish_delay).timeout
			# Kurzes Zucken, dann weg.
			play_sound_at(creak_sound, global_position, -6.0)
			_finish()
			return


## Figur im Bild, nah genug an der Blickmitte und nicht verdeckt.
func _has_eye_contact() -> bool:
	var cam := get_camera()
	if cam == null or not _on_screen:
		return false
	var chest := _entity_chest()
	var forward := -cam.global_transform.basis.z
	var angle := rad_to_deg(forward.angle_to((chest - cam.global_position).normalized()))
	return angle < contact_angle and is_ray_clear(sight_ray, chest)


func _entity_chest() -> Vector3:
	var v: Variant = entity_call(_entity, &"get_chest_position")
	return v if v is Vector3 else _entity.global_position + Vector3(0.0, 1.3, 0.0)


func _wait_for_look_away() -> void:
	var waited := 0.0
	while _waiting_for_look_away:
		await get_tree().physics_frame
		var player := get_player()
		var cam := get_camera()
		if player == null or cam == null:
			continue
		waited += get_physics_process_delta_time()
		if waited > give_up_time or not trigger_zone.overlaps_body(player):
			cancel_scare()
			_waiting_for_look_away = false
			_running = false
			return
		var behind := _behind_player_position(player, cam)
		if behind.is_finite() and _is_facing_away(cam, behind):
			_waiting_for_look_away = false
			var xform := Transform3D(Basis.IDENTITY, behind)
			_start_glimpse(xform)
			if _entity:
				play_sound_at(step_sound, behind, -3.0, 20.0)
			return


## Punkt hinter dem Spieler auf Bodenhoehe dieses Knotens; Vector3.INF, wenn
## dort eine Wand ist.
func _behind_player_position(player: Node3D, cam: Camera3D) -> Vector3:
	var back := cam.global_transform.basis.z
	back.y = 0.0
	back = back.normalized()
	var pos := player.global_position + back * behind_distance
	pos.y = global_position.y
	var query := PhysicsRayQueryParameters3D.create(
			player.global_position + Vector3(0.0, 1.0, 0.0), pos + Vector3(0.0, 1.0, 0.0), 1)
	if player is CollisionObject3D:
		query.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return Vector3.INF if not hit.is_empty() else pos


func _is_facing_away(cam: Camera3D, behind: Vector3) -> bool:
	return is_out_of_view(behind + Vector3(0.0, 1.0, 0.0))


# --- CROSS_HALLWAY -------------------------------------------------------------

func _start_cross() -> void:
	var from := path_start.global_position
	var to := path_end.global_position
	var xform := Transform3D(Basis.IDENTITY, from)
	_entity = spawn_entity(self, xform)
	if _entity == null:
		cancel_scare()
		_running = false
		return
	entity_call(_entity, &"face_point", [to])
	entity_call(_entity, &"play_animation", [crawl_animation, 1.0, true, 0.0])
	var duration := maxf(from.distance_to(to) / crawl_speed, 0.3)
	play_sound_at(step_sound, from, -4.0, 20.0)
	var tween := create_tween()
	tween.tween_property(_entity, "global_position", to, duration)
	await tween.finished
	_finish()


# --- FAKE_OUT ------------------------------------------------------------------

func _start_fake_out() -> void:
	var player := get_player()
	var steps := randi_range(fake_step_count.x, fake_step_count.y)
	for i in steps:
		# Schritte wandern auf die Position dieses Punktes zu.
		var t := float(i) / maxf(steps - 1, 1)
		var pos := global_position
		if player:
			pos = global_position.lerp(player.global_position, 0.25 * t)
			pos.y = global_position.y
		play_sound_at(step_sound, pos, -2.0, 25.0)
		await get_tree().create_timer(randf_range(fake_step_interval.x, fake_step_interval.y)).timeout
	if randf() < fake_creak_chance:
		play_sound_at(creak_sound, global_position, 0.0)
		await get_tree().create_timer(randf_range(0.5, 1.2)).timeout
	if randf() < fake_roar_chance:
		play_sound_at(roar_sound, global_position, -4.0, 30.0)
	_finish()
