extends RefCounted
## Gemeinsame Farben und Stil-Helfer fuer das duestere Ermittler-UI
## (Einstellungs-/Pausemenue, Game-Over- und Sieg-Screen).
## Nutzung: const UIStyle = preload("res://scenes/scripts/ui_style.gd")

const C_PANEL := Color(0.035, 0.04, 0.05, 0.96)
const C_CARD := Color(0.06, 0.07, 0.085, 0.9)
const C_CARD_HOVER := Color(0.1, 0.115, 0.14, 0.95)
const C_CARD_ACTIVE := Color(0.14, 0.11, 0.07, 0.97)
const C_LINE := Color(0.2, 0.24, 0.3)
const C_TEXT := Color(0.82, 0.85, 0.88)
const C_DIM := Color(0.46, 0.5, 0.56)
## Warmer Akzent (Fensterlicht) - das einzige Warme im kalten Nachtblau.
const C_ACCENT := Color(0.9, 0.62, 0.3)
const C_ACCENT_BRIGHT := Color(1.0, 0.74, 0.42)
## Echtes Rot nur fuer Gefahr (Bedrohungsstufe, Game Over).
const C_DANGER := Color(0.78, 0.13, 0.1)

## Dimmer mit leichtem Unschaerfe-Effekt ueber dem Spielbild.
const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 5.0) = 2.5;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 0.7);
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	COLOR = vec4(mix(c, tint.rgb, tint.a), 1.0);
}
"""


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: Array = [0, 0, 0, 0], margin: Array = [0, 0, 0, 0]) -> StyleBoxFlat:
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


static func label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Schaltflaeche im Akten-Stil. primary = roter Hauptknopf.
static func style_button(b: Button, primary: bool = false, font_size: int = 20) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.38, 0.35, 0.33))
	var pad := [20, 0, 20, 0]
	if primary:
		b.add_theme_stylebox_override("normal", box(Color(0.16, 0.1, 0.05), C_ACCENT, [2, 2, 2, 2], pad))
		b.add_theme_stylebox_override("hover", box(Color(0.26, 0.16, 0.07), C_ACCENT_BRIGHT, [2, 2, 2, 2], pad))
		b.add_theme_stylebox_override("pressed", box(Color(0.1, 0.065, 0.03), C_ACCENT_BRIGHT, [2, 2, 2, 2], pad))
	else:
		b.add_theme_stylebox_override("normal", box(Color(0.05, 0.058, 0.07), C_LINE, [1, 1, 1, 1], pad))
		b.add_theme_stylebox_override("hover", box(Color(0.1, 0.115, 0.14), C_DIM, [1, 1, 1, 1], pad))
		b.add_theme_stylebox_override("pressed", box(Color(0.05, 0.045, 0.045), C_DIM, [1, 1, 1, 1], pad))
	b.add_theme_stylebox_override("disabled", box(Color(0.06, 0.055, 0.055), Color(0.16, 0.14, 0.13), [1, 1, 1, 1], pad))


## Slider im dunklen Stil: schmale Rille, rote Fuellung.
static func style_slider(s: HSlider) -> void:
	var groove := box(Color(0.16, 0.14, 0.13))
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	var fill := box(C_ACCENT)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", groove)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.focus_mode = Control.FOCUS_NONE
