extends CanvasLayer
## Bewusst einfaches, provisorisches Einstellungsmenue (F1).
##
## Buendelt die wichtigsten Steuerungs-Optionen an einer Stelle, statt sie
## ueber Cogitos verschachteltes Options-Menue zu verteilen:
##   - Maus-Empfindlichkeit
##   - Y-Achse invertieren
##   - Ducken umschalten (Toggle statt Halten)
##   - Headbob
##   - Tastenbelegung der wichtigsten Aktionen (Klick -> Taste druecken)
##
## Aenderungen werden sofort auf den Player angewandt und beim Schliessen in
## user://options.cfg gespeichert.

## Wird nach dem Schliessen des Menues (und dem Speichern) gesendet.
signal closed

const MIGRATION_KEY := "simplified_controls_v2"

## Index von "1600x900 (16:9)" in CogitoGameConfig.RESOLUTION_DICTIONARY.
const DEFAULT_RESOLUTION_INDEX := 11

## Aktion -> Anzeigename fuer die Tastenbelegung.
const BINDABLE_ACTIONS := [
	["forward", "Vorwärts"],
	["back", "Rückwärts"],
	["left", "Links"],
	["right", "Rechts"],
	["crouch", "Ducken"],
	["sprint", "Sprinten"],
	["interact", "Interagieren"],
	["interact2", "Sekundär (Schloss)"],
	["flashlight", "Taschenlampe"],
	["inventory", "Inventar"],
	["menu", "Pause"],
]

## Standardbelegung fuer den "Standardwerte"-Knopf.
const DEFAULT_BINDINGS := {
	"forward": KEY_W,
	"back": KEY_S,
	"left": KEY_A,
	"right": KEY_D,
	"crouch": KEY_C,
	"sprint": KEY_SHIFT,
	"interact": KEY_E,
	"interact2": KEY_F,
	"flashlight": KEY_L,
	"inventory": KEY_TAB,
	"menu": KEY_ESCAPE,
}

const HEADBOB_VALUES := [0, 1, 3, 7]
const HEADBOB_LABELS := ["Aus", "Minimal", "Normal", "Stark"]

const DEFAULT_SENSITIVITY := 0.25

var _root: Control
var _sensitivity_slider: HSlider
var _sensitivity_label: Label
var _invert_check: CheckBox
var _toggle_crouch_check: CheckBox
var _headbob_option: OptionButton
var _bind_buttons: Dictionary = {}
var _scroll: ScrollContainer
var _hint_label: Label
var _awaiting_action: String = ""
var _awaiting_button: Button = null
var _player: Node = null
var _has_been_opened: bool = false

## Aus dem Startmenue heraus geoeffnet: Beim Schliessen bleibt der Mauszeiger
## sichtbar und der Spieler eingefroren, und der F1-Hinweis bleibt versteckt.
## Solange menu_mode aktiv ist, oeffnet F1 das Menue nicht (nur der Knopf im
## Startmenue).
var menu_mode: bool = false:
	set(value):
		menu_mode = value
		_update_hint_visibility()

## Von Game-Over- und Sieg-Screen gesetzt: F1 oeffnet das Menue nicht mehr.
var hotkey_blocked: bool = false


func _ready() -> void:
	# Befehls-Prioritaet: laeuft auch, wenn das Spiel pausiert ist.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	add_to_group("simple_settings")
	_player = get_tree().get_first_node_in_group("Player")

	_migrate_controls_once()
	_build_ui()
	_update_panel_height()
	_sync_from_config()
	_set_open(false)

	# Nach dem kompletten Szenenstart erneut anwenden: der Player liest seine
	# Optionen in _ready() selbst aus der Config und wuerde unsere Werte sonst
	# je nach Node-Reihenfolge ueberschreiben.
	_apply_to_player.call_deferred()


## Einmalige Korrektur unsinniger Alt-Defaults (Y invertiert, Crouch-Toggle).
## Laeuft nur beim ersten Start dieses Panels und ist ueber "Standardwerte"
## jederzeit rueckgaengig zu machen.
func _migrate_controls_once() -> void:
	var cfg := CogitoGameConfig
	if cfg == null or cfg.config == null:
		return
	if cfg.config.has_section_key(OptionsConstants.section_name, MIGRATION_KEY):
		return

	cfg.invert_y = false
	cfg.toggle_crouching = false
	cfg.headbob_strength = 1

	# Alt-Configs starten auf 800x600 (Index 0). Auf eine zeitgemaesse
	# Fenstergroesse anheben, sofern noch die winzige Aufloesung aktiv ist.
	if cfg.current_resolution_index == 0:
		cfg.current_resolution_index = DEFAULT_RESOLUTION_INDEX
		cfg.fullscreen_mode = false
		_apply_window_size.call_deferred()

	cfg.config.set_value(OptionsConstants.section_name, MIGRATION_KEY, 1)
	cfg.save_options()


func _apply_window_size() -> void:
	var window := get_window()
	window.size = Vector2i(1600, 900)
	window.content_scale_size = Vector2i.ZERO


#region UI-Aufbau
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)

	# Aussen: Scrollbereich (flexibel) + fester Footer. So bleiben die
	# Schaltflaechen auch bei kleiner Aufloesung immer erreichbar.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(680, 420)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)
	get_viewport().size_changed.connect(_update_panel_height)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	_scroll.add_child(vbox)

	var title := Label.new()
	title.text = "EINSTELLUNGEN"
	title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "F1 oder Esc zum Schließen – Änderungen gelten sofort."
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())
	_add_sensitivity_row(vbox)
	_add_checkbox_row(vbox, "Y-Achse invertieren", func(pressed: bool): _on_invert_toggled(pressed))
	_add_checkbox_row(vbox, "Ducken umschalten (statt halten)", func(pressed: bool): _on_toggle_crouch(pressed))
	_add_headbob_row(vbox)

	vbox.add_child(HSeparator.new())
	var bind_title := Label.new()
	bind_title.text = "TASTENBELEGUNG"
	bind_title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(bind_title)

	var bind_hint := Label.new()
	bind_hint.text = "Knopf anklicken, dann die neue Taste drücken. Esc bricht ab."
	bind_hint.add_theme_font_size_override("font_size", 13)
	bind_hint.modulate = Color(1, 1, 1, 0.6)
	vbox.add_child(bind_hint)

	# Zwei Spaltenpaare nebeneinander, damit die Liste kompakt bleibt.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)
	for entry in BINDABLE_ACTIONS:
		_add_bind_row(grid, entry[0], entry[1])

	outer.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(buttons)

	var reset_button := Button.new()
	reset_button.text = "Standardwerte"
	reset_button.custom_minimum_size = Vector2(150, 40)
	reset_button.pressed.connect(_on_reset_pressed)
	buttons.add_child(reset_button)

	var close_button := Button.new()
	close_button.text = "Speichern & Schließen"
	close_button.custom_minimum_size = Vector2(190, 40)
	close_button.pressed.connect(func(): _set_open(false))
	buttons.add_child(close_button)

	# Dezenter Dauer-Hinweis, damit das Menue auffindbar ist.
	# Achtung: haengt absichtlich NICHT an _root, sonst verschwindet er mit dem Menue.
	var hint_root := Control.new()
	hint_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hint_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_root)

	_hint_label = Label.new()
	_hint_label.text = "F1 – Einstellungen"
	_hint_label.add_theme_font_size_override("font_size", 14)
	_hint_label.modulate = Color(1, 1, 1, 0.35)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint_label.offset_left = -190
	_hint_label.offset_top = -38
	_hint_label.offset_right = -18
	_hint_label.offset_bottom = -14
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_root.add_child(_hint_label)


func _add_sensitivity_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = "Maus-Empfindlichkeit"
	label.custom_minimum_size = Vector2(240, 0)
	row.add_child(label)

	_sensitivity_slider = HSlider.new()
	_sensitivity_slider.min_value = 0.03
	_sensitivity_slider.max_value = 1.5
	_sensitivity_slider.step = 0.01
	_sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sensitivity_slider.custom_minimum_size = Vector2(180, 34)
	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	row.add_child(_sensitivity_slider)

	_sensitivity_label = Label.new()
	_sensitivity_label.custom_minimum_size = Vector2(46, 0)
	_sensitivity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_sensitivity_label)


func _add_checkbox_row(parent: Control, text: String, on_toggled: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.toggled.connect(on_toggled)
	parent.add_child(check)
	if text.begins_with("Y-Achse"):
		_invert_check = check
	else:
		_toggle_crouch_check = check
	return check


func _add_headbob_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label := Label.new()
	label.text = "Headbob (Kopfwippen)"
	label.custom_minimum_size = Vector2(240, 0)
	row.add_child(label)

	_headbob_option = OptionButton.new()
	_headbob_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in HEADBOB_LABELS.size():
		_headbob_option.add_item(HEADBOB_LABELS[i], HEADBOB_VALUES[i])
	_headbob_option.item_selected.connect(_on_headbob_selected)
	row.add_child(_headbob_option)


func _add_bind_row(parent: Control, action: String, display_name: String) -> void:
	var label := Label.new()
	label.text = display_name
	label.custom_minimum_size = Vector2(130, 0)
	parent.add_child(label)

	var button := Button.new()
	button.custom_minimum_size = Vector2(92, 32)
	button.pressed.connect(func(): _start_rebind(action, button))
	parent.add_child(button)
	_bind_buttons[action] = button
	_refresh_bind_button(action)


## Begrenzt die Panelhoehe auf die Fensterhoehe, damit der Schliessen-Knopf
## auch bei kleinen Aufloesungen erreichbar bleibt.
func _update_panel_height() -> void:
	if _scroll == null:
		return
	var window_height := get_viewport().get_visible_rect().size.y
	# Platz fuer Titel/Footer/Abstaende freihalten.
	_scroll.custom_minimum_size.y = clampf(window_height - 210.0, 240.0, 680.0)


func _refresh_bind_button(action: String) -> void:
	var button: Button = _bind_buttons.get(action)
	if button == null:
		return
	if action == _awaiting_action:
		button.text = "Taste drücken …"
		return
	var event := InputHelper.get_keyboard_input_for_action(action)
	button.text = InputHelper.get_label_for_input(event) if event else "—"
#endregion


#region Werte <-> UI
func _sync_from_config() -> void:
	if _sensitivity_slider:
		_sensitivity_slider.set_value_no_signal(CogitoGameConfig.mouse_sens)
		_update_sensitivity_label(CogitoGameConfig.mouse_sens)
	if _invert_check:
		_invert_check.set_pressed_no_signal(CogitoGameConfig.invert_y)
	if _toggle_crouch_check:
		_toggle_crouch_check.set_pressed_no_signal(CogitoGameConfig.toggle_crouching)
	if _headbob_option:
		var idx := HEADBOB_VALUES.find(CogitoGameConfig.headbob_strength)
		_headbob_option.select(0 if idx == -1 else idx)
	for action in _bind_buttons.keys():
		_refresh_bind_button(action)


func _update_sensitivity_label(value: float) -> void:
	if _sensitivity_label:
		_sensitivity_label.text = "%.2f" % value


func _on_sensitivity_changed(value: float) -> void:
	CogitoGameConfig.mouse_sens = value
	_update_sensitivity_label(value)
	if _player:
		_player.MOUSE_SENS = value


func _on_invert_toggled(pressed: bool) -> void:
	CogitoGameConfig.invert_y = pressed
	if _player:
		_player.INVERT_Y_AXIS = pressed


func _on_toggle_crouch(pressed: bool) -> void:
	CogitoGameConfig.toggle_crouching = pressed
	if _player:
		_player.TOGGLE_CROUCH = pressed


func _on_headbob_selected(index: int) -> void:
	var value: int = _headbob_option.get_item_id(index)
	CogitoGameConfig.headbob_strength = value
	if _player:
		_player.HEADBOBBLE = value


func _apply_to_player() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("Player")
	if _player == null:
		return
	_player.MOUSE_SENS = CogitoGameConfig.mouse_sens
	_player.INVERT_Y_AXIS = CogitoGameConfig.invert_y
	_player.TOGGLE_CROUCH = CogitoGameConfig.toggle_crouching
	_player.HEADBOBBLE = CogitoGameConfig.headbob_strength
#endregion


#region Tastenbelegung
func _start_rebind(action: String, button: Button) -> void:
	# Alten "warte auf Taste"-Zustand zuruecksetzen.
	if _awaiting_action != "":
		_refresh_bind_button(_awaiting_action)
	_awaiting_action = action
	_awaiting_button = button
	button.text = "Taste drücken …"


func _cancel_rebind() -> void:
	if _awaiting_action == "":
		return
	var action := _awaiting_action
	_awaiting_action = ""
	_awaiting_button = null
	_refresh_bind_button(action)


func _finish_rebind(event: InputEventKey) -> void:
	var action := _awaiting_action
	_awaiting_action = ""
	_awaiting_button = null

	var new_event := InputEventKey.new()
	new_event.physical_keycode = event.physical_keycode
	InputHelper.set_keyboard_input_for_action(action, new_event)

	# Alle Knöpfe neu beschriften: durch das Tauschen kann sich mehr als eine
	# Belegung geaendert haben.
	for a in _bind_buttons.keys():
		_refresh_bind_button(a)


func _on_reset_pressed() -> void:
	# Steuerungs-Defaults
	CogitoGameConfig.mouse_sens = DEFAULT_SENSITIVITY
	CogitoGameConfig.invert_y = false
	CogitoGameConfig.toggle_crouching = false
	CogitoGameConfig.headbob_strength = 1

	# Tastenbelegung
	for action in DEFAULT_BINDINGS.keys():
		var ev := InputEventKey.new()
		ev.physical_keycode = DEFAULT_BINDINGS[action]
		InputHelper.set_keyboard_input_for_action(action, ev)

	_sync_from_config()
	_apply_to_player()
#endregion


#region Oeffnen / Schliessen / Speichern
func _input(event: InputEvent) -> void:
	# Tastenaufnahme hat Vorrang vor allem anderen.
	if _awaiting_action != "":
		if event is InputEventKey and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
				_cancel_rebind()
			else:
				_finish_rebind(event)
			return
		return

	if not _root:
		return

	if event.is_action_pressed("settings"):
		# In Startmenue und Endscreens laesst sich das Menue nicht per F1
		# oeffnen. Ein bereits offenes Menue darf per F1 geschlossen werden.
		if not _root.visible and (menu_mode or hotkey_blocked):
			return
		get_viewport().set_input_as_handled()
		_set_open(not _root.visible)
		return

	if _root.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_set_open(false)


func _set_open(open: bool) -> void:
	if _root == null:
		return

	# Beim allerersten Aufruf (Spielstart) nichts anwenden oder speichern.
	if not open and not _has_been_opened:
		_root.visible = false
		_update_hint_visibility()
		return

	_root.visible = open
	_update_hint_visibility()

	if open:
		_has_been_opened = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _player and _player.has_method("pause_before_interaction"):
			_player.pause_before_interaction()
		if _sensitivity_slider:
			# Beim Oeffnen den aktuellen Stand anzeigen.
			_sensitivity_slider.set_value_no_signal(CogitoGameConfig.mouse_sens)
			_update_sensitivity_label(CogitoGameConfig.mouse_sens)
	else:
		_cancel_rebind()
		_save()
		if menu_mode:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			closed.emit()
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Verzoegert: Wird das Menue per Esc geschlossen, laeuft im selben Frame
		# noch Cogitos InputRouter. Waere die Bewegung schon wieder freigegeben,
		# wuerde dieselbe Esc-Taste zusaetzlich das Pause-Menue oeffnen.
		_resume_player_deferred.call_deferred()


## Der F1-Hinweis ist nur im laufenden Spiel bei geschlossenem Menue sichtbar.
func _update_hint_visibility() -> void:
	if _hint_label == null:
		return
	var is_menu_open := _root != null and _root.visible
	_hint_label.visible = not is_menu_open and not menu_mode and not hotkey_blocked


## Sperrt F1 dauerhaft (Game-Over- / Sieg-Screen). Ein gerade offenes Menue
## wird gespeichert und geschlossen, ohne Maus oder Spieler freizugeben.
func block_hotkey() -> void:
	hotkey_blocked = true
	if _root and _root.visible:
		_cancel_rebind()
		_save()
		_root.visible = false
	_update_hint_visibility()


## Oeffnet das Menue von aussen (Startmenue).
func open_menu() -> void:
	_set_open(true)


func is_open() -> bool:
	return _root != null and _root.visible


func _resume_player_deferred() -> void:
	if _player and _player.has_method("resume_after_interaction"):
		_player.resume_after_interaction()


func _save() -> void:
	if CogitoGameConfig == null:
		return
	CogitoGameConfig.save_options()
#endregion
