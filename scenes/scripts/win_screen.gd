extends CanvasLayer
## Schlichter schwarzer Sieg-Screen.
##
## Haelt die Spielzeit an, gibt den Mauszeiger frei und blendet den
## "DU BIST ENTKOMMEN"-Text samt Zeit und Neustart-Button ein.

## Wird ausgeloest, wenn der Spieler "Neu starten" drueckt.
signal restart_requested

@onready var _time_label: Label = %TimeLabel
@onready var _restart_button: Button = %RestartButton
@onready var _location_button: Button = %LocationButton

## Laufzeit der aktuellen Partie in Sekunden.
var elapsed_seconds: float = 0.0
var _is_counting: bool = false
var _shown: bool = false


func _ready() -> void:
	visible = false
	_restart_button.pressed.connect(_on_restart_pressed)
	_location_button.pressed.connect(_on_location_pressed)


## Zurueck zur Ortsauswahl im Hauptmenue.
func _on_location_pressed() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## Startet die Zeitmessung (ab Beginn der Partie).
func start_timer() -> void:
	_is_counting = true


func _process(delta: float) -> void:
	if _is_counting:
		elapsed_seconds += delta


func show_win_screen() -> void:
	if _shown:
		return
	_shown = true

	_is_counting = false
	visible = true

	_time_label.text = "Benötigte Zeit: %s" % format_time(elapsed_seconds)

	_release_player_input()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


## Cogitos InputRouter laeuft trotz Pause weiter (PROCESS_MODE_ALWAYS) und ruft
## player.on_input() direkt auf. Ohne diesen Schritt wuerde ESC ein Pause-Menue
## ueber dem Sieg-Screen oeffnen und die Maus weiter gedreht werden.
func _release_player_input() -> void:
	# F1 (Einstellungen) sperren, solange der Sieg-Screen steht.
	var settings := get_tree().get_first_node_in_group("simple_settings")
	if settings and settings.has_method("block_hotkey"):
		settings.block_hotkey()

	var player := get_tree().get_first_node_in_group("Player")
	if player == null:
		return
	# Tab (Inventar) und alle weiteren Spieler-Eingaben sperren.
	player.set("ui_input_locked", true)
	if "is_mouselook_active" in player:
		player.is_mouselook_active = false
	if player.has_method("pause_before_interaction"):
		player.pause_before_interaction()


func _on_restart_pressed() -> void:
	restart_requested.emit()
	perform_restart()


## Laedt die Szene neu. get_tree().paused wird vorher aufgehoben, damit die
## neue Szene nicht sofort wieder pausiert.
func perform_restart() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


## Formatiert Sekunden als MM:SS.
static func format_time(total_seconds: float) -> String:
	var seconds := maxi(0, int(total_seconds))
	return "%02d:%02d" % [seconds / 60, seconds % 60]
