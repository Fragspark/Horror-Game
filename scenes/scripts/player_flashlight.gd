extends SpotLight3D
## Taschenlampe, die von Spielbeginn an am Player-Head befestigt ist.
## Umschalten mit der Input-Action "flashlight" (Standard: L).

@export_group("Verhalten")
## Ist die Lampe beim Start bereits an?
@export var start_on: bool = true
## Input-Map-Action zum Ein-/Ausschalten.
@export var toggle_action: String = "flashlight"

@export_group("Licht")
## Grundhelligkeit bei eingeschalteter Lampe.
@export var base_energy: float = 6.0
## Wie stark die Helligkeit minimal schwankt (0 = komplett ruhig).
@export var energy_jitter: float = 0.35
## Intervall, in dem ein neuer Jitter-Wert gewuerfelt wird.
@export var jitter_interval_min: float = 0.08
@export var jitter_interval_max: float = 0.7

@export_group("Nahbereich")
## Ab dieser Entfernung zur angestrahlten Flaeche beginnt die Lampe zu dimmen.
@export var proximity_fade_distance: float = 2.0
## Bei dieser Entfernung (oder naeher) ist die Lampe am staerksten gedimmt.
@export var proximity_min_distance: float = 0.4
## Minimale Helligkeit direkt vor einer Wand (0.12 = 12 %).
@export_range(0.0, 1.0, 0.01) var proximity_min_factor: float = 0.12
## Wie schnell die Nahbereichs-Daempfung nachzieht.
@export var proximity_response: float = 8.0
## Physik-Layer, die fuer die Naehepruefung als Wand/Objekt zaehlen.
@export_flags_3d_physics var occlusion_mask: int = 1

var _is_on: bool = false
var _rng := RandomNumberGenerator.new()
var _jitter_time: float = 0.0
var _jitter_offset: float = 0.0
var _proximity_factor: float = 1.0
var _player_rid: RID
var _has_player_rid: bool = false


func _ready() -> void:
	_rng.randomize()
	var player := get_tree().get_first_node_in_group("Player") as CollisionObject3D
	if player:
		_player_rid = player.get_rid()
		_has_player_rid = true
	set_on(start_on)


func set_on(value: bool) -> void:
	_is_on = value
	visible = value
	_jitter_offset = 0.0
	light_energy = base_energy * _proximity_factor
	_jitter_time = 0.0


func is_on() -> bool:
	return _is_on


func toggle() -> void:
	set_on(not _is_on)


## Bewusst _input statt _unhandled_input, damit die Lampe auch dann
## reagiert, wenn ein UI-Control den Tastendruck abfaengt.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action):
		toggle()


func _process(delta: float) -> void:
	if not _is_on:
		return

	_jitter_time -= delta
	if _jitter_time <= 0.0:
		_jitter_time = _rng.randf_range(jitter_interval_min, jitter_interval_max)
		_jitter_offset = _rng.randf_range(-energy_jitter, energy_jitter)

	_update_proximity_factor(delta)
	light_energy = (base_energy + _jitter_offset) * _proximity_factor


## Dimmt die Lampe, wenn eine Wand oder ein Objekt sehr nah vor dem Strahl liegt.
## Verhindert die ueberstrahlten, grellen Flaechen beim Anlehnen an eine Wand.
func _update_proximity_factor(delta: float) -> void:
	var target := 1.0
	var space := get_world_3d().direct_space_state
	var origin := global_position
	var forward := -global_transform.basis.z
	var exclude: Array[RID] = []
	if _has_player_rid:
		exclude.append(_player_rid)
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + forward * proximity_fade_distance,
		occlusion_mask,
		exclude
	)

	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var distance := origin.distance_to(hit.position)
		var span := maxf(proximity_fade_distance - proximity_min_distance, 0.01)
		var t := clampf((distance - proximity_min_distance) / span, 0.0, 1.0)
		target = lerpf(proximity_min_factor, 1.0, t)

	_proximity_factor = lerpf(
		_proximity_factor,
		target,
		clampf(delta * proximity_response, 0.0, 1.0)
	)
