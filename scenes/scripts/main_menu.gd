extends Control
## Atmosphaerisches Hauptmenue: Das Haus bei Nacht als lebender 3D-Hintergrund.
##
## Links oben der Titel, links unten das Textmenue (Ortswahl, Einsatz starten,
## Einstellungen, Beenden), rechts unten ein schlichter Infoblock zum gewaehlten
## Ort mit Foto. Keine Panels, kaum Rahmen - das Bild traegt die Stimmung.
## Das UI entsteht komplett im Code.
##
## Tab ist hier gesperrt; ESC schliesst nur das Einstellungs-Overlay (das
## behandelt simple_settings selbst).

const UIStyle = preload("res://scenes/scripts/ui_style.gd")
const BACKDROP := preload("res://scenes/scripts/menu_backdrop.gd")

const GAME_SCENE := "res://scenes/horror_main.tscn"
const PREVIEW_HOUSE := "res://assets/ui/preview_house.png"

const FILM_SHADER := """
shader_type canvas_item;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float d = distance(UV, vec2(0.5, 0.5));
	float vig = smoothstep(0.35, 0.95, d);
	float grain = hash(floor(UV * vec2(1280.0, 720.0)) + fract(TIME) * 37.0);
	float flicker = 0.02 * sin(TIME * 9.0) * sin(TIME * 2.3);
	COLOR = vec4(vec3(grain * 0.5), clamp(0.05 + vig * 0.8 + flicker, 0.0, 1.0));
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
var _entries: Array[Button] = []
var _content: Control
var _fade: ColorRect
var _title: Label
var _info: Control
var _photo: TextureRect
var _name_label: Label
var _status_label: Label
var _desc_label: Label
var _objective_label: Label
var _pips: Array[ColorRect] = []
var _start_button: Button
var _preview_tex: Texture2D
var _serif: Font
var _starting: bool = false
var _flicker_timer: float = 6.0


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_settings.menu_mode = true
	_settings.closed.connect(_on_settings_closed)

	_serif = _make_serif()
	_preview_tex = _load_preview()
	_build_ui()
	_select_location(0)
	_start_ambience()
	_intro()


func _process(delta: float) -> void:
	# Titel flackert gelegentlich kurz, wie eine defekte Leuchtreklame.
	_flicker_timer -= delta
	if _flicker_timer <= 0.0 and _title and _content.visible:
		_flicker_timer = randf_range(5.0, 11.0)
		var tw := create_tween()
		for i in 4:
			tw.tween_property(_title, "modulate:a", randf_range(0.15, 0.5), 0.05)
			tw.tween_property(_title, "modulate:a", 1.0, randf_range(0.04, 0.12))


## Tab bleibt gesperrt, ESC wird ohne offenes Overlay verworfen.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_TAB or key.keycode == KEY_TAB:
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and not _settings.is_open():
		get_viewport().set_input_as_handled()


#region Hilfsfunktionen

## Serifenschrift fuer den Titel; faellt auf die Standardschrift zurueck.
func _make_serif() -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Times New Roman", "serif"])
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var fv := FontVariation.new()
	fv.base_font = sf
	fv.spacing_glyph = 6
	return fv


func _label(text: String, size: int, color: Color, font: Font = null) -> Label:
	var l := UIStyle.label(text, size, color)
	if font:
		l.add_theme_font_override("font", font)
	return l


func _rule(width: float = 0.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = UIStyle.C_LINE
	r.custom_minimum_size = Vector2(width, 1)
	return r


## Platzhalter, falls das Vorschaubild noch nicht im Projekt liegt.
func _load_preview() -> Texture2D:
	if ResourceLoader.exists(PREVIEW_HOUSE):
		var tex := load(PREVIEW_HOUSE) as Texture2D
		if tex:
			return tex
	push_warning("MainMenu: %s fehlt - Platzhalter wird angezeigt." % PREVIEW_HOUSE)
	var g := Gradient.new()
	g.set_color(0, Color(0.12, 0.14, 0.2))
	g.set_color(1, Color(0.015, 0.02, 0.03))
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
	# 3D-Hintergrund in einem eigenen Viewport.
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	move_child(svc, 0)
	var vp := SubViewport.new()
	vp.handle_input_locally = false
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	var backdrop := Node3D.new()
	backdrop.set_script(BACKDROP)
	vp.add_child(backdrop)

	# Verlauf nach unten, damit der Text lesbar bleibt, plus Vignette/Korn.
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.0))
	grad.set_color(1, Color(0.0, 0.005, 0.015, 0.88))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.35)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 4
	gt.height = 256
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	move_child(shade, 1)

	var fx := ColorRect.new()
	var shader := Shader.new()
	shader.code = FILM_SHADER
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

	_build_title()
	_build_menu()
	_build_info()

	# Schwarzblende fuer Ein- und Ausblenden.
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _build_title() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.offset_left = 96
	box.offset_top = 70
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(box)

	box.add_child(_label("EINE UNTERSUCHUNG", 14, UIStyle.C_ACCENT))

	_title = _label("DAS VERLASSENE\nHAUS", 84, UIStyle.C_TEXT, _serif)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_title.add_theme_constant_override("shadow_offset_x", 4)
	_title.add_theme_constant_override("shadow_offset_y", 4)
	_title.add_theme_constant_override("line_spacing", -14)
	box.add_child(_title)

	box.add_child(_label("Das Licht brennt noch. Aber niemand ist zu Hause.", 17, UIStyle.C_DIM))


func _build_menu() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_left = 96
	box.offset_bottom = -72
	box.custom_minimum_size = Vector2(430, 0)
	box.add_theme_constant_override("separation", 2)
	_content.add_child(box)

	box.add_child(_label("ORT WÄHLEN", 13, UIStyle.C_DIM))
	for i in LOCATIONS.size():
		var b := _menu_entry(box, "%02d – %s" % [i + 1, LOCATIONS[i]["name"]], 21)
		b.pressed.connect(_select_location.bind(i))
		_entries.append(b)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	box.add_child(gap)

	_start_button = _menu_entry(box, "Einsatz starten", 30)
	_start_button.pressed.connect(_on_start_pressed)

	var s := _menu_entry(box, "Einstellungen", 24)
	s.pressed.connect(_on_settings_pressed)
	var q := _menu_entry(box, "Beenden", 24)
	q.pressed.connect(_on_quit_pressed)


## Flacher Texteintrag ohne Kasten: dunkel, bei Hover hell mit Akzent-Balken.
func _menu_entry(parent: Control, text: String, size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", _serif)
	b.add_theme_color_override("font_color", UIStyle.C_DIM)
	b.add_theme_color_override("font_hover_color", UIStyle.C_TEXT)
	b.add_theme_color_override("font_pressed_color", UIStyle.C_ACCENT_BRIGHT)
	b.add_theme_color_override("font_hover_pressed_color", UIStyle.C_ACCENT_BRIGHT)
	b.add_theme_color_override("font_disabled_color", Color(0.28, 0.3, 0.34))
	var pad := [18, 4, 8, 4]
	var none := UIStyle.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), [0, 0, 0, 0], pad)
	var hover := UIStyle.box(Color(0.9, 0.62, 0.3, 0.06), UIStyle.C_ACCENT, [2, 0, 0, 0], pad)
	b.add_theme_stylebox_override("normal", none)
	b.add_theme_stylebox_override("disabled", none)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("hover_pressed", hover)
	parent.add_child(b)
	return b


func _build_info() -> void:
	_info = VBoxContainer.new()
	_info.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info.offset_right = -96
	_info.offset_bottom = -72
	_info.custom_minimum_size = Vector2(470, 0)
	_info.add_theme_constant_override("separation", 10)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_info)

	# Foto, leicht schief wie ein aufgepinntes Polaroid.
	var photo_row := HBoxContainer.new()
	photo_row.alignment = BoxContainer.ALIGNMENT_END
	photo_row.custom_minimum_size = Vector2(0, 190)
	_info.add_child(photo_row)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(290, 180)
	frame.pivot_offset = Vector2(145, 90)
	frame.rotation_degrees = 2.2
	frame.add_theme_stylebox_override("panel", UIStyle.box(Color(0.82, 0.8, 0.74), Color(0, 0, 0, 0), [0, 0, 0, 0], [8, 8, 8, 8]))
	photo_row.add_child(frame)
	_photo = TextureRect.new()
	_photo.texture = _preview_tex
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(_photo)

	var head := HBoxContainer.new()
	_info.add_child(head)
	_name_label = _label("", 28, UIStyle.C_TEXT, _serif)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name_label)
	_status_label = _label("", 13, UIStyle.C_ACCENT)
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_status_label)

	_desc_label = _label("", 15, UIStyle.C_DIM)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(_desc_label)

	_info.add_child(_rule())

	var goal := HBoxContainer.new()
	goal.add_theme_constant_override("separation", 14)
	_info.add_child(goal)
	goal.add_child(_label("ZIEL", 12, UIStyle.C_ACCENT))
	_objective_label = _label("", 15, UIStyle.C_TEXT)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal.add_child(_objective_label)

	var threat := HBoxContainer.new()
	threat.add_theme_constant_override("separation", 14)
	_info.add_child(threat)
	threat.add_child(_label("GEFAHR", 12, UIStyle.C_ACCENT))
	var pip_row := HBoxContainer.new()
	pip_row.add_theme_constant_override("separation", 5)
	threat.add_child(pip_row)
	for i in 5:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(26, 6)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip_row.add_child(pip)
		_pips.append(pip)

#endregion


#region Auswahl und Aktionen

func _select_location(index: int) -> void:
	_selected = index
	var loc := LOCATIONS[index]
	var locked: bool = loc["scene"] == ""

	for i in _entries.size():
		var active := i == index
		var c: Color = UIStyle.C_ACCENT_BRIGHT if active else UIStyle.C_DIM
		_entries[i].add_theme_color_override("font_color", c)
		_entries[i].text = ("›  " if active else "   ") + "%02d – %s" % [i + 1, LOCATIONS[i]["name"]]

	_name_label.text = loc["name"]
	_status_label.text = "GESPERRT" if locked else "SPIELBAR"
	_status_label.add_theme_color_override("font_color", UIStyle.C_DIM if locked else UIStyle.C_ACCENT)
	_desc_label.text = loc["description"]
	_objective_label.text = loc["objective"]

	var threat: int = loc["threat"]
	for i in _pips.size():
		_pips[i].color = UIStyle.C_DANGER if i < threat else Color(0.14, 0.16, 0.2)

	_start_button.disabled = locked
	_start_button.text = "Demnächst verfügbar" if locked else "Einsatz starten"
	_photo.modulate = Color(0.35, 0.37, 0.42) if locked else Color.WHITE


func _intro() -> void:
	_content.modulate.a = 0.0
	_fade.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 2.2)
	tw.parallel().tween_property(_content, "modulate:a", 1.0, 1.8).set_delay(1.0)


func _on_start_pressed() -> void:
	var path: String = LOCATIONS[_selected]["scene"]
	if path == "" or _starting:
		return
	_starting = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.8)
	tw.parallel().tween_property(_room_hum, "volume_db", -60.0, 0.8)
	tw.tween_callback(get_tree().change_scene_to_file.bind(path))


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
	create_tween().tween_property(_room_hum, "volume_db", -18.0, 3.0)

#endregion
