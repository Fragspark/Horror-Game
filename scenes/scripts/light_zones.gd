extends Node
## Schaltet Lampen ab, die vom aktuellen Aufenthaltsort des Spielers aus nicht
## zu sehen sind (Performance).
##
## Godot hat kein Occlusion Culling fuer Lichter: Jede schattenwerfende
## OmniLight3D im Sichtfeld rendert ihre Schattenkarte (6 Wuerfelseiten mit
## allen CSG-Teilen in Reichweite) neu, sobald sich der Spieler bewegt - auch
## Kellerlampen direkt unter dem Boden. Das hat im Bad/Schlafzimmer ueber
## 10.000 Draw-Calls pro Frame gekostet.
##
## Lampen werden ueber `visible` geschaltet statt nur den Schatten
## abzuschalten. Eine Lampe ohne Schatten wuerde durch Boden und Waende in
## andere Stockwerke leuchten.
##
## Zonen:
##   Keller-Lampen   an, wenn der Spieler im Keller ist oder im Bereich der
##                   Kellertreppe steht (von oben die Treppe hinunterschaut).
##   Erdgeschoss     aus, wenn der Spieler tief im Keller ist (ausser
##                   `always_on`, z. B. die Treppenhauslampe).
##   Obergeschoss    nicht begehbar; Lampen nur an, wenn der Spieler draussen
##                   ist und die beleuchteten Fenster sehen kann.

@export var player: Node3D

@export_group("Lampen")
@export var basement_lights: Array[Light3D] = []
@export var ground_lights: Array[Light3D] = []
@export var upper_lights: Array[Light3D] = []
## Erdgeschoss-Lampen, die auch aus dem Keller sichtbar sind (Treppenhaus).
@export var always_on: Array[Light3D] = []
## Mondlicht: im Haus guenstigerer Schatten (eine Stufe, kurze Distanz),
## draussen die Einstellungen aus der Szene. Ganz abschalten geht nicht, sonst
## scheint der Mond durch die Waende ins Haus.
@export var moon: DirectionalLight3D
@export var moon_indoor_max_distance: float = 20.0

@export_group("Zonen")
## Grundflaeche des Hauses (x/z), alles ausserhalb gilt als "draussen".
@export var house_bounds: AABB = AABB(Vector3(-9.2, -4.0, -11.4), Vector3(17.0, 12.0, 17.8))
## Bereich der Kellertreppe inkl. Flurtuer; hier sind Keller und Erdgeschoss
## gleichzeitig an.
@export var stair_zone: AABB = AABB(Vector3(-0.6, -3.2, -11.2), Vector3(3.2, 5.6, 7.9))
## Unterhalb dieser Hoehe (Fuesse des Spielers) ist er im Keller.
@export var basement_below_y: float = -1.2
## Pruefintervall in Sekunden.
@export var interval: float = 0.15
## Im Keller werfen nur die N naechsten Lampen Schatten, die uebrigen leuchten
## ohne Schatten weiter. Jede Schatten-Omni rendert ihre Schattenkarte mit allen
## CSG-Teilen in Reichweite neu, sobald sich der Spieler bewegt (Keller ohne
## Omni-Schatten: ~10.700 -> ~2.600 Draw-Calls).
@export var basement_shadow_count: int = 2

var _t: float = 0.0
var _zone: String = ""
var _shadow_set: Array = [null]  # != jedes echte Set, erzwingt erste Anwendung
var _basement_shadow_default: Dictionary = {}
var _moon_mode: DirectionalLight3D.ShadowMode
var _moon_distance: float


func _ready() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("Player") as Node3D
	if moon:
		_moon_mode = moon.directional_shadow_mode
		_moon_distance = moon.directional_shadow_max_distance
	for l in basement_lights:
		if l:
			_basement_shadow_default[l] = l.shadow_enabled
	_update(true)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = interval
	_update(false)


func _update(force: bool) -> void:
	if player == null:
		return
	var p := player.global_position
	var zone := "ground"
	if not house_bounds.has_point(p):
		zone = "outside"
	elif stair_zone.has_point(p):
		zone = "stairs"
	elif p.y < basement_below_y:
		zone = "basement"
	if zone == "basement" or zone == "stairs":
		_update_basement_shadows(p)
	if zone == _zone and not force:
		return
	_zone = zone
	if zone != "basement" and zone != "stairs":
		_restore_basement_shadows()

	_set_all(basement_lights, zone == "basement" or zone == "stairs")
	_set_all(ground_lights, zone != "basement")
	_set_all(upper_lights, zone == "outside")
	_set_all(always_on, true)

	if moon:
		var outside := zone == "outside"
		moon.directional_shadow_mode = _moon_mode if outside else DirectionalLight3D.SHADOW_ORTHOGONAL
		moon.directional_shadow_max_distance = _moon_distance if outside else moon_indoor_max_distance


## Schatten nur fuer die basement_shadow_count Lampen, die dem Spieler am naechsten sind.
func _update_basement_shadows(p: Vector3) -> void:
	var lights: Array = []
	for l in basement_lights:
		if l and _basement_shadow_default.get(l, false):
			lights.append(l)
	lights.sort_custom(func(a: Light3D, b: Light3D) -> bool:
		return a.global_position.distance_squared_to(p) < b.global_position.distance_squared_to(p))
	var nearest := lights.slice(0, maxi(basement_shadow_count, 0))
	if nearest == _shadow_set:
		return
	_shadow_set = nearest
	for l in lights:
		(l as Light3D).shadow_enabled = nearest.has(l)


func _restore_basement_shadows() -> void:
	if _shadow_set.is_empty():
		return
	_shadow_set = []
	for l in basement_lights:
		if l:
			l.shadow_enabled = _basement_shadow_default.get(l, l.shadow_enabled)


func _set_all(lights: Array[Light3D], on: bool) -> void:
	for l in lights:
		if l:
			l.visible = on


## Aktuelle Zone (fuer Debug/Tests).
func get_zone() -> String:
	return _zone
