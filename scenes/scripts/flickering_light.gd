extends OmniLight3D
## Unregelmaessiges Flackern fuer eine defekte Deckenlampe im Wohnhaus.
## Wechselt zwischen stabilem (aber nie ganz ruhigem) Leuchten, kurzen
## Aussetzern und schnellen Flacker-Schueben.

@export_group("Helligkeit")
## Grundhelligkeit der Lampe (wird mit dem Level multipliziert).
@export var base_energy: float = 2.2
## Minimaler Level im eingeschalteten Zustand (0 = komplett aus).
@export var min_on_level: float = 0.45

## Zufaelliges Dauerflackern an/aus (force_flicker() und fail() gehen immer).
@export var random_flicker: bool = false

@export_group("Timing")
@export var min_steady_time: float = 1.0
@export var max_steady_time: float = 5.0
@export var min_blackout_time: float = 0.12
@export var max_blackout_time: float = 1.3
@export var min_burst_time: float = 0.25
@export var max_burst_time: float = 1.5

@export_group("Optik")
## Emissives Material des Leuchtkoerpers. Wird mit dem Lichtlevel mitgezogen.
@export var fixture_material: StandardMaterial3D
## Emissionsstaerke des Leuchtkoerpers bei vollem Level.
@export var fixture_emission_when_on: float = 3.0

var _rng := RandomNumberGenerator.new()
var _state_time: float = 0.0
var _burst_time: float = 0.0
var _burst_active: bool = false
var _level: float = 1.0

## Erzwungenes heftiges Flackern (z.B. beim Start des Generators).
var _distress_time: float = 0.0
var _is_in_distress: bool = false
var _base_energy: float = 0.0

## Dauerhaft ausgefallen (z.B. nachdem der Spieler das erste Item genommen hat).
var _failed: bool = false


func _ready() -> void:
	add_to_group("ceiling_lights")
	_rng.randomize()
	_base_energy = base_energy
	_enter_steady()


## Laesst das Licht fuer die angegebene Dauer heftig und unregelmaessig flackern.
## Wird z.B. vom Generator ausgeloest.
func force_flicker(duration: float = 2.0) -> void:
	if _failed:
		return
	_distress_time = duration
	_is_in_distress = true


## Schaltet die Lampe dauerhaft aus (z.B. wenn die Stromversorgung kollabiert).
## Die Lampe reagiert danach nicht mehr auf force_flicker().
func fail() -> void:
	if _failed:
		return
	_failed = true
	_is_in_distress = false
	_burst_active = false
	_state_time = 0.0
	_level = 0.0
	_apply_level(0.0)
	set_process(false)


func _process(delta: float) -> void:
	# Erzwungenes Flackern hat Vorrang vor dem normalen Zufallsverhalten.
	if _is_in_distress:
		_distress_time -= delta
		if _distress_time <= 0.0:
			_is_in_distress = false
			_level = _rng.randf_range(min_on_level, 1.0)
			_enter_steady()
		else:
			# Harte Spruenge: haeufiger komplett aus, dazwischen grell.
			var roll := _rng.randf()
			if roll < 0.55:
				_level = 0.0
			elif roll < 0.8:
				_level = _rng.randf_range(min_on_level, 1.0)
			else:
				# kurzzeitige Ueberhelligkeit fuer den "Kurzschluss"-Look
				_level = _rng.randf_range(1.0, 1.35)
		_apply_level(_level)
		return

	# Zufaelliges Flackern ist abgeschaltet -> Lampe leuchtet stabil.
	if not random_flicker:
		_level = 1.0
		_apply_level(_level)
		return

	if _burst_active:
		_burst_time -= delta
		if _burst_time <= 0.0:
			_burst_active = false
			_level = _rng.randf_range(min_on_level, 1.0)
		else:
			# Schnelle, unregelmaessige Spruenge zwischen aus und fast voll.
			_level = 0.0 if _rng.randf() < 0.45 else _rng.randf_range(min_on_level, 1.0)
		_apply_level(_level)
		return

	_state_time -= delta
	if _state_time <= 0.0:
		var roll := _rng.randf()
		if roll < 0.28:
			_enter_blackout()
		elif roll < 0.62:
			_enter_burst()
		else:
			_enter_steady()
	else:
		# Leichtes Zittern, damit das Licht nie wirklich ruhig wirkt.
		_level = clampf(_level + _rng.randf_range(-0.04, 0.04), min_on_level, 1.0)

	_apply_level(_level)


func _enter_steady() -> void:
	_state_time = _rng.randf_range(min_steady_time, max_steady_time)
	_level = _rng.randf_range(min_on_level, 1.0)


func _enter_blackout() -> void:
	_state_time = _rng.randf_range(min_blackout_time, max_blackout_time)
	_level = 0.0


func _enter_burst() -> void:
	_burst_active = true
	_burst_time = _rng.randf_range(min_burst_time, max_burst_time)
	_level = _rng.randf_range(min_on_level, 1.0)


func _apply_level(level: float) -> void:
	light_energy = _base_energy * level
	if fixture_material:
		fixture_material.emission_energy_multiplier = fixture_emission_when_on * level
