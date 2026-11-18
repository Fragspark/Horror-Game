extends StaticBody3D
## Hausgenerator im Hauswirtschaftsraum.
##
## Der Spieler betankt den Generator mit dem Benzinkanister. Erst dann springt
## er an: Statuslicht wechselt von Rot auf Gruen, das Brumm-Loop-Geraeusch
## startet, die Deckenlampen flackern heftig und die Hintertuer wird entriegelt.
## Zusaetzlich wird das globale Signal GameEvents.generator_started ausgeloest.


## Wird vom HUD als Objektname ueber dem Interaktions-Prompt gelesen.
@export var display_name: String = "Hausgenerator"

## Lokales Signal (fuer die Hauptszene).
signal power_restored

## Vom BasicInteraction-Component erwartet (Prompt-Text aktualisieren).
signal object_state_updated(interaction_text: String)

@export_group("Texte")
@export var interaction_text_when_off: String = "Betanken & starten"
@export var interaction_text_when_on: String = "Läuft"
@export var success_hint: String = "Der Generator läuft. Die Hintertür ist entriegelt."
@export var missing_fuel_hint: String = "Kein Treibstoff. Ich brauche einen Benzinkanister."
## Anzeigename des benoetigten Items (muss dem "name" im Item-Resource entsprechen).
@export var fuel_item_name: String = "Benzinkanister"
## Wenn true, wird der Kanister beim Betanken aus dem Inventar entfernt.
@export var consume_fuel: bool = true

@export_group("Referenzen")
## Statuslicht: Rot, solange der Generator aus ist.
@export var status_light_path: NodePath
## Mesh des Statuslaempchens (wird mit umgefaerbt).
@export var status_lamp_path: NodePath
## Loop-Geraeusch, das beim Start abgespielt wird.
@export var hum_player_path: NodePath

@export_group("Optik")
@export var color_off: Color = Color(1, 0.14902, 0.117647, 1)
@export var color_on: Color = Color(0.301961, 1, 0.415686, 1)
@export var energy_off: float = 1.4
@export var energy_on: float = 2.4

@export_group("Effekte")
## Wie lange die Deckenlampen beim Start heftig flackern.
@export var flicker_duration: float = 2.0

var is_on: bool = false
var interaction_nodes: Array[Node] = []
var _basic_interaction: Node = null

@onready var _status_light: OmniLight3D = get_node_or_null(status_light_path) as OmniLight3D
@onready var _status_lamp: Node3D = get_node_or_null(status_lamp_path) as Node3D
@onready var _hum_player: AudioStreamPlayer3D = get_node_or_null(hum_player_path) as AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("interactable")
	find_interaction_nodes()
	# Das Statuslaempchen zeigt Rot, solange der Generator stillsteht.
	_set_status_color(false)
	_setup_hum_loop()


## Weist den Generator-Loop zu (Endlosschleife, Einstellung zur Laufzeit,
## damit sie nicht von Import-Einstellungen abhaengt).
func _setup_hum_loop() -> void:
	if _hum_player == null:
		return

	_hum_player.stream = GameAudio.single("generator_loop", true)


func find_interaction_nodes() -> void:
	interaction_nodes = find_children("", "InteractionComponent", true)
	for node in interaction_nodes:
		if node.input_map_action == "interact":
			_basic_interaction = node
			break


## Wird vom PlayerInteractionComponent aufgerufen (E-Taste).
func interact(player_interaction_component) -> void:
	if is_on:
		return

	if not _player_has_fuel(player_interaction_component):
		if player_interaction_component and player_interaction_component.has_method("send_hint"):
			player_interaction_component.send_hint(null, missing_fuel_hint)
		return

	if consume_fuel:
		_consume_fuel(player_interaction_component)

	_start_generator()

	if player_interaction_component and player_interaction_component.has_method("send_hint"):
		player_interaction_component.send_hint(null, success_hint)


## Prueft, ob der Spieler den Benzinkanister im Inventar hat.
func _player_has_fuel(player_interaction_component) -> bool:
	if player_interaction_component == null:
		return false
	var inventory := _get_inventory(player_interaction_component)
	if inventory == null:
		return false
	return not inventory.find_slots(fuel_item_name).is_empty()


## Entfernt einen Kanister aus dem Inventar.
func _consume_fuel(player_interaction_component) -> void:
	var inventory := _get_inventory(player_interaction_component)
	if inventory == null:
		return
	var matched := inventory.find_slots(fuel_item_name)
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


## Schaltet den Generator ein und loest alle Folgereaktionen aus.
func _start_generator() -> void:
	is_on = true

	# Prompt verschwindet, weil set_interaction_prompts() deaktivierte
	# Komponenten ueberspringt.
	if _basic_interaction:
		_basic_interaction.is_disabled = true

	_set_status_color(true)

	if _hum_player and _hum_player.stream:
		_hum_player.play()

	_trigger_ceiling_flicker()

	object_state_updated.emit(interaction_text_when_on)
	power_restored.emit()
	GameEvents.generator_started.emit()


## Faerbt Statuslicht und Laempchen um.
func _set_status_color(active: bool) -> void:
	var col := color_on if active else color_off
	var energy := energy_on if active else energy_off

	if _status_light:
		_status_light.light_color = col
		_status_light.light_energy = energy
		_status_light.visible = true

	# Das Laempchen selbst UND eventuelle Kinder umfaerben. find_children()
	# durchsucht nur Kinder, deshalb das MeshInstance3D separat behandeln.
	var lamp_nodes: Array[GeometryInstance3D] = []
	if _status_lamp is GeometryInstance3D:
		lamp_nodes.append(_status_lamp)
	for child in _status_lamp.find_children("", "GeometryInstance3D", true, false):
		lamp_nodes.append(child)

	for geo in lamp_nodes:
		var material: Material = geo.get_surface_override_material(0)
		if material is StandardMaterial3D:
			(material as StandardMaterial3D).albedo_color = col
			(material as StandardMaterial3D).emission = col


## Laesst alle Deckenlampen im Haus kurz heftig flackern.
func _trigger_ceiling_flicker() -> void:
	var lights := get_tree().get_nodes_in_group("ceiling_lights")
	for node in lights:
		if node.has_method("force_flicker"):
			node.force_flicker(flicker_duration)
