class_name HouseAmbience
extends Node
## Haus-Atmosphaere: Ambient-Loop plus zufaelliges 3D-Holzknarzen im Umkreis
## von 6-15 m um den Spieler, alle 12-35 Sekunden.
##
## Hinweis: horror_main.gd startet bereits eine eigene Raum-Ambience. Wird
## dieser Knoten zusaetzlich verwendet, `play_loop` ausschalten (oder die
## Ambience in horror_main abschalten), sonst laeuft der Loop doppelt.

@export_group("Loop")
@export var play_loop: bool = true
## Leer = assets/audio/ambient_sound.wav (siehe GameAudio).
@export var ambient_stream: AudioStream
@export_range(-60.0, 6.0, 0.5) var loop_volume_db: float = -14.0
@export var loop_fade_in: float = 4.0

@export_group("Knarzen")
## Leer = assets/audio/wooden_creak.wav.
@export var creak_stream: AudioStream
## Abstand zwischen zwei Geraeuschen (Sekunden).
@export var creak_interval: Vector2 = Vector2(12.0, 35.0)
## Entfernung zum Spieler (Meter).
@export var creak_distance: Vector2 = Vector2(6.0, 15.0)
@export var creak_height: Vector2 = Vector2(0.2, 2.6)
@export_range(-30.0, 6.0, 0.5) var creak_volume_db: float = -4.0
@export var creak_pitch: Vector2 = Vector2(0.8, 1.15)

var _loop_player: AudioStreamPlayer
var _timer: Timer


func _ready() -> void:
	var bus := &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"

	if play_loop:
		var stream := ambient_stream if ambient_stream else GameAudio.single("house_ambience", true)
		if stream:
			_loop_player = AudioStreamPlayer.new()
			_loop_player.name = "AmbientLoop"
			_loop_player.stream = stream
			_loop_player.bus = bus
			_loop_player.volume_db = -60.0
			add_child(_loop_player)
			_loop_player.play()
			var tween := create_tween()
			tween.tween_property(_loop_player, "volume_db", loop_volume_db, maxf(loop_fade_in, 0.01))

	if creak_stream == null:
		creak_stream = GameAudio.group("house_creak")

	_timer = Timer.new()
	_timer.name = "CreakTimer"
	_timer.one_shot = true
	_timer.timeout.connect(_on_creak_timer)
	add_child(_timer)
	_schedule_next()


func _schedule_next() -> void:
	_timer.start(randf_range(creak_interval.x, creak_interval.y))


func _on_creak_timer() -> void:
	_play_creak()
	_schedule_next()


func _play_creak() -> void:
	var player := get_tree().get_first_node_in_group("Player") as Node3D
	if player == null or creak_stream == null:
		return
	var angle := randf() * TAU
	var distance := randf_range(creak_distance.x, creak_distance.y)
	var offset := Vector3(cos(angle) * distance, randf_range(creak_height.x, creak_height.y), sin(angle) * distance)

	var source := AudioStreamPlayer3D.new()
	source.stream = creak_stream
	source.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	source.volume_db = creak_volume_db
	source.pitch_scale = randf_range(creak_pitch.x, creak_pitch.y)
	source.max_distance = creak_distance.y * 2.5
	source.unit_size = 5.0
	add_child(source)
	source.global_position = player.global_position + offset
	source.finished.connect(source.queue_free)
	source.play()
