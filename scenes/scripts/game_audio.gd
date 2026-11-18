class_name GameAudio
extends RefCounted
## Zentrale Anlaufstelle fuer alle echten Audio-Dateien aus assets/audio.
##
## Mehrteilige Gruppen (z. B. monster_step_01.wav, monster_step_02.wav, ...)
## werden automatisch gefunden und in einen AudioStreamRandomizer gepackt.
## Aktuell gibt es pro Typ nur eine Datei (siehe LEGACY_FILES); sobald
## nummerierte Varianten in assets/audio liegen, werden sie ohne Code-Aenderung
## verwendet. Die Legacy-Datei dient nur als Fallback, wenn keine nummerierte
## Variante existiert.

const AUDIO_DIR := "res://assets/audio/"
const EXTENSIONS: Array[String] = [".wav", ".ogg"]
const MAX_VARIATIONS := 32

## Tonhoehen-Streuung und Lautstaerke-Schwankung der Randomizer.
const RANDOM_PITCH := 1.08
const RANDOM_VOLUME_OFFSET_DB := 1.5

## Logischer Name -> aktuell vorhandene Einzeldatei (ohne Pfad).
const LEGACY_FILES := {
	"monster_step": "heavy_step.wav",
	"monster_breath": "monster_breathing.wav",
	"house_creak": "wooden_creak.wav",
	"door_creak": "wooden_creak.wav",
	"door_slam_scare": "door_slam.wav",
	"house_ambience": "ambient_sound.wav",
	"generator_loop": "generator.wav",
	"fuse_insert_spark": "circuit_breaker.wav",
	"exit_door_unlock_charge": "escape_door_unlock_after_6_seconds.wav",
	"caught_scare": "caught_scare.wav",
	"apparition_sting": "ghost_sting.wav",
	"chase_stinger": "short_vhilling_jumpscare.wav",
	# Horror-Director-Events (scripts/events/*): Roar und langsame Schritte.
	"monster_roar": "short_vhilling_jumpscare.wav",
	"monster_step_slow": "Heavy_slow_steps.wav",
}

static var _cache: Dictionary = {}


## Liefert einen AudioStreamRandomizer mit allen Varianten von `key`.
## Gibt null zurueck, wenn keine Datei existiert.
static func group(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]

	var randomizer: AudioStreamRandomizer = null
	for path in _find_paths(key):
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		if randomizer == null:
			randomizer = AudioStreamRandomizer.new()
			randomizer.random_pitch = RANDOM_PITCH
			randomizer.random_volume_offset_db = RANDOM_VOLUME_OFFSET_DB
		randomizer.add_stream(-1, stream, 1.0)

	if randomizer == null:
		push_warning("GameAudio: Keine Audio-Datei fuer '%s' gefunden." % key)
	_cache[key] = randomizer
	return randomizer


## Liefert den Einzel-Sound `key` direkt (ohne Randomizer). Mit `loop` wird
## er als Endlosschleife eingestellt (Ambience, Generator).
static func single(key: String, loop: bool = false) -> AudioStream:
	var paths := _find_paths(key)
	if paths.is_empty():
		push_warning("GameAudio: Keine Audio-Datei fuer '%s' gefunden." % key)
		return null

	var stream := load(paths[0]) as AudioStream
	if stream != null and loop:
		_enable_loop(stream)
	return stream


## Nummerierte Varianten (key_01 .. key_NN); ohne Treffer die Legacy-Datei.
static func _find_paths(key: String) -> Array[String]:
	var paths: Array[String] = []
	for i in range(1, MAX_VARIATIONS + 1):
		var found := ""
		for ext in EXTENSIONS:
			var candidate := "%s%s_%02d%s" % [AUDIO_DIR, key, i, ext]
			if ResourceLoader.exists(candidate):
				found = candidate
				break
		if found.is_empty():
			break
		paths.append(found)

	if paths.is_empty():
		for ext in EXTENSIONS:
			var plain := "%s%s%s" % [AUDIO_DIR, key, ext]
			if ResourceLoader.exists(plain):
				paths.append(plain)
				break

	if paths.is_empty() and LEGACY_FILES.has(key):
		var legacy := AUDIO_DIR + String(LEGACY_FILES[key])
		if ResourceLoader.exists(legacy):
			paths.append(legacy)
	return paths


static func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			var bytes_per_frame := (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) \
				* (2 if wav.stereo else 1)
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = wav.data.size() / bytes_per_frame
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
