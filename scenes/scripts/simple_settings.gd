extends CanvasLayer
## Pause- und Einstellungsmenue im duesteren Ermittler-Stil (ESC).
##
## Kategorien:
##   - Audio:               Gesamt-, Umgebungs- und Effektlautstaerke
##   - Steuerung & Kamera:  Maus-Empfindlichkeit, FOV (75-95), Y-Invert, Ducken,
##                          Headbob, Tastenbelegung
##   - Grafik:              Helligkeit (Exposure), Vollbild/Fenster, V-Sync,
##                          Bildqualitaet (AA, MSAA, AF, 3D-Skalierung, Profile)
##
## Im Spiel (menu_mode == false) ist es zugleich das Pausemenue: Es pausiert den
## SceneTree und bietet "Fortsetzen", "Zurueck zur Level-Auswahl" und "Spiel
## beenden". Geoeffnet wird es ueber horror_player.gd (ESC -> open_pause_menu()).
## Aus dem Startmenue (menu_mode == true) oeffnet nur der Knopf dort das Menue.
##
## Aenderungen gelten sofort. Cogito-Werte landen in user://options.cfg, die
## neuen Werte (Lautstaerken, FOV, Helligkeit) in user://horror_settings.cfg.

const UIStyle = preload("res://scenes/scripts/ui_style.gd")

## Wird nach dem Schliessen des Menues (und dem Speichern) gesendet.
signal closed

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SETTINGS_FILE := "user://horror_settings.cfg"
const MIGRATION_KEY := "simplified_controls_v2"
const FULLSCREEN_MIGRATION_KEY := "fullscreen_default_v2"

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
const DEFAULT_FOV := 85.0
const DEFAULT_EXPOSURE := 0.85
const FOV_MIN := 75.0
const FOV_MAX := 95.0
const EXPOSURE_MIN := 0.5
const EXPOSURE_MAX := 1.5

## Kategorie -> Anzeigename (Reihenfolge = Tab-Reihenfolge).
const CATEGORIES := ["AUDIO", "STEUERUNG & KAMERA", "GRAFIK"]

## Audio-Zeilen: Schluessel, Anzeigename, Bus.
const AUDIO_ROWS := [
	["master", "Gesamtlautstärke", "Master"],
	["ambient", "Umgebung", "Music"],
	["sfx", "Effekte", "SFX"],
]

var _root: Control
var _title_label: Label
var _subtitle_label: Label
var _scroll: ScrollContainer
var _pages: Array[Control] = []
var _tab_buttons: Array[Button] = []

var _sensitivity_slider: HSlider
var _fov_slider: HSlider
var _exposure_slider: HSlider
var _invert_check: CheckBox
var _toggle_crouch_check: CheckBox
var _fullscreen_check: CheckBox
var _vsync_check: CheckBox
var _screen_option: OptionButton
var _resolution_option: OptionButton
var _resolution_hint: Label
var _headbob_option: OptionButton
var _profile_option: OptionButton
var _aa_option: OptionButton
var _msaa_option: OptionButton
var _af_option: OptionButton
var _scale_slider: HSlider
var _audio_sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _bind_buttons: Dictionary = {}

var _pause_footer: HBoxContainer
var _menu_footer: HBoxContainer

var _awaiting_action: String = ""
var _player: Node = null
var _has_been_opened: bool = false
var _opened_frame: int = -1
var _file := ConfigFile.new()

## Aus dem Startmenue heraus geoeffnet: kein Pausieren, die Maus bleibt sichtbar
## und ESC oeffnet das Menue nicht (nur der Knopf im Startmenue).
var menu_mode: bool = false:
	set(value):
		menu_mode = value
		_update_footer()

## Von Game-Over- und Sieg-Screen gesetzt: ESC oeffnet das Menue nicht mehr.
var hotkey_blocked: bool = false


func _ready() -> void:
	# Laeuft auch, wenn das Spiel pausiert ist.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	add_to_group("simple_settings")
	_player = get_tree().get_first_node_in_group("Player")
	_file.load(SETTINGS_FILE)

	_migrate_controls_once()
	_migrate_fullscreen_default_once()
	_build_ui()
	_update_panel_height()
	_select_category(0)
	_update_footer()
	_sync_from_config()
	_set_open(false)

	# Nach dem kompletten Szenenstart anwenden: Player und Environment lesen ihre
	# Werte in _ready() selbst und wuerden unsere sonst ueberschreiben.
	_apply_all.call_deferred()


## Sicherheitsnetz: Ein Szenenwechsel aus dem Pausemenue darf nie ein
## pausiertes Spiel zuruecklassen.
func _exit_tree() -> void:
	if is_inside_tree():
		get_tree().paused = false


## Einmalige Korrektur unsinniger Alt-Defaults (Y invertiert, Crouch-Toggle).
func _migrate_controls_once() -> void:
	var cfg := CogitoGameConfig
	if cfg == null or cfg.config == null:
		return
	if cfg.config.has_section_key(OptionsConstants.section_name, MIGRATION_KEY):
		return

	cfg.invert_y = false
	cfg.toggle_crouching = false
	cfg.headbob_strength = 1

	# Alt-Configs starten auf 800x600 (Index 0): auf zeitgemaesse Groesse anheben.
	if cfg.current_resolution_index == 0:
		cfg.current_resolution_index = DEFAULT_RESOLUTION_INDEX
		cfg.fullscreen_mode = false
		_apply_window_size.call_deferred()

	cfg.config.set_value(OptionsConstants.section_name, MIGRATION_KEY, 1)
	cfg.save_options()


## Einmalig: Spiel startet im Vollbild (auch bei alten Configs mit Fenstermodus).
func _migrate_fullscreen_default_once() -> void:
	var cfg := CogitoGameConfig
	if cfg == null or cfg.config == null:
		return
	if cfg.config.has_section_key(OptionsConstants.section_name, FULLSCREEN_MIGRATION_KEY):
		return
	_prepare_windowed_size()
	cfg.toggle_fullscreen(true)
	# Moduswechsel braucht einen Moment; sonst speichert save_options noch "Fenster".
	await get_tree().create_timer(0.5).timeout
	cfg.fullscreen_mode = true
	cfg.config.set_value(OptionsConstants.section_name, FULLSCREEN_MIGRATION_KEY, 1)
	cfg.save_options()
	if not cfg.is_fullscreen():
		# Sicherheitsnetz: gewuenschten Zustand trotzdem in die Datei schreiben.
		cfg.config.set_value(OptionsConstants.section_name, OptionsConstants.fullscreen_mode_key_name, true)
		cfg.config.save(OptionsConstants.config_file_name)


## Stellt sicher, dass windowed_resolution gesetzt ist, bevor in den Fenstermodus gewechselt wird.
func _prepare_windowed_size() -> void:
	var cfg := CogitoGameConfig
	var values := cfg.RESOLUTION_DICTIONARY.values()
	var idx := clampi(int(cfg.current_resolution_index), 0, values.size() - 1)
	cfg.windowed_resolution = values[idx]


func _apply_window_size() -> void:
	if CogitoGameConfig.is_fullscreen():
		return
	var window := get_window()
	window.size = Vector2i(1600, 900)
	window.content_scale_size = Vector2i.ZERO


#region UI-Aufbau
func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Dimmer mit Unschaerfe ueber dem Spielbild; faellt auf reines Schwarz zurueck,
	# falls der Shader nicht greift.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	var shader := Shader.new()
	shader.code = UIStyle.BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	dim.material = mat
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1040, 0)
	panel.add_theme_stylebox_override("panel", UIStyle.box(UIStyle.C_PANEL, UIStyle.C_LINE, [1, 1, 1, 1], [32, 26, 32, 26]))
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	panel.add_child(outer)

	_subtitle_label = UIStyle.label("", 13, UIStyle.C_ACCENT)
	outer.add_child(_subtitle_label)
	_title_label = UIStyle.label("", 38, UIStyle.C_TEXT)
	outer.add_child(_title_label)
	outer.add_child(_rule())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	outer.add_child(body)

	var tabs := VBoxContainer.new()
	tabs.custom_minimum_size = Vector2(250, 0)
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(700, 420)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	get_viewport().size_changed.connect(_update_panel_height)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(stack)

	var group := ButtonGroup.new()
	for i in CATEGORIES.size():
		var b := Button.new()
		b.text = CATEGORIES[i]
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 56)
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", UIStyle.C_DIM)
		b.add_theme_color_override("font_hover_color", UIStyle.C_TEXT)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		var pad := [18, 0, 12, 0]
		b.add_theme_stylebox_override("normal", UIStyle.box(UIStyle.C_CARD, UIStyle.C_LINE, [3, 0, 0, 0], pad))
		b.add_theme_stylebox_override("hover", UIStyle.box(UIStyle.C_CARD_HOVER, UIStyle.C_DIM, [3, 0, 0, 0], pad))
		b.add_theme_stylebox_override("pressed", UIStyle.box(UIStyle.C_CARD_ACTIVE, UIStyle.C_ACCENT, [3, 0, 0, 0], pad))
		b.add_theme_stylebox_override("hover_pressed", UIStyle.box(UIStyle.C_CARD_ACTIVE, UIStyle.C_ACCENT_BRIGHT, [3, 0, 0, 0], pad))
		b.pressed.connect(_select_category.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)

		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 16)
		stack.add_child(page)
		_pages.append(page)

	_build_audio_page(_pages[0])
	_build_controls_page(_pages[1])
	_build_graphics_page(_pages[2])

	outer.add_child(_rule())
	_build_footer(outer)


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = UIStyle.C_LINE
	r.custom_minimum_size = Vector2(0, 1)
	return r


func _section(parent: Control, text: String) -> void:
	parent.add_child(UIStyle.label(text, 13, UIStyle.C_ACCENT))


func _build_audio_page(page: Control) -> void:
	_section(page, "LAUTSTÄRKE")
	for row in AUDIO_ROWS:
		var key: String = row[0]
		_audio_sliders[key] = _add_slider_row(page, row[1], 0.0, 1.0, 0.01, key,
			func(v: float): _on_audio_changed(key, v),
			func(v: float) -> String: return "%d %%" % roundi(v * 100.0))


func _build_controls_page(page: Control) -> void:
	_section(page, "MAUS & KAMERA")
	_sensitivity_slider = _add_slider_row(page, "Maus-Empfindlichkeit", 0.03, 1.5, 0.01, "sens",
		_on_sensitivity_changed, func(v: float) -> String: return "%.2f" % v)
	_fov_slider = _add_slider_row(page, "Sichtfeld (FOV)", FOV_MIN, FOV_MAX, 1.0, "fov",
		_on_fov_changed, func(v: float) -> String: return "%d°" % roundi(v))
	_invert_check = _add_toggle_row(page, "Y-Achse invertieren", _on_invert_toggled)
	_toggle_crouch_check = _add_toggle_row(page, "Ducken umschalten (statt halten)", _on_toggle_crouch)
	_add_headbob_row(page)

	page.add_child(_rule())
	_section(page, "TASTENBELEGUNG")
	var hint := UIStyle.label("Knopf anklicken, dann die neue Taste drücken. Esc bricht ab.", 13, UIStyle.C_DIM)
	page.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	page.add_child(grid)
	for entry in BINDABLE_ACTIONS:
		_add_bind_row(grid, entry[0], entry[1])


func _build_graphics_page(page: Control) -> void:
	_section(page, "DARSTELLUNG")
	_exposure_slider = _add_slider_row(page, "Helligkeit (Exposure)", EXPOSURE_MIN, EXPOSURE_MAX, 0.01, "exposure",
		_on_exposure_changed, func(v: float) -> String: return "%.2f" % v)
	_fullscreen_check = _add_toggle_row(page, "Vollbild", _on_fullscreen_toggled)
	var screen_labels: Array = []
	for i in DisplayServer.get_screen_count():
		var sz := DisplayServer.screen_get_size(i)
		screen_labels.append("Bildschirm %d (%d×%d)" % [i + 1, sz.x, sz.y])
	_screen_option = _add_option_row(page, "Bildschirm", screen_labels, _on_screen_selected)
	_resolution_option = _add_option_row(page, "Fenster-Auflösung",
		CogitoGameConfig.RESOLUTION_DICTIONARY.keys(), _on_resolution_selected)
	_resolution_hint = UIStyle.label(
		"Im Vollbild gilt die Bildschirmauflösung; die Renderauflösung stellst du unter „3D-Auflösung“ ein.",
		13, UIStyle.C_DIM)
	page.add_child(_resolution_hint)
	_vsync_check = _add_toggle_row(page, "V-Sync", _on_vsync_toggled)

	page.add_child(_rule())
	_section(page, "BILDQUALITÄT")
	# Profil-Eintrag "Benutzerdefiniert" (Index 3) wird nur angezeigt, nie gewaehlt.
	_profile_option = _add_option_row(page, "Qualitätsprofil",
		GraphicsSettings.PROFILE_LABELS + ["Benutzerdefiniert"], _on_profile_selected)
	_profile_option.set_item_disabled(GraphicsSettings.Profile.CUSTOM, true)
	_aa_option = _add_option_row(page, "Anti-Aliasing",
		GraphicsSettings.AA_LABELS, _on_aa_selected)
	_msaa_option = _add_option_row(page, "MSAA 3D",
		GraphicsSettings.MSAA_LABELS, _on_msaa_selected)
	_af_option = _add_option_row(page, "Anisotropic Filtering",
		GraphicsSettings.AF_LABELS, _on_af_selected)
	_scale_slider = _add_slider_row(page, "3D-Auflösung",
		GraphicsSettings.SCALE_MIN, GraphicsSettings.SCALE_MAX, 0.05, "scale",
		_on_scale_changed, func(v: float) -> String: return "%d %%" % roundi(v * 100.0))
	page.add_child(UIStyle.label(
		"FSR 2 rechnet immer mit voller Auflösung (100 %). TAA/FSR 2 brauchen Forward+.",
		13, UIStyle.C_DIM))


func _build_footer(parent: Control) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	parent.add_child(footer)

	var reset_button := Button.new()
	reset_button.text = "STANDARDWERTE"
	reset_button.custom_minimum_size = Vector2(210, 52)
	UIStyle.style_button(reset_button, false, 17)
	reset_button.pressed.connect(_on_reset_pressed)
	footer.add_child(reset_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	# Pausemodus: Fortsetzen / Level-Auswahl / Beenden.
	_pause_footer = HBoxContainer.new()
	_pause_footer.add_theme_constant_override("separation", 12)
	footer.add_child(_pause_footer)
	_footer_button(_pause_footer, "FORTSETZEN", 190, true, func(): _set_open(false))
	_footer_button(_pause_footer, "ZURÜCK ZUR LEVEL-AUSWAHL", 300, false, _on_level_select_pressed)
	_footer_button(_pause_footer, "SPIEL BEENDEN", 190, false, _on_quit_pressed)

	# Startmenue: nur Zurueck.
	_menu_footer = HBoxContainer.new()
	footer.add_child(_menu_footer)
	_footer_button(_menu_footer, "SPEICHERN & SCHLIESSEN", 290, true, func(): _set_open(false))


func _footer_button(parent: Control, text: String, width: float, primary: bool, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 52)
	UIStyle.style_button(b, primary, 17)
	b.pressed.connect(callback)
	parent.add_child(b)


## Zeile mit Beschriftung, Slider und Wertanzeige. Gibt den Slider zurueck.
func _add_slider_row(parent: Control, text: String, min_v: float, max_v: float, step: float,
		key: String, on_changed: Callable, formatter: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	var label := UIStyle.label(text, 17, UIStyle.C_TEXT)
	label.custom_minimum_size = Vector2(230, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(200, 30)
	UIStyle.style_slider(slider)
	row.add_child(slider)

	var value_label := UIStyle.label("", 16, UIStyle.C_DIM)
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_value_labels[slider] = [value_label, formatter]

	slider.value_changed.connect(func(v: float):
		_refresh_value_label(slider)
		on_changed.call(v))
	return slider


func _refresh_value_label(slider: HSlider) -> void:
	var entry: Array = _value_labels.get(slider, [])
	if entry.is_empty():
		return
	var label: Label = entry[0]
	var formatter: Callable = entry[1]
	label.text = formatter.call(slider.value)


func _set_slider(slider: HSlider, value: float) -> void:
	if slider == null:
		return
	slider.set_value_no_signal(value)
	_refresh_value_label(slider)


func _add_toggle_row(parent: Control, text: String, on_toggled: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.focus_mode = Control.FOCUS_NONE
	check.add_theme_font_size_override("font_size", 17)
	check.add_theme_color_override("font_color", UIStyle.C_TEXT)
	check.add_theme_color_override("font_hover_color", Color.WHITE)
	check.add_theme_color_override("font_pressed_color", Color.WHITE)
	check.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	check.toggled.connect(on_toggled)
	parent.add_child(check)
	return check


func _add_headbob_row(parent: Control) -> void:
	_headbob_option = _add_option_row(parent, "Headbob (Kopfwippen)", HEADBOB_LABELS, _on_headbob_selected)
	for i in HEADBOB_VALUES.size():
		_headbob_option.set_item_id(i, HEADBOB_VALUES[i])


## Zeile mit Beschriftung und Auswahlliste. Gibt die OptionButton zurueck.
func _add_option_row(parent: Control, text: String, labels: Array, on_selected: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	var label := UIStyle.label(text, 17, UIStyle.C_TEXT)
	label.custom_minimum_size = Vector2(230, 0)
	row.add_child(label)

	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size = Vector2(0, 40)
	UIStyle.style_button(option, false, 16)
	for i in labels.size():
		option.add_item(labels[i], i)
	option.item_selected.connect(on_selected)
	row.add_child(option)
	return option


func _add_bind_row(parent: Control, action: String, display_name: String) -> void:
	var label := UIStyle.label(display_name, 15, UIStyle.C_TEXT)
	label.custom_minimum_size = Vector2(130, 0)
	parent.add_child(label)

	var button := Button.new()
	button.custom_minimum_size = Vector2(110, 34)
	UIStyle.style_button(button, false, 15)
	button.pressed.connect(func(): _start_rebind(action, button))
	parent.add_child(button)
	_bind_buttons[action] = button
	_refresh_bind_button(action)


func _select_category(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index
		_tab_buttons[i].set_pressed_no_signal(i == index)
	if _scroll:
		_scroll.scroll_vertical = 0


## Begrenzt die Panelhoehe auf die Fensterhoehe, damit die Fussleiste auch bei
## kleinen Aufloesungen erreichbar bleibt.
func _update_panel_height() -> void:
	if _scroll == null:
		return
	var window_height := get_viewport().get_visible_rect().size.y
	_scroll.custom_minimum_size.y = clampf(window_height - 300.0, 240.0, 520.0)


## Titel und Fussleiste je nach Modus (Pause im Spiel / Overlay im Startmenue).
func _update_footer() -> void:
	if _pause_footer == null:
		return
	_pause_footer.visible = not menu_mode
	_menu_footer.visible = menu_mode
	_subtitle_label.text = "EINSTELLUNGEN" if menu_mode else "EINSATZ UNTERBROCHEN"
	_title_label.text = "Einstellungen" if menu_mode else "Pause"
	_subtitle_label.text += "  ·  Esc zum Schließen"


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
	_set_slider(_sensitivity_slider, CogitoGameConfig.mouse_sens)
	_set_slider(_fov_slider, _get_saved("camera", "fov", DEFAULT_FOV))
	_set_slider(_exposure_slider, _get_saved("graphics", "exposure", DEFAULT_EXPOSURE))
	for row in AUDIO_ROWS:
		_set_slider(_audio_sliders.get(row[0]), _get_audio_value(row[0], row[2]))
	if _invert_check:
		_invert_check.set_pressed_no_signal(CogitoGameConfig.invert_y)
	if _toggle_crouch_check:
		_toggle_crouch_check.set_pressed_no_signal(CogitoGameConfig.toggle_crouching)
	if _fullscreen_check:
		_fullscreen_check.set_pressed_no_signal(CogitoGameConfig.is_fullscreen())
	_sync_resolution()
	if _vsync_check:
		_vsync_check.set_pressed_no_signal(DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED)
	if _headbob_option:
		var idx := HEADBOB_VALUES.find(CogitoGameConfig.headbob_strength)
		_headbob_option.select(0 if idx == -1 else idx)
	_sync_quality()
	for action in _bind_buttons.keys():
		_refresh_bind_button(action)


func _get_saved(section: String, key: String, default: Variant) -> Variant:
	return _file.get_value(section, key, default)


func _put_saved(section: String, key: String, value: Variant) -> void:
	_file.set_value(section, key, value)


## Gespeicherter Wert, sonst der aktuelle Pegel des Busses (Cogito-Optionen).
func _get_audio_value(key: String, bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	var current := 1.0
	if idx >= 0:
		current = db_to_linear(AudioServer.get_bus_volume_db(idx))
	return clampf(_get_saved("audio", key, current), 0.0, 1.0)


func _on_audio_changed(key: String, value: float) -> void:
	_put_saved("audio", key, value)
	_apply_audio(key, value)


func _apply_audio(key: String, value: float) -> void:
	for row in AUDIO_ROWS:
		if row[0] != key:
			continue
		var idx := AudioServer.get_bus_index(row[2])
		if idx < 0:
			return
		AudioServer.set_bus_mute(idx, value <= 0.001)
		# Cogito merkt sich SFX-/Musik-Pegel selbst (options.cfg) - dort mitfuehren.
		if row[2] != "Master" and CogitoGameConfig:
			CogitoGameConfig.set_volume(idx, value)
		else:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(value, 0.0001)))
		return


func _on_sensitivity_changed(value: float) -> void:
	CogitoGameConfig.mouse_sens = value
	if _player:
		_player.MOUSE_SENS = value


func _on_fov_changed(value: float) -> void:
	_put_saved("camera", "fov", value)
	_apply_fov(value)


func _apply_fov(value: float) -> void:
	if _player and _player.has_method("set_base_fov"):
		_player.set_base_fov(value)


func _on_exposure_changed(value: float) -> void:
	_put_saved("graphics", "exposure", value)
	_apply_exposure(value)


func _apply_exposure(value: float) -> void:
	var node := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if node and node.environment:
		node.environment.tonemap_exposure = value


#region Bildqualitaet
func _sync_quality() -> void:
	if _aa_option == null:
		return
	var gs := GraphicsSettings
	_profile_option.select(gs.current_profile())
	_aa_option.select(gs.aa_mode)
	_msaa_option.select(gs.msaa_index)
	_af_option.select(gs.af_index)
	_set_slider(_scale_slider, gs.render_scale)
	# FSR 2 erzwingt Skalierung 1.0 - Slider dann sperren.
	var fsr := gs.aa_mode == GraphicsSettings.AAMode.FSR2
	_scale_slider.editable = not fsr
	if fsr:
		_set_slider(_scale_slider, 1.0)


func _on_profile_selected(index: int) -> void:
	GraphicsSettings.apply_profile(index)
	_sync_quality()


func _on_aa_selected(index: int) -> void:
	GraphicsSettings.aa_mode = index
	_quality_changed()


func _on_msaa_selected(index: int) -> void:
	GraphicsSettings.msaa_index = index
	_quality_changed()


func _on_af_selected(index: int) -> void:
	GraphicsSettings.af_index = index
	_quality_changed()


func _on_scale_changed(value: float) -> void:
	GraphicsSettings.render_scale = value
	_quality_changed()


func _quality_changed() -> void:
	GraphicsSettings.apply()
	_sync_quality()
#endregion


func _on_fullscreen_toggled(pressed: bool) -> void:
	if not pressed:
		_prepare_windowed_size()
	CogitoGameConfig.toggle_fullscreen(pressed)
	_sync_resolution(pressed)


func _on_screen_selected(index: int) -> void:
	GraphicsSettings.screen_index = index
	GraphicsSettings.apply_screen()


func _on_resolution_selected(index: int) -> void:
	CogitoGameConfig._on_resolution_selected(index)


## Auflösungsliste nur im Fenstermodus bedienbar.
func _sync_resolution(fullscreen: bool = CogitoGameConfig.is_fullscreen()) -> void:
	if _resolution_option == null:
		return
	if _screen_option:
		var cur := GraphicsSettings.screen_index
		if cur < 0 or cur >= _screen_option.item_count:
			cur = DisplayServer.window_get_current_screen()
		_screen_option.select(clampi(cur, 0, _screen_option.item_count - 1))
		_screen_option.disabled = _screen_option.item_count < 2
	var idx := clampi(int(CogitoGameConfig.current_resolution_index), 0, _resolution_option.item_count - 1)
	_resolution_option.select(idx)
	_resolution_option.disabled = fullscreen
	_resolution_hint.visible = fullscreen


func _on_vsync_toggled(pressed: bool) -> void:
	CogitoGameConfig.set_vsync(pressed)


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


## Wendet alle gespeicherten Werte auf Spieler, Environment und Audio-Busse an.
func _apply_all() -> void:
	_apply_to_player()
	_apply_exposure(_get_saved("graphics", "exposure", DEFAULT_EXPOSURE))
	# Audio nur anwenden, wenn der Nutzer schon etwas gespeichert hat.
	for row in AUDIO_ROWS:
		if _file.has_section_key("audio", row[0]):
			_apply_audio(row[0], _file.get_value("audio", row[0]))


func _apply_to_player() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("Player")
	if _player == null:
		return
	_player.MOUSE_SENS = CogitoGameConfig.mouse_sens
	_player.INVERT_Y_AXIS = CogitoGameConfig.invert_y
	_player.TOGGLE_CROUCH = CogitoGameConfig.toggle_crouching
	_player.HEADBOBBLE = CogitoGameConfig.headbob_strength
	_apply_fov(_get_saved("camera", "fov", DEFAULT_FOV))
#endregion


#region Tastenbelegung
func _start_rebind(action: String, button: Button) -> void:
	if _awaiting_action != "":
		_refresh_bind_button(_awaiting_action)
	_awaiting_action = action
	button.text = "Taste drücken …"


func _cancel_rebind() -> void:
	if _awaiting_action == "":
		return
	var action := _awaiting_action
	_awaiting_action = ""
	_refresh_bind_button(action)


func _finish_rebind(event: InputEventKey) -> void:
	var action := _awaiting_action
	_awaiting_action = ""

	var new_event := InputEventKey.new()
	new_event.physical_keycode = event.physical_keycode
	InputHelper.set_keyboard_input_for_action(action, new_event)

	# Durch das Tauschen kann sich mehr als eine Belegung geaendert haben.
	for a in _bind_buttons.keys():
		_refresh_bind_button(a)


func _on_reset_pressed() -> void:
	CogitoGameConfig.mouse_sens = DEFAULT_SENSITIVITY
	CogitoGameConfig.invert_y = false
	CogitoGameConfig.toggle_crouching = false
	CogitoGameConfig.headbob_strength = 1

	_put_saved("camera", "fov", DEFAULT_FOV)
	_put_saved("graphics", "exposure", DEFAULT_EXPOSURE)
	GraphicsSettings.apply_profile(GraphicsSettings.DEFAULT_PROFILE)
	for row in AUDIO_ROWS:
		_put_saved("audio", row[0], 1.0)
		_apply_audio(row[0], 1.0)

	for action in DEFAULT_BINDINGS.keys():
		var ev := InputEventKey.new()
		ev.physical_keycode = DEFAULT_BINDINGS[action]
		InputHelper.set_keyboard_input_for_action(action, ev)

	_sync_from_config()
	_apply_to_player()
	_apply_exposure(DEFAULT_EXPOSURE)
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

	if _root == null or not _root.visible:
		return

	# ESC schliesst das offene Menue. Im selben Frame, in dem es durch ESC
	# geoeffnet wurde, darf dieselbe Taste es nicht sofort wieder schliessen.
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		if Engine.get_process_frames() != _opened_frame:
			_set_open(false)


## Oeffnet das Pausemenue im Spiel (von horror_player.gd bei ESC aufgerufen).
func open_pause_menu() -> void:
	if menu_mode or hotkey_blocked or is_open():
		return
	_set_open(true)


## Oeffnet das Menue von aussen (Startmenue-Knopf).
func open_menu() -> void:
	if not is_open():
		_set_open(true)


func is_open() -> bool:
	return _root != null and _root.visible


func _set_open(open: bool) -> void:
	if _root == null:
		return

	# Beim allerersten Aufruf (Spielstart) nichts anwenden oder speichern.
	if not open and not _has_been_opened:
		_root.visible = false
		return

	_root.visible = open

	if open:
		_has_been_opened = true
		_opened_frame = Engine.get_process_frames()
		_sync_from_config()
		_select_category(0)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not menu_mode:
			if _player and _player.has_method("pause_before_interaction"):
				_player.pause_before_interaction()
			get_tree().paused = true
	else:
		_cancel_rebind()
		_save()
		if menu_mode:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			closed.emit()
			return
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Verzoegert: Im selben Frame laeuft noch Cogitos InputRouter. Waere die
		# Bewegung schon freigegeben, wuerde dieselbe ESC-Taste das Menue erneut
		# oeffnen.
		_resume_player_deferred.call_deferred()
		closed.emit()


## Sperrt das Menue dauerhaft (Game-Over- / Sieg-Screen). Ein gerade offenes
## Menue wird gespeichert und geschlossen, ohne Maus oder Spieler freizugeben;
## der Endscreen uebernimmt Pause und Mauszeiger selbst.
func block_hotkey() -> void:
	hotkey_blocked = true
	if _root and _root.visible:
		_cancel_rebind()
		_save()
		_root.visible = false


func _on_level_select_pressed() -> void:
	_save()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_quit_pressed() -> void:
	_save()
	get_tree().quit()


func _resume_player_deferred() -> void:
	if _player and _player.has_method("resume_after_interaction"):
		_player.resume_after_interaction()


func _save() -> void:
	GraphicsSettings.store(_file)
	_file.save(SETTINGS_FILE)
	if CogitoGameConfig:
		CogitoGameConfig.save_options()
#endregion
