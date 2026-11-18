extends CogitoPlayerSimple
## Horror-Anpassung des COGITO-Simple-Players für horror_main.tscn.
##
## Der Simple-Player ist der Basis-Player des Spiels. Für das Horror-Gameplay
## werden hier zwei Dinge nachgeschärft:
##
##   - Springen ist komplett aus, damit der Spieler nicht auf Möbel klettern
##     und das Monster austricksen kann. Zusätzlich ist die "jump"-Action in
##     project.godot ohne Belegung.
##   - Das HUD ist auf ein Minimum reduziert: keine Health/Stamina/Sanity-
##     Balken und kein dauerhaftes Fadenkreuz. Sobald ein interaktives Objekt
##     angeschaut wird, erscheinen ein dezentes Fadenkreuz sowie Objektname
##     und [E]-Hinweis.

## Deckkraft des Interaktions-Fadenkreuzes (1.0 = volle Deckkraft).
const CROSSHAIR_OPACITY: float = 0.65

## HUD-Knoten, die im Horror-Modus dauerhaft ausgeblendet bleiben.
const HIDDEN_HUD_NODES := [
	"FixedStaminaBar",
	"FixedOxygenBar",
	"MarginContainer_BottomUI/PlayerAttributes",
]

## Kamera-Sichtfeld (Grad): Gehen und Sprinten. Weites FOV gegen das Enge-Gefuehl.
const FOV_WALK: float = 85.0
const FOV_SPRINT: float = 90.0
## Wie schnell das FOV zwischen Gehen und Sprinten ueberblendet (1/s).
const FOV_BLEND_SPEED: float = 6.0

## Schrittbasierte Fussschritte: Strecke (m) pro Schritt je Bewegungsart und
## Lautstaerke (dB). Der Sound kommt aus assets/audio/footsteps_player.wav.
const STEP_STRIDE_WALK: float = 1.45
const STEP_STRIDE_SPRINT: float = 2.0
const STEP_STRIDE_CROUCH: float = 1.1
const STEP_VOLUME_WALK_DB: float = -23.0
const STEP_VOLUME_SPRINT_DB: float = -17.0
const STEP_VOLUME_CROUCH_DB: float = -33.0
## Unter dieser Horizontalgeschwindigkeit (m/s) gibt es keine Schritte.
const STEP_MIN_SPEED: float = 0.4

## Render-Layer, die nur die Spiegelkamera sieht (siehe haunted_mirror.gd).
const MIRROR_ONLY_LAYER: int = 2

## Von Startmenue und Endscreens gesetzt: sperrt saemtliche Spieler-Eingaben.
var ui_input_locked: bool = false

## Die Datei footsteps_player.wav hat ~0,5 s leises Vorspiel vor dem eigentlichen
## Tritt; die Wiedergabe startet erst hier (s), damit der Schritt nicht hinterherhinkt.
const STEP_START_OFFSET: float = 0.48

## Untergrund-Sounds: Gruppe des Colliders -> {key, offset, gain_db}. Ohne Gruppe
## (Haus, Keller, Veranda) gilt Holz. Offset = Beginn des Tritts in der Datei,
## gain_db gleicht die unterschiedlich leisen Dateien an Holz an (Pegel gemessen).
const SURFACES := {
	&"surface_grass": {"key": "footstep_grass", "offset": 0.44, "gain_db": 14.0},
	&"surface_asphalt": {"key": "footstep_asphalt", "offset": 0.49, "gain_db": 9.0},
}

var _step_player: AudioStreamPlayer
var _step_distance: float = 0.0
var _wood_stream: AudioStream
var _surface_streams: Dictionary = {}


func _ready() -> void:
	# Jump-Eingabe endgültig entfernen. CogitoGameConfig lädt beim Start
	# gespeicherte Tastenbelegungen (user://options.cfg) und könnte sonst
	# eine alte Space-/Gamepad-Belegung wiederherstellen.
	if InputMap.has_action("jump"):
		InputMap.action_erase_events("jump")

	# Sicherheitsnetz zusätzlich zur unbelegten "jump"-Action: Auch ein per
	# Neubelegung zurückgeholter Jump-Input löst keinen Sprung aus.
	jumping_enabled = false

	# Langsamere Bewegung (Horror-Tempo). Das hilft auch auf der Kellertreppe,
	# weil der Spieler pro Physik-Tick weniger weit ueber die Rampe laeuft.
	WALKING_SPEED = 2.8
	SPRINTING_SPEED = 4.6
	CROUCHING_SPEED = 1.6

	# Treppe: Der Spieler soll auf der Rampe "kleben" (Boden-Snap), steile
	# Rampen (35 Grad) als Boden erkennen und beim Hochlaufen nicht gebremst
	# werden. Fallschaden erst bei echten Stuerzen (> ca. 6 m), nicht wenn man
	# kurz in der Luft ist.
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	floor_stop_on_slope = true
	fall_damage_threshold = -12.0
	super._ready()
	_apply_minimal_hud()
	_setup_footsteps()
	if camera:
		camera.fov = FOV_WALK
		# Erscheinungen auf dem Spiegel-Layer sind fuer den Spieler unsichtbar.
		camera.cull_mask &= ~(1 << (MIRROR_ONLY_LAYER - 1))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if camera:
		var target_fov: float = FOV_SPRINT if is_sprinting else FOV_WALK
		camera.fov = lerpf(camera.fov, target_fov, clampf(FOV_BLEND_SPEED * delta, 0.0, 1.0))
	_update_footsteps(delta)


## Eigene schrittbasierte Fussschritte. Sind keine player_footstep_NN-Dateien
## vorhanden, bleibt das COGITO-Fussschrittsystem unveraendert aktiv.
func _setup_footsteps() -> void:
	var stream := GameAudio.single("footsteps_player")
	if stream == null:
		return
	_step_player = AudioStreamPlayer.new()
	_step_player.name = "HorrorFootsteps"
	_step_player.stream = stream
	_wood_stream = stream
	for group in SURFACES:
		var s := GameAudio.single(SURFACES[group]["key"])
		if s != null:
			_surface_streams[group] = s
	_step_player.max_polyphony = 3
	_step_player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master"
	add_child(_step_player)
	# COGITO-Fussschritte stummschalten, damit nichts doppelt klingt.
	walk_volume_db = -80.0
	crouch_volume_db = -80.0
	sprint_volume_db = -80.0


## Zaehlt die zurueckgelegte Strecke und spielt pro Schritt einen Sound.
func _update_footsteps(delta: float) -> void:
	if _step_player == null:
		return
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if ui_input_locked or not is_on_floor() or horizontal < STEP_MIN_SPEED:
		# Beim Losgehen kommt der erste Schritt nach der halben Strecke.
		_step_distance = minf(_step_distance, STEP_STRIDE_WALK * 0.5)
		return

	var stride := STEP_STRIDE_WALK
	var volume := STEP_VOLUME_WALK_DB
	if is_crouching:
		stride = STEP_STRIDE_CROUCH
		volume = STEP_VOLUME_CROUCH_DB
	elif is_sprinting:
		stride = STEP_STRIDE_SPRINT
		volume = STEP_VOLUME_SPRINT_DB

	_step_distance += horizontal * delta
	if _step_distance >= stride:
		_step_distance = 0.0
		var offset := STEP_START_OFFSET
		var gain := 0.0
		var group := _surface_group()
		if group != &"" and _surface_streams.has(group):
			_step_player.stream = _surface_streams[group]
			offset = SURFACES[group]["offset"]
			gain = SURFACES[group]["gain_db"]
		else:
			_step_player.stream = _wood_stream
		_step_player.volume_db = volume + gain
		_step_player.pitch_scale = randf_range(0.92, 1.08)
		_step_player.play(offset)


## Gruppe "surface_*" des Colliders unter den Fuessen; leer = Holz-Standard.
func _surface_group() -> StringName:
	var query := PhysicsRayQueryParameters3D.create(
			global_position, global_position + Vector3.DOWN * 2.0)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return &""
	var collider := hit["collider"] as Node
	for group in SURFACES:
		if collider != null and collider.is_in_group(group):
			return group
	return &""


## Solange Startmenue, Game-Over- oder Sieg-Screen aktiv sind, werden alle
## Spieler-Eingaben verworfen (Inventar, Pause-Menue, Interaktion). Sonst
## koennte z.B. Tab das Inventar oeffnen und beim Schliessen den Spieler
## freigeben und die Maus fangen.
func on_input(event):
	if ui_input_locked:
		return
	super.on_input(event)


func _apply_minimal_hud() -> void:
	if player_hud == null:
		return

	# Kein Dauer-Fadenkreuz: Das HUD blendet es erst ein, wenn die
	# Interaktions-Ray ein interaktives Objekt im Fokus hat.
	player_hud.default_crosshair = null
	player_hud.previous_crosshair_texture = null
	player_hud.crosshair_texture.texture = null
	player_hud.crosshair.modulate.a = CROSSHAIR_OPACITY

	# COGITO-Statusbalken ausblenden. Die Knoten bleiben instanziert, damit
	# Schadens-Vignette und Game-Over-Screen weiterhin verdrahtet sind.
	for path in HIDDEN_HUD_NODES:
		var node := player_hud.get_node_or_null(path)
		if node:
			node.visible = false
