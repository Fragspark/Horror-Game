extends CogitoDoor
## Haustuer an der Vorderseite des Hauses.
##
## Die Tuer ist von aussen passierbar. Sobald der Spieler den Flur betritt,
## faellt sie hinter ihm zu und verriegelt. Der eigentliche Fluchtweg bleibt
## die separate Hintertuer am Ende des Flurs, die erst nach dem Start des
## Generators entriegelt wird.

## Hinweis, wenn die Tuer bereits hinter dem Spieler verriegelt ist.
@export var locked_hint: String = "Die Haustür ist hinter mir ins Schloss gefallen."

## Hinweis, der beim Zufallen der Tuer eingeblendet wird.
@export var entered_hint: String = "Die Haustür fällt hinter mir zu – von außen verriegelt."

@export_group("Verdrahtung")
## Spieler-Node. Leer lassen, dann wird die Gruppe "Player" verwendet.
@export var player_path: NodePath

@export_group("Verriegelung")
## Bereich direkt hinter der Tuer (globale Koordinaten). Sobald der Spieler
## diesen Bereich betritt, wird die Tuer geschlossen und verriegelt.
@export var interior_area: AABB = AABB(Vector3(-1.25, 0.0, 2.8), Vector3(2.5, 3.0, 2.0))
## Gesamtes Hausinnere. Liegt der Spieler beim Verriegeln nicht mehr hier,
## wird der Vorgang abgebrochen (z.B. wenn er sofort wieder hinauslaeuft).
@export var house_area: AABB = AABB(Vector3(-9.2, 0.0, -12.3), Vector3(18.4, 3.2, 18.0))
## Verzoegerung, damit der Spieler den Tuerrahmen verlassen kann.
@export var lock_delay: float = 0.55

var _player: Node3D
var _has_entered: bool = false
var _is_locking: bool = false


func _ready() -> void:
	super._ready()
	_resolve_player()


func _process(_delta: float) -> void:
	if _has_entered or _player == null:
		return
	if interior_area.has_point(_player.global_position):
		_has_entered = true
		_lock_behind_player()


## Von aussen ist die Tuer offen; nach dem Verriegeln gibt sie nur noch einen
## Hinweis zurueck, statt sich erneut zu oeffnen.
func interact(interactor: Node3D) -> void:
	if is_locked:
		if interactor and interactor.has_method("send_hint"):
			interactor.send_hint(null, locked_hint)
		return

	super.interact(interactor)


func _resolve_player() -> void:
	if player_path != NodePath():
		_player = get_node_or_null(player_path) as Node3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("Player") as Node3D


func _lock_behind_player() -> void:
	if _is_locking:
		return
	_is_locking = true

	await get_tree().create_timer(lock_delay).timeout

	# Falls der Spieler doch wieder nach draussen gelaufen ist, nichts tun.
	if _player == null or not house_area.has_point(_player.global_position):
		_has_entered = false
		_is_locking = false
		return

	if is_open:
		close_door(_player)

	# Erst verriegeln, wenn die Tuer sichtbar zufaellt.
	await get_tree().create_timer(0.35).timeout
	is_locked = true
	lock_interaction_text = interaction_text_when_locked
	lock_state_changed.emit(true)
	lock_state_updated.emit(lock_interaction_text)
	object_state_updated.emit(interaction_text_when_locked)

	_send_hint(entered_hint)


func _send_hint(text: String) -> void:
	if _player == null or text.is_empty():
		return
	var interactor = _player.get_node_or_null("PlayerInteractionComponent")
	if interactor and interactor.has_method("send_hint"):
		interactor.send_hint(null, text)
