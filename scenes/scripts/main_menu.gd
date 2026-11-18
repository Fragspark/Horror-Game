extends Control
## Hauptmenue mit Ortsauswahl im Stil einer duesteren Ermittler-Akte.
##
## Hintergrund: Vorschaubild, abgedunkelt, mit Vignette und Filmkorn.
## Links: Seitenleiste mit Titel und Orts-Karten. Rechts: Akte mit Foto, Name,
## Beschreibung, Missionsziel und Bedrohungsstufe. Unten: Aktionsleiste.
## Das UI entsteht komplett im Code.
##
## Tab (Inventar) und F1 (Einstellungen per Hotkey) sind hier gesperrt; die
## Einstellungen oeffnen sich nur ueber den Knopf.

const GAME_SCENE := "res://scenes/horror_main.tscn"
const PREVIEW_HOUSE := "res://assets/ui/preview_house.png"

const C_BG := Color(0.03, 0.028, 0.03)
const C_SIDEBAR := Color(0.045, 0.04, 0.042, 0.9)
const C_CARD := Color(0.09, 0.08, 0.08, 0.9)
const C_CARD_HOVER := Color(0.14, 0.11, 0.105, 0.95)
const C_CARD_ACTIVE := Color(0.17, 0.09, 0.08, 0.97)
const C_LINE := Color(0.26, 0.22, 0.19)
const C_TEXT := Color(0.88, 0.84, 0.78)
const C_DIM := Color(0.56, 0.52, 0.48)
const C_RED := Color(0.78, 0.13, 0.1)
const C_RED_BRIGHT := Color(0.95, 0.25, 0.18)

const VIGNETTE_SHADER := """
shader_type canvas_item;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float d = distance(UV, vec2(0.5, 0.5));
	float vig = smoothstep(0.25, 0.85, d);
	float grain = hash(floor(UV * vec2(1600.0, 900.0)) + fract(TIME) * 37.0);
	float flicker = 0.03 * sin(TIME * 7.0) * sin(TIME * 2.3);
	COLOR = vec4(vec3(grain * 0.35), clamp(0.12 + vig * 0.75 + flicker, 0.0, 1.0));
}
"""

## Name, Kurzbeschreibung, Ziel, Bedrohung (1-5), Szene ("" = gesperrt).
const LOCATIONS: Array[Dictionary] = [
	{
		"name": "Verlassenes Vorstadthaus",
		"description": "Ein Einfamilienhaus am Ende der Straße. Das Licht brennt noch, aber niemand ist zu Hause. Nachbarn berichten von Schritten im Keller.",
		"objective": "Generator starten, zwei Sicherungen einsetzen und durch die Hintertür entkommen.",
		"threat": 3,
		"scene": GAME_SCENE,
	},
	{
		"name": "Altes Sanatorium",
		"description": "Die Akten dieses Ortes sind noch versiegelt. Zugang erst nach Freigabe durch die Einsatzleitung.",
		"objective": "Demnächst verfügbar.",
		"threat": 4,
		"scene": "",
	},
	{
		"name": "Verlassene Waldhütte",
		"description": "Eine Hütte tief im Wald. Die Erkundung des Gebiets ist noch nicht abgeschlossen.",
		"objective": "Demnächst verfügbar.",
		"threat": 2,
		"scene": "",
	},
]

@onready var _settings: CanvasLayer = %SimpleSettings
@onready var _room_hum: AudioStreamPlayer = $RoomHum

var _selected: int = 0
var _cards: Array[Button] = []
var _content: Control
var _background: TextureRect
var _photo: TextureRect
var _file_label: Label
var _name_label: Label
var _status_label: Label
var _desc_label: Label
var _objective_label: Label
var _pips: Array[ColorRect] = []
var _threat_text: Label
var _start_button: Button
var _preview_tex: Texture2D


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_settings.menu_mode = true
	_settings.closed.connect(_on_settings_closed)

	_preview_tex = _load_preview()
	_build_ui()
	_select_location(0)
	_start_ambience()

	_content.modulate.a = 0.0
	create_tween().tween_property(_content, "modulate:a", 1.0, 1.4)


## Tab und F1 bleiben im Hauptmenue gesperrt. F1 darf ein bereits offenes
## Einstellungsmenue noch schliessen (das behandelt simple_settings selbst).
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_TAB or key.keycode == KEY_TAB:
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("settings") and not _settings.is_open():
		get_viewport().set_input_as_handled()


#region Hilfsfunktionen

func _box(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: Array = [0, 0, 0, 0], margin: Array = [0, 0, 0, 0]) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = border_w[0]
	s.border_width_top = border_w[1]
	s.border_width_right = border_w[2]
	s.border_width_bottom = border_w[3]
	s.content_margin_left = margin[0]
	s.content_margin_top = margin[1]
	s.content_margin_right = margin[2]
	s.content_margin_bottom = margin[3]
	return s


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _margin(parent: Control, l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	parent.add_child(m)
	return m


func _rule(color: Color = C_LINE, thickness: int = 1) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, thickness)
	return r


## Platzhalter, falls das Vorschaubild noch nicht im Projekt liegt.
func _load_preview() -> Texture2D:
	if ResourceLoader.exists(PREVIEW_HOUSE):
		var tex := load(PREVIEW_HOUSE) as Texture2D
		if tex:
			return tex
	push_warning("MainMenu: %s fehlt - Platzhalter wird angezeigt." % PREVIEW_HOUSE)
	var g := Gradient.new()
	g.set_color(0, Color(0.2, 0.09, 0.07))
	g.set_color(1, Color(0.02, 0.02, 0.025))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.55)
	t.fill_to = Vector2(1.0, 1.0)
	t.width = 512
	t.height = 512
	return t

#endregion


#region UI-Aufbau

func _build_ui() -> void:
	# Hintergrund: Bild stark abgedunkelt + Vignette/Korn.
	var base := ColorRect.new()
	base.color = C_BG
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	move_child(base, 0)

	_background = TextureRect.new()
	_background.texture = _preview_tex
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.modulate = Color(0.32, 0.3, 0.3)
	add_child(_background)
	move_child(_background, 1)

	var fx := ColorRect.new()
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	fx.material = mat
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)
	move_child(fx, 2)

	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	_content.add_child(root)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)
	root.add_child(main)

	_build_sidebar(main)
	_build_dossier(main)
	_build_bottom_bar(root)


func _build_sidebar(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 0)
	panel.add_theme_stylebox_override("panel", _box(C_SIDEBAR, C_LINE, [0, 0, 1, 0]))
	parent.add_child(panel)

	var m := _margin(panel, 48, 48, 40, 32)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	m.add_child(box)

	box.add_child(_label("EINSATZTAFEL  ·  AKTE 07", 14, C_RED))

	var title := _label("DAS VERLASSENE\nHAUS", 58, C_TEXT)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("line_spacing", -6)
	box.add_child(title)

	var tagline := _label("Das Licht brennt noch.\nAber niemand ist zu Hause.", 17, C_DIM)
	box.add_child(tagline)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	box.add_child(gap)

	box.add_child(_label("ORT WÄHLEN", 14, C_DIM))
	box.add_child(_rule())

	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	box.add_child(cards)

	for i in LOCATIONS.size():
		_cards.append(_make_card(cards, i))


func _make_card(parent: Control, index: int) -> Button:
	var loc := LOCATIONS[index]
	var locked: bool = loc["scene"] == ""

	var b := Button.new()
	b.text = "%02d    %s" % [index + 1, loc["name"]]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", C_DIM if locked else C_TEXT)
	b.add_theme_color_override("font_hover_color", C_TEXT)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)

	var pad := [18, 0, 130, 0]
	b.add_theme_stylebox_override("normal", _box(C_CARD, C_LINE, [3, 0, 0, 0], pad))
	b.add_theme_stylebox_override("hover", _box(C_CARD_HOVER, C_DIM, [3, 0, 0, 0], pad))
	b.add_theme_stylebox_override("pressed", _box(C_CARD_ACTIVE, C_RED, [3, 0, 0, 0], pad))
	b.add_theme_stylebox_override("hover_pressed", _box(C_CARD_ACTIVE, C_RED_BRIGHT, [3, 0, 0, 0], pad))
	b.pressed.connect(_select_location.bind(index))
	parent.add_child(b)

	var tag := _label("GESPERRT" if locked else "FREIGEGEBEN", 12, C_DIM if locked else C_RED_BRIGHT)
	tag.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	tag.offset_left = -118
	tag.offset_right = -14
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tag)
	return b


func _build_dossier(parent: Control) -> void:
	var outer := MarginContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("margin_left", 56)
	outer.add_theme_constant_override("margin_right", 64)
	outer.add_theme_constant_override("margin_top", 48)
	outer.add_theme_constant_override("margin_bottom", 32)
	parent.add_child(outer)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.05, 0.045, 0.045, 0.88), C_LINE, [1, 1, 1, 1], [22, 20, 22, 22]))
	outer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_file_label = _label("", 13, C_RED)
	box.add_child(_file_label)

	# Foto im Rahmen.
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _box(Color.BLACK, C_DIM, [1, 1, 1, 1], [4, 4, 4, 4]))
	box.add_child(frame)

	_photo = TextureRect.new()
	_photo.texture = _preview_tex
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_photo.custom_minimum_size = Vector2(0, 220)
	_photo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(_photo)

	var head := HBoxContainer.new()
	box.add_child(head)
	_name_label = _label("", 34, C_TEXT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name_label)
	_status_label = _label("", 15, C_RED_BRIGHT)
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_status_label)

	_desc_label = _label("", 17, C_DIM)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_desc_label)

	box.add_child(_rule())

	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 40)
	box.add_child(info)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.0
	info.add_child(left)
	left.add_child(_label("MISSIONSZIEL", 13, C_RED))
	_objective_label = _label("", 18, C_TEXT)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_objective_label)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(right)
	right.add_child(_label("BEDROHUNGSSTUFE", 13, C_RED))
	var pip_row := HBoxContainer.new()
	pip_row.add_theme_constant_override("separation", 6)
	pip_row.custom_minimum_size = Vector2(0, 26)
	right.add_child(pip_row)
	for i in 5:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(30, 12)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip_row.add_child(pip)
		_pips.append(pip)
	_threat_text = _label("", 18, C_TEXT)
	right.add_child(_threat_text)


func _build_bottom_bar(parent: Control) -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _box(Color(0.02, 0.018, 0.02, 0.96), C_LINE, [0, 1, 0, 0], [56, 16, 64, 16]))
	parent.add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)

	_start_button = _bar_button(row, "EINSATZ STARTEN", _on_start_pressed, true)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_bar_button(row, "EINSTELLUNGEN", _on_settings_pressed, false)
	_bar_button(row, "BEENDEN", _on_quit_pressed, false)


func _bar_button(parent: Control, text: String, callback: Callable, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(300 if primary else 210, 56)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.38, 0.35, 0.33))

	var pad := [20, 0, 20, 0]
	if primary:
		b.add_theme_stylebox_override("normal", _box(Color(0.42, 0.07, 0.06), C_RED, [2, 2, 2, 2], pad))
		b.add_theme_stylebox_override("hover", _box(Color(0.58, 0.1, 0.08), C_RED_BRIGHT, [2, 2, 2, 2], pad))
		b.add_theme_stylebox_override("pressed", _box(Color(0.3, 0.05, 0.04), C_RED_BRIGHT, [2, 2, 2, 2], pad))
	else:
		b.add_theme_stylebox_override("normal", _box(Color(0.08, 0.07, 0.07), C_LINE, [1, 1, 1, 1], pad))
		b.add_theme_stylebox_override("hover", _box(Color(0.15, 0.12, 0.115), C_DIM, [1, 1, 1, 1], pad))
		b.add_theme_stylebox_override("pressed", _box(Color(0.05, 0.045, 0.045), C_DIM, [1, 1, 1, 1], pad))
	b.add_theme_stylebox_override("disabled", _box(Color(0.06, 0.055, 0.055), Color(0.16, 0.14, 0.13), [1, 1, 1, 1], pad))
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

#endregion


#region Auswahl und Aktionen

func _select_location(index: int) -> void:
	_selected = index
	var loc := LOCATIONS[index]
	var locked: bool = loc["scene"] == ""

	for i in _cards.size():
		_cards[i].set_pressed_no_signal(i == index)

	_file_label.text = "AKTE %02d  ·  %s" % [index + 1, "ZUGANG VERWEIGERT" if locked else "ZUGANG GEWÄHRT"]
	_name_label.text = loc["name"]
	_status_label.text = "▮ GESPERRT" if locked else "▮ SPIELBAR"
	_status_label.add_theme_color_override("font_color", C_DIM if locked else C_RED_BRIGHT)
	_desc_label.text = loc["description"]
	_objective_label.text = loc["objective"]

	var threat: int = loc["threat"]
	for i in _pips.size():
		_pips[i].color = C_RED if i < threat else Color(0.2, 0.17, 0.16)
	_threat_text.text = "%d / 5" % threat

	_start_button.disabled = locked
	_start_button.text = "DEMNÄCHST VERFÜGBAR" if locked else "EINSATZ STARTEN"

	# Gesperrte Orte erscheinen abgedunkelt und entsättigt.
	_photo.modulate = Color(0.3, 0.3, 0.33) if locked else Color.WHITE
	_background.modulate = Color(0.16, 0.16, 0.18) if locked else Color(0.32, 0.3, 0.3)


func _on_start_pressed() -> void:
	var path: String = LOCATIONS[_selected]["scene"]
	if path == "":
		return
	get_tree().change_scene_to_file(path)


func _on_settings_pressed() -> void:
	_content.visible = false
	_settings.open_menu()


func _on_settings_closed() -> void:
	_content.visible = true


func _on_quit_pressed() -> void:
	get_tree().quit()

#endregion


#region Ambience

func _start_ambience() -> void:
	var stream := GameAudio.single("house_ambience", true)
	if stream == null:
		return
	_room_hum.stream = stream
	_room_hum.volume_db = -60.0
	_room_hum.play()
	create_tween().tween_property(_room_hum, "volume_db", -22.0, 3.0)

#endregion
