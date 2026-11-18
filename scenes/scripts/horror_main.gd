extends Node3D
## Verdrahtet den Spiel-Loop des Hauses:
##   Generator starten -> zwei Sicherungen in den Kasten neben der Fluchttuer
##   setzen -> entkommen -> Sieg-Screen.
##
## Zusaetzlich startet die Szene ihre Hintergrund-Ambience und
## verteilt Schluessel, Benzinkanister und die beiden Sicherungen bei jedem
## Start an zufaelligen Orten in Erdgeschoss, Keller und Obergeschoss.
##
## Der Aussenbereich (Node "Outdoor") liegt bewusst NICHT in der Gruppe
## "nav_source". Die NavigationRegion3D backt ihr NavMesh beim Start aus der
## Haus-Geometrie neu und deckt damit nur das Hausinnere ab; das Monster kann
## dem Spieler nicht nach draussen folgen.

@onready var _generator: Node = %GeneratorConsole
@onready var _exit_door: Node = %ExitDoor
@onready var _utility_door: Node = $Doors/UtilityRoomDoor
@onready var _fuse_panel: Node = %FusePanel
@onready var _win_screen: CanvasLayer = %WinScreen
@onready var _settings: CanvasLayer = %SimpleSettings
@onready var _player: Node = $Player
@onready var _room_hum: AudioStreamPlayer = $RoomHum
@onready var _pickups: Array[Node3D] = [
	$Pickups/KeyPickup,
	$Pickups/FuelCanPickup,
	$Pickups/FusePickupA,
	$Pickups/FusePickupB,
]
@onready var _spawn_groups: Array[Node3D] = [
	$ItemSpawnPoints/Key,
	$ItemSpawnPoints/FuelCan,
	$ItemSpawnPoints/FuseA,
	$ItemSpawnPoints/FuseB,
]

@export_group("Zufaellige Item-Spawns")
## Verteilt Schluessel, Kanister und Sicherungen beim Szenenstart neu.
@export var randomize_item_spawns: bool = true
## Hoehe ueber dem Marker, in der der Schluessel abgelegt wird.
## Die Pickups sind eingefroren (keine Physik), daher muss die Hoehe exakt
## passen, damit sie nicht in der Luft schweben.
@export var key_spawn_height: float = 0.0
## Hoehe ueber dem Marker, in der der Benzinkanister abgelegt wird.
@export var fuel_can_spawn_height: float = 0.23
## Hoehe ueber dem Marker, in der eine Sicherung abgelegt wird.
@export var fuse_spawn_height: float = 0.08
## Maximale zufaellige Drehung um die Y-Achse (Grad).
@export_range(0.0, 360.0) var spawn_yaw_range_deg: float = 360.0

@export_group("Raum-Ambience")
## Ziel-Lautstaerke der Raum-Ambience.
@export var room_hum_volume_db: float = -22.0
## Dauer des Einblendens beim Szenenstart.
@export var room_hum_fade_in: float = 5.0
## Zeitfenster zwischen zwei zufaelligen 3D-Hausgeraeuschen (Sekunden).
@export var house_noise_interval: Vector2 = Vector2(20.0, 40.0)
## Lautstaerke der Hausgeraeusche.
@export var house_noise_volume_db: float = -6.0
## Mindestabstand zum Spieler, damit das Geraeusch "irgendwo im Haus" klingt.
@export var house_noise_min_distance: float = 5.0
## Hoehe der Schallquelle ueber dem Boden-Marker.
@export var house_noise_height: float = 1.4

@export_group("Erstes Item")
## So lange flackern die Erdgeschoss-Deckenlampen, bevor sie ausfallen.
@export var first_item_flicker_time: float = 1.2
## Verzoegerung bis zum endgueltigen Ausfall (sollte >= Flicker-Dauer sein).
@export var first_item_blackout_delay: float = 1.4

@export_group("Finale")
## Dauer des Hochfahrens des Sicherheitsschlosses der Hintertuer.
@export var exit_unlock_duration: float = 6.0
## Ziel des alarmierten Monsters relativ zur Hintertuer (Innenseite des Hauses).
@export var exit_monster_target_offset: Vector3 = Vector3(0.5, 0.0, 1.5)
## So lange sucht das Monster am Laermort.
@export var exit_monster_search_duration: float = 12.0
@export var exit_power_up_volume_db: float = -4.0

var _spawn_rng := RandomNumberGenerator.new()
var _first_item_collected: bool = false
var _power_restored: bool = false
var _fuses_installed: bool = false
var _finale_started: bool = false
var _finale_time_left: float = 0.0
var _finale_label: Label
var _finale_audio: AudioStreamPlayer3D
var _house_noise_player: AudioStreamPlayer3D
var _house_noise_timer: float = 0.0
var _house_noise_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_generator.power_restored.connect(_on_power_restored)
	_exit_door.escaped.connect(_on_escaped)

	if _fuse_panel and _fuse_panel.has_signal("fuses_installed"):
		_fuse_panel.fuses_installed.connect(_on_fuses_installed)

	_connect_item_pickups()
	_spawn_rng.randomize()
	_start_room_hum()
	_setup_door_audio()
	_setup_house_noises()
	_randomize_item_spawns()
	_start_game()


func _process(delta: float) -> void:
	_update_house_noises(delta)

	if _finale_time_left > 0.0:
		_finale_time_left = maxf(_finale_time_left - delta, 0.0)
		if _finale_label:
			_finale_label.text = "Sicherheitsschloss fährt hoch…  %d" % ceili(_finale_time_left)


func _on_power_restored() -> void:
	_power_restored = true
	_unlock_utility_room_door()
	_try_unlock_exit_door()


## Mit laufendem Generator faellt auch das Schloss der Vorratskammer. So kann
## das Monster auf seiner Patrouille alle Stockwerke erreichen, ohne an der
## verschlossenen Seitentuer haengen zu bleiben.
func _unlock_utility_room_door() -> void:
	if _utility_door == null:
		return

	if _utility_door.is_locked:
		if _utility_door.has_method("unlock_door"):
			_utility_door.unlock_door()
		else:
			_utility_door.is_locked = false

	# Das Schliess-Komponente wird stillgelegt, damit die Vorratskammer nicht
	# wieder verriegelt werden kann. Sonst koennte die Monster-Patrouille auf
	# dem Weg ins Obergeschoss an der Tuer haengen bleiben.
	var lock_component := _utility_door.get_node_or_null("LockInteraction")
	if lock_component:
		lock_component.set("is_disabled", true)


func _on_fuses_installed() -> void:
	_fuses_installed = true
	_try_unlock_exit_door()


## Die Fluchttuer braucht Strom UND beide Sicherungen. Sind beide Bedingungen
## erfuellt, faehrt das Sicherheitsschloss erst hoch (Finale).
func _try_unlock_exit_door() -> void:
	if not (_power_restored and _fuses_installed):
		return
	if _finale_started or _exit_door == null or not _exit_door.is_locked:
		return

	_finale_started = true
	_run_exit_finale()


## 6 Sekunden Hochfahren mit Geraeusch und HUD-Hinweis; das Monster wird vom
## Laerm zur Hintertuer gelockt. Danach entriegelt die Tuer hoerbar.
func _run_exit_finale() -> void:
	_exit_door.set("is_unlocking", true)
	_finale_time_left = exit_unlock_duration
	_show_finale_label()
	_send_player_hint("Sicherheitsschloss fährt hoch…")

	_finale_audio = AudioStreamPlayer3D.new()
	_finale_audio.bus = &"SFX"
	_finale_audio.max_distance = 80.0
	_finale_audio.unit_size = 14.0
	_finale_audio.volume_db = exit_power_up_volume_db
	# Die Datei enthaelt Hochfahren UND das Einrasten nach ca. 6 Sekunden.
	_finale_audio.stream = GameAudio.single("exit_door_unlock_charge")
	add_child(_finale_audio)
	_finale_audio.global_position = (_exit_door as Node3D).global_position + Vector3(0.0, 1.2, 0.0)
	_finale_audio.play()

	await get_tree().create_timer(exit_unlock_duration).timeout

	_finale_time_left = 0.0
	if _finale_label:
		_finale_label.queue_free()
		_finale_label = null
	_exit_door.set("is_unlocking", false)

	if _exit_door.has_method("unlock_door"):
		_exit_door.unlock_door()
	else:
		_exit_door.is_locked = false

	# Der Sound laeuft weiter und endet von selbst mit dem Entriegeln.
	_send_player_hint("Die Hintertür ist entriegelt!")


func _send_player_hint(text: String) -> void:
	var component = _player.get("player_interaction_component") if _player else null
	if component and component.has_method("send_hint"):
		component.send_hint(null, text)


## Dauerhafter HUD-Hinweis mit Countdown waehrend des Hochfahrens.
func _show_finale_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = 70.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(0.95, 0.32, 0.2))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.text = "Sicherheitsschloss fährt hoch…"
	layer.add_child(label)
	_finale_label = label
	# Beim Entfernen des Labels auch die Ebene aufraeumen.
	label.tree_exited.connect(layer.queue_free)


func _on_escaped() -> void:
	_win_screen.show_win_screen()


## Die Szene startet ohne Menue direkt im Spiel (das Hauptmenue ist
## scenes/main_menu.tscn): Maus gefangen, Spieler aktiv, Timer laeuft.
func _start_game() -> void:
	get_tree().paused = false
	_settings.menu_mode = false
	var player_camera := _player.get_node_or_null("Body/Neck/Head/Eyes/Camera") as Camera3D
	if player_camera:
		player_camera.make_current()
	if _player:
		_player.set("ui_input_locked", false)
	_win_screen.start_timer()
	# Verzoegert, damit kein anderer _ready()-Code die Maus wieder freigibt.
	_capture_mouse.call_deferred()


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED



#region Erstes Item

## Verbindet alle wichtigen Pickups mit der Eskalation des Spiels.
func _connect_item_pickups() -> void:
	for pickup in _pickups:
		if pickup == null:
			continue

		var component := pickup.get_node_or_null("PickupComponent")
		if component == null or not component.has_signal("was_interacted_with"):
			push_warning("HorrorMain: PickupComponent fehlt an %s." % pickup.name)
			continue

		if not component.is_connected("was_interacted_with", _on_item_picked_up):
			component.connect("was_interacted_with", _on_item_picked_up)


## Sobald das erste wichtige Item aufgenommen wurde, sterben die Deckenlampen
## im Erdgeschoss und das Monster wird schneller.
func _on_item_picked_up(_interaction_text: String, _input_map_action: String) -> void:
	if _first_item_collected:
		return

	_first_item_collected = true
	GameEvents.first_item_collected.emit()
	_blackout_ground_floor_lights()


## Laesst die Erdgeschoss-Deckenlampen erst heftig flackern und schaltet sie
## anschliessend dauerhaft ab.
func _blackout_ground_floor_lights() -> void:
	var lights := get_tree().get_nodes_in_group("ground_floor_lights")

	for node in lights:
		if node.has_method("force_flicker"):
			node.force_flicker(first_item_flicker_time)

	if first_item_blackout_delay > 0.0:
		await get_tree().create_timer(first_item_blackout_delay).timeout

	for node in lights:
		if node.has_method("fail"):
			node.fail()

#endregion


#region Raum-Ambience und Hausgeraeusche

## Startet die Raum-Ambience als Endlosschleife und blendet sie langsam ein.
func _start_room_hum() -> void:
	if _room_hum == null:
		return

	_room_hum.stream = GameAudio.single("house_ambience", true)
	if _room_hum.stream == null:
		return
	_room_hum.volume_db = -60.0
	_room_hum.play()

	if room_hum_fade_in > 0.0:
		var tween := create_tween()
		tween.tween_property(_room_hum, "volume_db", room_hum_volume_db, room_hum_fade_in)
	else:
		_room_hum.volume_db = room_hum_volume_db


## Tueren knarren beim Oeffnen; die Haustuer faellt mit einem Knall zu.
func _setup_door_audio() -> void:
	var creak := GameAudio.group("door_creak")
	var slam := GameAudio.group("door_slam_scare")
	for node in find_children("*", "CogitoDoor", true, false):
		var door := node as CogitoDoor
		if creak:
			door.open_sound = creak
			door.close_sound = creak
			door.rattle_sound = creak
		if slam and door.get_script() == preload("res://scenes/scripts/front_door.gd"):
			door.close_sound = slam


## Legt den 3D-Player fuer zufaellige Hausgeraeusche an.
func _setup_house_noises() -> void:
	_house_noise_rng.randomize()
	_house_noise_player = AudioStreamPlayer3D.new()
	_house_noise_player.name = "HouseNoisePlayer"
	_house_noise_player.bus = &"SFX"
	_house_noise_player.unit_size = 7.0
	_house_noise_player.max_distance = 40.0
	_house_noise_player.volume_db = house_noise_volume_db
	add_child(_house_noise_player)
	_reset_house_noise_timer()


func _reset_house_noise_timer() -> void:
	_house_noise_timer = _house_noise_rng.randf_range(
		house_noise_interval.x, house_noise_interval.y
	)


## Spielt alle 20-40 s ein Geraeusch (Knarzen oder Tuerknall) an einer
## zufaelligen Raumposition, die nicht direkt neben dem Spieler liegt.
func _update_house_noises(delta: float) -> void:
	if _house_noise_player == null:
		return

	_house_noise_timer -= delta
	if _house_noise_timer > 0.0:
		return
	_reset_house_noise_timer()

	var positions: Array[Vector3] = []
	var player_pos := (_player as Node3D).global_position if _player is Node3D else Vector3.ZERO
	var markers := get_node_or_null("MonsterPatrolPoints")
	if markers:
		for child in markers.get_children():
			if child is Node3D:
				var pos := (child as Node3D).global_position
				if pos.distance_to(player_pos) >= house_noise_min_distance:
					positions.append(pos)
	if positions.is_empty():
		return

	var stream := GameAudio.group(
		"door_slam_scare" if _house_noise_rng.randf() < 0.25 else "house_creak"
	)
	if stream == null:
		return
	_house_noise_player.stream = stream
	_house_noise_player.global_position = (
		positions[_house_noise_rng.randi_range(0, positions.size() - 1)]
		+ Vector3(0.0, house_noise_height, 0.0)
	)
	_house_noise_player.play()

#endregion


#region Zufaellige Item-Spawns

## Waehlt fuer jedes wichtige Item einen anderen zufaelligen Marker aus seiner
## eigenen Markergruppe. Jede Gruppe enthaelt vier Punkte, verteilt auf
## Erdgeschoss, Keller und Obergeschoss.
func _randomize_item_spawns() -> void:
	if not randomize_item_spawns:
		return

	var heights: Array[float] = [
		key_spawn_height,
		fuel_can_spawn_height,
		fuse_spawn_height,
		fuse_spawn_height,
	]

	for i in _spawn_groups.size():
		var group := _spawn_groups[i]
		if group == null or i >= _pickups.size():
			continue

		var markers: Array[Node3D] = []
		for child in group.get_children():
			if child is Node3D:
				markers.append(child as Node3D)

		if markers.size() < 4:
			push_warning(
				"HorrorMain: %s hat nur %d Spawn-Marker (4 erwartet)."
				% [group.name, markers.size()]
			)

		if markers.is_empty():
			continue

		var marker := markers[_spawn_rng.randi_range(0, markers.size() - 1)]
		_place_pickup(_pickups[i], marker, heights[i])


## Setzt ein Pickup auf einen Marker und dreht es zufaellig um die Y-Achse.
func _place_pickup(pickup: Node3D, marker: Node3D, height: float) -> void:
	if pickup == null or marker == null:
		return

	pickup.global_position = marker.global_position + Vector3(0.0, height, 0.0)
	var yaw := marker.global_rotation.y + deg_to_rad(
		_spawn_rng.randf_range(-spawn_yaw_range_deg * 0.5, spawn_yaw_range_deg * 0.5)
	)
	pickup.global_rotation = Vector3(0.0, yaw, 0.0)

#endregion
