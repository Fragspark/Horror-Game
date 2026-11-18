class_name HorrorEvent
extends Node3D
## Gemeinsame Basis aller Horror-Events (Tuer-Scare, Scare-Point, Eckenspaeher,
## Spiegel). Alles Wesentliche ist per @export im Inspector einstellbar, damit
## dieselben Szenen auf Map 2 mit einem anderen Modell (z. B. Kind) laufen:
## einfach `entity_scene` austauschen und die Animationsnamen anpassen.

## Szene des Wesens (Wurzel sollte MonsterEntity sein, siehe monster_entity.gd).
@export var entity_scene: PackedScene = preload("res://scenes/monster/distorted_wand.tscn")

@export_group("Director")
## Ab welcher Eskalationsphase das Event ausgeloest werden darf (1-3).
@export_range(1, 3) var required_phase: int = 1
## Wahrscheinlichkeit (0-1), mit der eine Anfrage beim Director gelingt.
@export_range(0.0, 1.0, 0.01) var chance: float = 0.5
## Name fuer die History des Directors. Leer = Name dieses Knotens.
@export var event_id: String = ""

@export_group("Animationen")
## Stehende Ausgangspose (wird im ersten Bild eingefroren).
@export var idle_animation: StringName = &"Zombie Scream"
## Reaktion/Schrei.
@export var react_animation: StringName = &"Zombie Scream"
## Fortbewegung/Rueckzug.
@export var crawl_animation: StringName = &"crawl_fixed"

@export_group("Sounds")
## Leer = automatisch aus assets/audio (siehe GameAudio / LEGACY_FILES).
@export var roar_sound: AudioStream
@export var step_sound: AudioStream
@export var creak_sound: AudioStream
@export var breath_sound: AudioStream
@export_range(-30.0, 6.0, 0.5) var sound_volume_db: float = 0.0


func _ready() -> void:
	if roar_sound == null:
		roar_sound = GameAudio.group("monster_roar")
	if step_sound == null:
		step_sound = GameAudio.group("monster_step")
	if creak_sound == null:
		creak_sound = GameAudio.group("house_creak")
	if breath_sound == null:
		breath_sound = GameAudio.single("monster_breath")


func get_event_id() -> String:
	return event_id if not event_id.is_empty() else String(name)


## Fragt den Director. Bei true laeuft sein globaler Cooldown.
func request_scare() -> bool:
	return HorrorDirector.request_scare(required_phase, chance, get_event_id())


func cancel_scare() -> void:
	HorrorDirector.cancel_scare(get_event_id())


func is_player(body: Node) -> bool:
	return body != null and body.is_in_group("Player")


func get_player() -> Node3D:
	return HorrorDirector.get_player()


func get_camera() -> Camera3D:
	return get_viewport().get_camera_3d()


## Gibt true zurueck, wenn der Punkt NICHT im Bild des Spielers liegt.
func is_out_of_view(world_pos: Vector3) -> bool:
	return not HorrorDirector.is_in_view(world_pos)


## Erzeugt das Wesen als Kind von `parent` an der Weltposition/-ausrichtung
## `xform`. Gibt null zurueck, wenn keine entity_scene gesetzt ist.
func spawn_entity(parent: Node, xform: Transform3D) -> Node3D:
	if entity_scene == null:
		push_warning("%s: keine entity_scene gesetzt." % name)
		return null
	var entity := entity_scene.instantiate() as Node3D
	parent.add_child(entity)
	entity.global_transform = xform
	return entity


## Wrapper: Methoden nur aufrufen, wenn die Wurzel ein MonsterEntity ist.
func entity_call(entity: Node, method: StringName, args: Array = []) -> Variant:
	if entity != null and is_instance_valid(entity) and entity.has_method(method):
		return entity.callv(method, args)
	return null


## Haengt einen VisibleOnScreenNotifier3D an das Wesen (Kameraerkennung).
func attach_notifier(entity: Node3D, aabb: AABB = AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.9, 0.8))) -> VisibleOnScreenNotifier3D:
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.name = "ScreenNotifier"
	notifier.aabb = aabb
	entity.add_child(notifier)
	return notifier


## true, wenn zwischen der Spielerkamera und `world_pos` nichts Solides liegt,
## geprueft mit einem RayCast3D (`ray` muss ein Kind dieser Szene sein).
func is_ray_clear(ray: RayCast3D, world_pos: Vector3) -> bool:
	var cam := get_camera()
	if cam == null or ray == null:
		return false
	ray.global_position = cam.global_position
	ray.target_position = ray.to_local(world_pos)
	ray.force_raycast_update()
	return not ray.is_colliding()


## Spielt einen Sound einmalig an einer Weltposition und raeumt danach auf.
func play_sound_at(stream: AudioStream, world_pos: Vector3, volume_db: float = 0.0,
		max_distance: float = 30.0) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = volume_db + sound_volume_db
	player.max_distance = max_distance
	player.unit_size = 6.0
	add_child(player)
	player.global_position = world_pos
	player.finished.connect(player.queue_free)
	player.play()
