extends CanvasLayer
## Dunkler Game-Over-Screen, wenn der Stalker den Spieler erwischt.
##
## Zeigt zuerst einen roten Bildschirm-Blitz (der eigentliche Schreck-Moment
## laeuft im Monster-Script) und danach den "DU WURDEST ERWISCHT"-Screen mit
## einem "Erneut versuchen"-Button. Der Screen laeuft auch bei pausiertem Tree,
## damit der Button weiterhin reagiert.

## Wird ausgeloest, wenn der Spieler erneut versuchen will.
signal retry_requested

const UIStyle = preload("res://scenes/scripts/ui_style.gd")

@onready var _flash: ColorRect = %FlashOverlay
@onready var _dim: ColorRect = %Dim
@onready var _center: VBoxContainer = %Center
@onready var _retry_button: Button = %RetryButton
# Kein Unique-Name: "LocationButton" existiert in horror_main.tscn auch im Sieg-Screen.
@onready var _location_button: Button = $Center/LocationButton

var _shown: bool = false
var _flash_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_flash.visible = false
	_flash.modulate.a = 0.0
	_dim.visible = false
	_center.visible = false
	UIStyle.style_button(_retry_button, true, 22)
	UIStyle.style_button(_location_button, false, 22)
	_retry_button.pressed.connect(_on_retry_pressed)
	_location_button.pressed.connect(_on_location_pressed)


## Roter Vollbild-Blitz, der schnell wieder ausblendet.
func flash_red() -> void:
	# Schon ab dem Schreckmoment gilt: kein Inventar, keine Einstellungen.
	_lock_ui_input()

	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()

	_flash.visible = true
	_flash.modulate.a = 1.0

	_flash_tween = create_tween()
	_flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_callback(_hide_flash)


func _hide_flash() -> void:
	_flash.visible = false


## Blendet den dunklen Game-Over-Screen ein, gibt die Maus frei und pausiert.
func show_game_over() -> void:
	if _shown:
		return
	_shown = true

	_dim.visible = true
	_center.visible = true
	_dim.modulate.a = 0.0
	_center.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_dim, "modulate:a", 1.0, 0.4)
	tween.tween_property(_center, "modulate:a", 1.0, 0.4)

	_retry_button.grab_focus()
	_release_player_input()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


## Cogitos InputRouter laeuft trotz Pause weiter. Ohne diesen Schritt koennte
## ESC ein Pause-Menue ueber dem Game-Over-Screen oeffnen.
func _release_player_input() -> void:
	_lock_ui_input()
	var player := get_tree().get_first_node_in_group("Player")
	if player == null:
		return
	if "is_mouselook_active" in player:
		player.is_mouselook_active = false
	if player.has_method("pause_before_interaction"):
		player.pause_before_interaction()


## Sperrt Tab (Inventar) und F1 (Einstellungen), sobald der Spieler erwischt
## wurde. Sonst koennte ein Menue hinter dem Screen aufgehen und beim
## Schliessen die Maus fangen.
func _lock_ui_input() -> void:
	var settings := get_tree().get_first_node_in_group("simple_settings")
	if settings and settings.has_method("block_hotkey"):
		settings.block_hotkey()
	var player := get_tree().get_first_node_in_group("Player")
	if player:
		player.set("ui_input_locked", true)


## Zurueck zur Ortsauswahl im Hauptmenue.
func _on_location_pressed() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_retry_pressed() -> void:
	retry_requested.emit()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()
