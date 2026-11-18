@tool
class_name CeilingLamp
extends Node3D
## Deckenlampe mit SpotLight3D und emissivem Leuchtkoerper.
##
## Modi:
##   STEADY      gleichmaessiges Licht
##   FLICKERING  Licht flackert in unregelmaessigen Schueben
##   BROKEN_OFF  Lampe ist kaputt/aus (Leuchtkoerper dunkel, kein Licht)
##
## Der Modus ist im Inspector waehlbar und zur Laufzeit per set_mode() aenderbar
## (z. B. durch ein Horror-Event).

enum Mode { STEADY, FLICKERING, BROKEN_OFF }

signal mode_changed(new_mode: Mode)

@export var mode: Mode = Mode.STEADY:
	set(value):
		mode = value
		if is_node_ready():
			_apply_mode()
			mode_changed.emit(mode)

@export_group("Licht")
@export var light_color: Color = Color(1.0, 0.84, 0.6):
	set(value):
		light_color = value
		if is_node_ready():
			_apply_look()
@export_range(0.0, 16.0, 0.05) var light_energy: float = 2.4
@export_range(1.0, 20.0, 0.1) var light_range: float = 7.0
@export_range(10.0, 89.0, 1.0) var spot_angle: float = 72.0
@export_range(0.0, 8.0, 0.1) var emission_energy: float = 3.0

@export_group("Flackern")
## Pause zwischen zwei Flacker-Schueben (Sekunden).
@export var burst_pause: Vector2 = Vector2(1.5, 6.0)
## Anzahl der Helligkeitswechsel pro Schub.
@export var burst_flips: Vector2i = Vector2i(3, 9)
## Dauer eines einzelnen Wechsels (Sekunden).
@export var flip_time: Vector2 = Vector2(0.025, 0.14)

@onready var light: SpotLight3D = $Light
@onready var bulb: MeshInstance3D = $Bulb

var _bulb_material: StandardMaterial3D
var _intensity: float = 1.0
var _timer: float = 0.0
var _flips_left: int = 0


func _ready() -> void:
	# Eigenes Material je Instanz, damit sich die Lampen nicht gegenseitig beeinflussen.
	var shared := bulb.material_override as StandardMaterial3D
	_bulb_material = shared.duplicate() as StandardMaterial3D if shared else StandardMaterial3D.new()
	_bulb_material.emission_enabled = true
	bulb.material_override = _bulb_material
	_apply_mode()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or mode != Mode.FLICKERING:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if _flips_left > 0:
		_flips_left -= 1
		# Zufaellig zwischen aus, gedimmt und voll.
		_intensity = [0.0, 0.15, 0.5, 1.0][randi() % 4]
		_timer = randf_range(flip_time.x, flip_time.y)
		if _flips_left == 0:
			_intensity = 1.0
	else:
		_intensity = 1.0
		_flips_left = randi_range(burst_flips.x, burst_flips.y)
		_timer = randf_range(burst_pause.x, burst_pause.y)
	_apply_look()


func set_mode(new_mode: Mode) -> void:
	mode = new_mode


func _apply_mode() -> void:
	_flips_left = 0
	_timer = randf_range(0.2, burst_pause.y)
	_intensity = 0.0 if mode == Mode.BROKEN_OFF else 1.0
	_apply_look()


func _apply_look() -> void:
	if light == null or _bulb_material == null:
		return
	light.light_color = light_color
	light.light_energy = light_energy * _intensity
	light.spot_range = light_range
	light.spot_angle = spot_angle
	light.visible = _intensity > 0.01
	_bulb_material.emission = light_color
	_bulb_material.emission_energy_multiplier = emission_energy * _intensity
	var glow := 0.25 + 0.75 * _intensity
	_bulb_material.albedo_color = Color(0.2 + 0.8 * glow, 0.2 + 0.78 * glow, 0.18 + 0.6 * glow)
