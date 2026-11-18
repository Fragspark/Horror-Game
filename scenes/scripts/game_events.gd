extends Node
## Globaler Event-Bus fuer szenenuebergreifende Signale.
##
## Muss als Autoload registriert sein (siehe project.godot -> [autoload]).
## Andere Systeme koennen sich einfach verbinden:
##     GameEvents.generator_started.connect(_on_generator_started)

## Wird ausgeloest, sobald der Generator gestartet wurde und Strom liefert.
signal generator_started

## Wird ausgeloest, sobald der Spieler durch die Ausgangstuer entkommen ist.
signal player_escaped

## Wird ausgeloest, sobald der Spieler das erste wichtige Item aufnimmt
## (Schluessel, Benzinkanister oder eine der beiden Sicherungen).
signal first_item_collected
