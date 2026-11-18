extends StaticBody3D
## Sicherungskasten neben der Fluchttuer.
##
## Nimmt zwei Sicherungen aus dem Inventar auf. Sind beide eingesetzt und
## liefert der Generator Strom, kann die Hintertuer entriegelt werden. Das
## eigentliche Entriegeln uebernimmt die Hauptszene, sobald sowohl
## "power_restored" als auch "fuses_installed" gemeldet wurden.

## Wird vom BasicInteraction-Component erwartet (Prompt-Text aktualisieren).
signal object_state_updated(interaction_text: String)
## Wird ausgeloest, sobald beide Sicherungen eingesetzt sind.
signal fuses_installed

## Wird vom HUD als Objektname ueber dem Interaktions-Prompt gelesen.
@export var display_name: String = "Sicherungskasten"

@export_group("Texte")
@export var interaction_text: String = "Sicherung einsetzen"
@export var all_installed_text: String = "Beide Sicherungen sitzen"
@export var no_fuse_hint: String = "Ich brauche eine Sicherung."
@export var first_fuse_hint: String = "Eine Sicherung sitzt. Es fehlt noch eine."
@export var installed_hint: String = "Beide Sicherungen sitzen. Die Hintertuer hat wieder Strom."
@export var installed_without_power_hint: String = "Beide Sicherungen sitzen. Jetzt fehlt noch der Strom."

@export_group("Verdrahtung")
## Name des Items im Inventar (muss dem "name" der Item-Ressource entsprechen).
@export var fuse_item_name: String = "Sicherung"
## So viele Sicherungen werden benoetigt.
@export_range(1, 4) var required_fuses: int = 2
## Kleine Leuchten, die pro eingesetzter Sicherung aufleuchten.
@export var indicator_paths: Array[NodePath] = []
## Licht, das den Kasten bei eingesetzten Sicherungen schwach beleuchtet.
@export var indicator_light_path: NodePath

var installed_count: int = 0
## Vom PlayerInteractionComponent erwartete Liste aller Interaktions-Komponenten.
var interaction_nodes: Array[Node] = []
var _basic_interaction: Node = null
var _indicator_light: OmniLight3D = null
var _power_on: bool = false
var _spark_player: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("interactable")
	find_interaction_nodes()
	_indicator_light = get_node_or_null(indicator_light_path) as OmniLight3D
	_setup_spark_audio()
	_refresh_visuals()

	if not GameEvents.generator_started.is_connected(_on_generator_started):
		GameEvents.generator_started.connect(_on_generator_started)


## Knisternder Funke beim Einsetzen einer Sicherung.
func _setup_spark_audio() -> void:
	_spark_player = AudioStreamPlayer3D.new()
	_spark_player.name = "SparkPlayer"
	_spark_player.stream = GameAudio.group("fuse_insert_spark")
	_spark_player.bus = &"SFX"
	_spark_player.volume_db = -14.0
	_spark_player.unit_size = 4.0
	_spark_player.max_distance = 30.0
	add_child(_spark_player)


## Sammelt die Child-Komponenten, damit der Spieler den Kasten als
## interagierbares Objekt erkennt.
func find_interaction_nodes() -> void:
	interaction_nodes = find_children("", "InteractionComponent", true)
	for node in interaction_nodes:
		if node.input_map_action == "interact":
			_basic_interaction = node
			break

	if _basic_interaction == null:
		_basic_interaction = get_node_or_null("BasicInteraction")


func _on_generator_started() -> void:
	_power_on = true


## Wird vom PlayerInteractionComponent aufgerufen (E-Taste).
func interact(player_interaction_component) -> void:
	if installed_count >= required_fuses:
		_send_hint(player_interaction_component, installed_hint)
		return

	if not _player_has_fuse(player_interaction_component):
		_send_hint(player_interaction_component, no_fuse_hint)
		return

	_consume_fuse(player_interaction_component)
	installed_count += 1
	if _spark_player and _spark_player.stream:
		_spark_player.play()
	_refresh_visuals()

	if installed_count >= required_fuses:
		# Kein weiterer Prompt mehr, der Kasten ist voll.
		if _basic_interaction:
			_basic_interaction.set("is_disabled", true)
		object_state_updated.emit(all_installed_text)
		_send_hint(
			player_interaction_component,
			installed_hint if _power_on else installed_without_power_hint
		)
		fuses_installed.emit()
	else:
		object_state_updated.emit(interaction_text)
		_send_hint(player_interaction_component, first_fuse_hint)


## Prueft, ob der Spieler eine Sicherung im Inventar hat.
func _player_has_fuse(player_interaction_component) -> bool:
	if player_interaction_component == null:
		return false
	var inventory := _get_inventory(player_interaction_component)
	if inventory == null:
		return false
	return not inventory.find_slots(fuse_item_name).is_empty()


## Entfernt eine Sicherung aus dem Inventar.
func _consume_fuse(player_interaction_component) -> void:
	var inventory := _get_inventory(player_interaction_component)
	if inventory == null:
		return
	var matched := inventory.find_slots(fuse_item_name)
	if matched.is_empty():
		return
	inventory.remove_slot_data(matched.front())


func _get_inventory(player_interaction_component) -> CogitoInventory:
	if player_interaction_component.has_method("get_inventory"):
		return player_interaction_component.get_inventory()
	var player: Node = player_interaction_component.get_parent()
	if player and "inventory_data" in player:
		return player.inventory_data
	return null


func _send_hint(player_interaction_component, text: String) -> void:
	if player_interaction_component == null:
		return
	if player_interaction_component.has_method("send_hint"):
		player_interaction_component.send_hint(null, text)


## Schaltet die kleinen Kontrollleuchten passend zur Anzahl der Sicherungen.
func _refresh_visuals() -> void:
	for i in indicator_paths.size():
		var indicator := get_node_or_null(indicator_paths[i]) as Node3D
		if indicator:
			indicator.visible = i < installed_count

	if _indicator_light:
		_indicator_light.visible = installed_count > 0
		_indicator_light.light_energy = 0.65 * float(installed_count)
