extends NavigationRegion3D
## Backt das NavMesh beim Spielstart neu.
##
## Die NavigationRegion3D sammelt ihre Quell-Geometrie aus der Gruppe
## "nav_source" (siehe navmesh_house.tres). Da inzwischen Keller, Obergeschoss
## und die beiden Treppen dazugekommen sind, wird das NavMesh nach dem
## Szenenstart einmal neu gebacken. So sind alle Ebenen und Treppen sicher
## verbunden, ohne dass das NavMesh von Hand gepflegt werden muss.
##
## Das Backen laeuft standardmaessig in einem Thread, damit der Spielstart
## nicht blockiert. Bis das neue Mesh fertig ist, bleibt das zuvor gebackene
## Mesh aktiv.

## Neu backen, sobald die Szene bereit ist.
@export var rebake_on_ready: bool = true
## Backen in einem Hintergrund-Thread (empfohlen).
@export var bake_on_thread: bool = true
## So viele Physik-Frames werden gewartet, damit CSG-Kollisionen der neuen
## Ebenen sicher erzeugt und registriert sind.
@export_range(0, 10) var wait_physics_frames: int = 5

var _has_baked: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if rebake_on_ready:
		_schedule_rebake()


## Startet das Neu-Backen nach einer kurzen Wartezeit.
func _schedule_rebake() -> void:
	for i in wait_physics_frames:
		await get_tree().physics_frame
	rebake()


## Backt das NavMesh mit den Einstellungen der zugewiesenen NavigationMesh-
## Ressource neu. Kann auch von aussen (z.B. nach Level-Aenderungen) gerufen
## werden.
func rebake() -> void:
	if navigation_mesh == null:
		push_warning("NavigationBaker: Keine NavigationMesh-Ressource zugewiesen.")
		return
	if is_baking():
		return

	if not bake_finished.is_connected(_on_bake_finished):
		bake_finished.connect(_on_bake_finished)

	_has_baked = false
	bake_navigation_mesh(bake_on_thread)


## Wird vom Bake-Prozess ausgeloest, sobald das neue Mesh bereit ist.
func _on_bake_finished() -> void:
	_has_baked = true


## True, sobald mindestens ein Bake-Vorgang abgeschlossen wurde.
func has_baked() -> bool:
	return _has_baked
