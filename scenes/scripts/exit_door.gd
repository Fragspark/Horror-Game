extends CogitoDoor
## Hintertuer am Ende des Flurs (eigentlicher Fluchtweg).
##
## Solange Strom oder Sicherungen fehlen (Door ist gelockt), verweigert sie das
## Oeffnen und zeigt stattdessen einen Hinweis auf Generator und
## Sicherungskasten. Sobald beides vorhanden ist und die Tuer entriegelt wurde,
## verhaelt sie sich wie eine normale Cogito-Tuer. Der Sieg wird NICHT mehr beim
## Oeffnen ausgeloest, sondern erst, wenn der Spieler die Area3D direkt hinter
## der geoeffneten Tuer (escape_area_path) betritt, also wirklich draussen ist.

## Wird ausgeloest, sobald der Spieler bei offener Tuer nach draussen laeuft.
signal escaped

## Hinweis, der bei verschlossener Tuer angezeigt wird.
@export var locked_hint: String = "Die Hintertür ist verriegelt. Generator und Sicherungskasten müssen beide in Ordnung sein."
## Hinweis, waehrend das Sicherheitsschloss hochfaehrt.
@export var unlocking_hint: String = "Das Sicherheitsschloss fährt noch hoch…"
## Area3D direkt hinter der Tuer (ausserhalb des Hauses).
@export var escape_area_path: NodePath

## Wird von horror_main gesetzt, solange das Schloss hochfaehrt.
var is_unlocking: bool = false

## Verhindert, dass der Sieg mehrfach ausgeloest wird.
var _has_escaped: bool = false


func _ready() -> void:
	super._ready()
	var area := get_node_or_null(escape_area_path) as Area3D
	if area:
		area.body_entered.connect(_on_escape_area_body_entered)
	elif escape_area_path != NodePath():
		push_warning("ExitDoor: escape_area_path zeigt auf keine Area3D.")


## Ueberschreibt das Standardverhalten: bei verschlossener Tuer nur Hinweis,
## kein Aufschliessen per Schluessel.
func interact(interactor: Node3D) -> void:
	if is_locked:
		if interactor and interactor.has_method("send_hint"):
			interactor.send_hint(null, unlocking_hint if is_unlocking else locked_hint)
		return

	super.interact(interactor)


func _on_escape_area_body_entered(body: Node3D) -> void:
	if _has_escaped or is_locked or not is_open:
		return
	if not body.is_in_group("Player"):
		return

	_has_escaped = true
	GameEvents.player_escaped.emit()
	escaped.emit()
