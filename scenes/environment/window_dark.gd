extends Node3D
## Fenster fuer die Nachbarhaeuser. Ursprung = Mitte der Fensteroeffnung auf der
## Wandaussenflaeche, Blickrichtung (nach aussen) = +Z. Baut Rahmen, Sprossen und
## Glas per Code. `lit` = schwach warm beleuchtet (mit leichtem Flackern).

@export var size: Vector2 = Vector2(0.9, 1.3)
@export var lit: bool = false
@export var cross_bars: bool = true
@export var round_window: bool = false
@export var flicker: bool = true
@export var light_energy: float = 0.5

static var _frame_mat: StandardMaterial3D
static var _glass_dark: StandardMaterial3D
static var _glass_lit: StandardMaterial3D

var _light: OmniLight3D
var _t := 0.0
var _rng := RandomNumberGenerator.new()


static func _mats() -> void:
	if _frame_mat:
		return
	var trim := load("res://assets/materials/wood_trim.tres") as StandardMaterial3D
	_frame_mat = trim.duplicate() as StandardMaterial3D
	_frame_mat.albedo_color = Color(0.5, 0.48, 0.45)
	_glass_dark = StandardMaterial3D.new()
	_glass_dark.albedo_color = Color(0.015, 0.022, 0.035)
	_glass_dark.roughness = 0.25
	_glass_dark.metallic_specular = 0.5
	_glass_lit = StandardMaterial3D.new()
	_glass_lit.albedo_color = Color(0.12, 0.09, 0.05)
	_glass_lit.emission_enabled = true
	_glass_lit.emission = Color(1.0, 0.62, 0.28)
	_glass_lit.emission_energy_multiplier = 0.9
	_glass_lit.roughness = 0.6


func _box(nm: String, pos: Vector3, sz: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


func _ready() -> void:
	_mats()
	_rng.randomize()
	var w := size.x
	var h := size.y
	var t := 0.07
	if round_window:
		var cm := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = w * 0.5
		cyl.bottom_radius = w * 0.5
		cyl.height = 0.03
		cyl.radial_segments = 14
		cm.mesh = cyl
		cm.rotation_degrees = Vector3(90, 0, 0)
		cm.position = Vector3(0, 0, 0.012)
		cm.material_override = _glass_lit if lit else _glass_dark
		add_child(cm)
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = w * 0.5
		tor.outer_radius = w * 0.5 + 0.06
		tor.rings = 14
		tor.ring_segments = 5
		ring.mesh = tor
		ring.rotation_degrees = Vector3(90, 0, 0)
		ring.position = Vector3(0, 0, 0.03)
		ring.material_override = _frame_mat
		add_child(ring)
	else:
		_box("Glass", Vector3(0, 0, 0.01), Vector3(w, h, 0.02), _glass_lit if lit else _glass_dark)
		_box("FrameL", Vector3(-(w + t) * 0.5, 0, 0.03), Vector3(t, h + 2.0 * t, 0.08), _frame_mat)
		_box("FrameR", Vector3((w + t) * 0.5, 0, 0.03), Vector3(t, h + 2.0 * t, 0.08), _frame_mat)
		_box("FrameT", Vector3(0, (h + t) * 0.5, 0.03), Vector3(w + 2.0 * t, t, 0.08), _frame_mat)
		_box("FrameB", Vector3(0, -(h + t) * 0.5, 0.03), Vector3(w + 2.0 * t, t, 0.08), _frame_mat)
		# Fensterbrett
		_box("Sill", Vector3(0, -(h + t) * 0.5 - 0.035, 0.07), Vector3(w + 0.22, 0.05, 0.16), _frame_mat)
		if cross_bars:
			_box("BarV", Vector3(0, 0, 0.03), Vector3(0.035, h, 0.04), _frame_mat)
			_box("BarH", Vector3(0, h * 0.12, 0.03), Vector3(w, 0.035, 0.04), _frame_mat)
	if lit:
		_light = OmniLight3D.new()
		_light.position = Vector3(0, 0, 0.5)
		_light.light_color = Color(1.0, 0.62, 0.3)
		_light.light_energy = light_energy
		_light.omni_range = 5.0
		_light.omni_attenuation = 1.4
		_light.light_volumetric_fog_energy = 0.8
		_light.shadow_enabled = false
		add_child(_light)
	set_process(lit and flicker)


func _process(delta: float) -> void:
	_t += delta
	if _light == null:
		return
	# ruhiges, leicht unregelmaessiges Kerzen-/Fernsehflackern, selten ein kurzer Einbruch
	var f := 0.88 + 0.12 * sin(_t * 7.3) * sin(_t * 2.1 + 1.0) + _rng.randf_range(-0.04, 0.04)
	if _rng.randf() < 0.004:
		f *= 0.25
	_light.light_energy = light_energy * f
	_glass_lit.emission_energy_multiplier = 0.9 * f
