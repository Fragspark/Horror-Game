extends Node
## Bildqualitaet (Autoload "GraphicsSettings").
##
## Haelt Anti-Aliasing, MSAA, Anisotropic Filtering und 3D-Aufloesungsskalierung
## und wendet sie am Root-Viewport an. Laedt die Werte beim Start aus
## user://horror_settings.cfg (Sektion "quality"), also schon im Hauptmenue.
## Das Menue (simple_settings.gd) aendert die Werte ueber set_* und speichert
## die Datei selbst; hier wird nur gelesen.

const SETTINGS_FILE := "user://horror_settings.cfg"
const SECTION := "quality"

enum AAMode { OFF, FXAA, SMAA, TAA, FSR2 }
enum Profile { LOW, HIGH, MAX, CUSTOM }

const AA_LABELS := ["Aus", "FXAA", "SMAA", "TAA", "FSR 2 (nativ)"]
const MSAA_LABELS := ["Aus", "2x", "4x"]
const AF_LABELS := ["Aus", "4x", "8x", "16x"]
const PROFILE_LABELS := ["Niedrig", "Hoch", "Maximal"]

const MSAA_MODES := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
const AF_MODES := [
	Viewport.ANISOTROPY_DISABLED,
	Viewport.ANISOTROPY_4X,
	Viewport.ANISOTROPY_8X,
	Viewport.ANISOTROPY_16X,
]

const SCALE_MIN := 0.5
const SCALE_MAX := 1.5

## Profil -> Werte (aa, msaa, af, scale); Indizes in die Label-Listen oben.
const PROFILES := [
	{"aa": AAMode.FXAA, "msaa": 0, "af": 1, "scale": 1.0},
	{"aa": AAMode.SMAA, "msaa": 1, "af": 2, "scale": 1.0},
	{"aa": AAMode.FSR2, "msaa": 2, "af": 3, "scale": 1.0},
]
const DEFAULT_PROFILE := Profile.HIGH

var aa_mode: int = PROFILES[DEFAULT_PROFILE]["aa"]
var msaa_index: int = PROFILES[DEFAULT_PROFILE]["msaa"]
var af_index: int = PROFILES[DEFAULT_PROFILE]["af"]
var render_scale: float = PROFILES[DEFAULT_PROFILE]["scale"]


func _ready() -> void:
	load_from_file()
	apply()


func load_from_file() -> void:
	var file := ConfigFile.new()
	if file.load(SETTINGS_FILE) != OK:
		return
	aa_mode = clampi(file.get_value(SECTION, "aa", aa_mode), 0, AA_LABELS.size() - 1)
	msaa_index = clampi(file.get_value(SECTION, "msaa", msaa_index), 0, MSAA_LABELS.size() - 1)
	af_index = clampi(file.get_value(SECTION, "af", af_index), 0, AF_LABELS.size() - 1)
	render_scale = clampf(file.get_value(SECTION, "scale", render_scale), SCALE_MIN, SCALE_MAX)


## Schreibt die Werte in das uebergebene ConfigFile (der Menue-Code speichert).
func store(file: ConfigFile) -> void:
	file.set_value(SECTION, "aa", aa_mode)
	file.set_value(SECTION, "msaa", msaa_index)
	file.set_value(SECTION, "af", af_index)
	file.set_value(SECTION, "scale", render_scale)


func apply_profile(profile: int) -> void:
	var p: Dictionary = PROFILES[profile]
	aa_mode = p["aa"]
	msaa_index = p["msaa"]
	af_index = p["af"]
	render_scale = p["scale"]
	apply()


## Gibt das passende Profil zurueck, sonst CUSTOM.
func current_profile() -> int:
	for i in PROFILES.size():
		var p: Dictionary = PROFILES[i]
		if p["aa"] == aa_mode and p["msaa"] == msaa_index and p["af"] == af_index \
				and is_equal_approx(p["scale"], render_scale):
			return i
	return Profile.CUSTOM


func apply() -> void:
	var vp := get_tree().root
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa_mode == AAMode.FXAA \
			else (Viewport.SCREEN_SPACE_AA_SMAA if aa_mode == AAMode.SMAA \
			else Viewport.SCREEN_SPACE_AA_DISABLED)
	vp.use_taa = aa_mode == AAMode.TAA
	vp.msaa_3d = MSAA_MODES[msaa_index]
	vp.anisotropic_filtering_level = AF_MODES[af_index]

	# FSR 2 ersetzt TAA und arbeitet "nativ" bei Skalierung 1.0; sonst bilinear.
	if aa_mode == AAMode.FSR2:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.scaling_3d_scale = 1.0
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = render_scale
