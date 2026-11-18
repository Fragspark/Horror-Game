extends Node
## Zentraler Horror-Director (Autoload "HorrorDirector").
##
## Statt einer berechenbaren Monster-KI entscheidet dieser Director, OB und
## WANN ein Schreck-Event (Tuer-Scare, Eckenspaeher, Spiegel ...) ausgeloest
## werden darf. Events fragen mit request_scare() an; der Director beachtet
##   - die aktuelle Eskalationsphase,
##   - einen globalen Zufalls-Cooldown nach jedem Event,
##   - eine History, damit sich Event-Typen nicht direkt wiederholen,
##   - und wuerfelt die uebergebene Wahrscheinlichkeit.

## Wird ausgeloest, wenn sich die Phase aendert.
signal phase_changed(new_phase: int)
## Wird ausgeloest, wenn ein Event freigegeben wurde.
signal scare_approved(event_id: String)

const PHASE_SUBTLE := 1
const PHASE_PRESENCE := 2
const PHASE_ESCALATION := 3

## Zufalls-Cooldown nach jedem freigegebenen Event (Sekunden).
const COOLDOWN_MIN := 45.0
const COOLDOWN_MAX := 90.0
## Wie viele zuletzt ausgeloeste Event-Typen gemerkt werden.
const HISTORY_SIZE := 5
## Anzahl der letzten Eintraege, in denen sich eine event_id NICHT wiederholen
## darf (1 = nur nicht direkt hintereinander).
const NO_REPEAT_WINDOW := 1
## Kurze Schonfrist nach Spielstart, bevor das erste Event kommen darf.
const INITIAL_GRACE_MIN := 20.0
const INITIAL_GRACE_MAX := 40.0

## 1 = Subtil, 2 = Praesenz, 3 = Eskalation.
var current_phase: int = PHASE_SUBTLE

var _cooldown_left: float = 0.0
var _history: Array[String] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_cooldown_left = _rng.randf_range(INITIAL_GRACE_MIN, INITIAL_GRACE_MAX)

	# Spielfortschritt treibt die Eskalation: erstes Item -> Praesenz,
	# Generator laeuft -> Eskalation.
	var events := get_node_or_null("/root/GameEvents")
	if events:
		if events.has_signal("first_item_collected"):
			events.first_item_collected.connect(advance_phase)
		if events.has_signal("generator_started"):
			events.generator_started.connect(advance_phase)


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)


## Erhoeht die Eskalationsphase um eins (max. 3). Fuer Spielfortschritt.
func advance_phase() -> void:
	set_phase(current_phase + 1)


## Setzt die Phase direkt (wird auf 1..3 begrenzt).
func set_phase(phase: int) -> void:
	var clamped := clampi(phase, PHASE_SUBTLE, PHASE_ESCALATION)
	if clamped == current_phase:
		return
	current_phase = clamped
	phase_changed.emit(current_phase)


## Fragt ein Event an. Gibt true zurueck, wenn es jetzt stattfinden darf.
## Bei true laeuft sofort der globale Cooldown und die event_id landet in der
## History. Ein Event, das doch nicht stattfinden kann, ruft cancel_scare().
func request_scare(min_phase: int, chance: float, event_id: String = "generic") -> bool:
	if current_phase < min_phase:
		return false
	if _cooldown_left > 0.0:
		return false
	if _recently_used(event_id):
		return false

	# Hoehere Phasen machen Events leicht wahrscheinlicher (+10 % pro Phase
	# ueber der Mindestphase), damit die Eskalation spuerbar bleibt.
	var phase_bonus := 1.0 + 0.1 * float(current_phase - min_phase)
	if _rng.randf() > clampf(chance * phase_bonus, 0.0, 1.0):
		return false

	_history.append(event_id)
	while _history.size() > HISTORY_SIZE:
		_history.pop_front()
	_cooldown_left = _rng.randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
	scare_approved.emit(event_id)
	return true


## Nimmt eine Freigabe zurueck, wenn das Event gar nicht stattgefunden hat
## (z. B. Spieler hat den Raum verlassen, bevor die Figur spawnen konnte).
func cancel_scare(event_id: String) -> void:
	var idx := _history.rfind(event_id)
	if idx >= 0:
		_history.remove_at(idx)
	_cooldown_left = 0.0


## Verkuerzt/verlaengert den Cooldown manuell (z. B. nach einer Verfolgungsjagd).
func set_cooldown(seconds: float) -> void:
	_cooldown_left = maxf(0.0, seconds)


func get_cooldown_left() -> float:
	return _cooldown_left


func get_history() -> Array[String]:
	return _history.duplicate()


## Setzt Phase, Cooldown und History zurueck (neuer Durchlauf).
func reset() -> void:
	current_phase = PHASE_SUBTLE
	_history.clear()
	_cooldown_left = _rng.randf_range(INITIAL_GRACE_MIN, INITIAL_GRACE_MAX)
	phase_changed.emit(current_phase)


func _recently_used(event_id: String) -> bool:
	var start := maxi(0, _history.size() - NO_REPEAT_WINDOW)
	for i in range(start, _history.size()):
		if _history[i] == event_id:
			return true
	return false


# ---------------------------------------------------------------------------
# Hilfsfunktionen fuer die Event-Szenen
# ---------------------------------------------------------------------------

## Der Spieler (Gruppe "Player") oder null.
func get_player() -> Node3D:
	return get_tree().get_first_node_in_group("Player") as Node3D


## Die aktive Kamera des Spielers (oder null).
func get_camera() -> Camera3D:
	return get_viewport().get_camera_3d()


## true, wenn `world_pos` im Sichtfeld des Spielers liegt (Frustum, ohne
## Verdeckungspruefung).
func is_in_view(world_pos: Vector3) -> bool:
	var cam := get_camera()
	return cam != null and cam.is_position_in_frustum(world_pos)


## true, wenn zwischen Kamera und `world_pos` nichts Solides liegt.
## `exclude` sind zusaetzliche Koerper, die ignoriert werden (z. B. Spieler).
func has_line_of_sight(world_pos: Vector3, exclude: Array[RID] = [], mask: int = 1) -> bool:
	var cam := get_camera()
	if cam == null:
		return false
	var space := cam.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(cam.global_position, world_pos, mask)
	var ex: Array[RID] = exclude.duplicate()
	var player := get_player()
	if player is CollisionObject3D:
		ex.append((player as CollisionObject3D).get_rid())
	query.exclude = ex
	return space.intersect_ray(query).is_empty()
