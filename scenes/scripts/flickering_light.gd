extends OmniLight3D
## Unregelmaessiges Flackern fuer eine defekte Deckenlampe im Wohnhaus.
## Wechselt zwischen stabilem (aber nie ganz ruhigem) Leuchten, kurzen
## Aussetzern und schnellen Flacker-Schueben.

@export_group("Helligkeit")
## Grundhelligkeit der Lampe (wird mit dem Level multipliziert).
@export var base_energy: float = 2.2
## Minimaler Level im eingeschalteten Zustand (0 = komplett aus).
@export var min_on_level: float = 0.45
## Globaler Faktor auf die Lichtenergie (damit die Lampen den Boden erreichen).
@export var brightness_scale: float = 2.2

## Zufaelliges Dauerflackern an/aus (force_flicker() und fail() gehen immer).
@export var random_flicker: bool = false

@export_group("Timing")
@export var min_steady_time: float = 1.0
@export var max_steady_time: float = 5.0
@export var min_blackout_time: float = 0.12
@export var max_blackout_time: float = 1.3
@export var min_burst_time: float = 0.25
@export var max_burst_time: float = 1.5

@export_group("Optik")
## Emissives Material des Leuchtkoerpers. Wird mit dem Lichtlevel mitgezogen.
@export var fixture_material: StandardMaterial3D
## Emissionsstaerke des Leuchtkoerpers bei vollem Level.
@export var fixture_emission_when_on: float = 3.0
## Helligkeit der Gluehbirne bei vollem Level (HDR, damit sie klar heller als
## der Schirm wirkt).
@export var bulb_boost: float = 3.0
## Emissionsstaerke der Glas-Tulpen des Kronleuchters bei vollem Level.
@export var chandelier_bulb_emission: float = 1.5
## Radius der Gluehbirnen, die in die Kronleuchter-Schirme gesetzt werden
## (das Modell hat selbst keine).
@export var chandelier_bulb_radius: float = 0.035
## Feinjustage der Birnen-Hoehe relativ zum Mittelpunkt der Modell-Teile.
@export var chandelier_bulb_lift: float = -0.075

var _rng := RandomNumberGenerator.new()
var _state_time: float = 0.0
var _burst_time: float = 0.0
var _burst_active: bool = false
var _level: float = 1.0

## Erzwungenes heftiges Flackern (z.B. beim Start des Generators).
var _distress_time: float = 0.0
var _is_in_distress: bool = false
var _base_energy: float = 0.0

## Dauerhaft ausgefallen (z.B. nachdem der Spieler das erste Item genommen hat).
var _failed: bool = false

## Pro Lampe eigene Kopien der Leuchtkoerper-Materialien (Gluehbirne bzw.
## Schirme des Kronleuchters), damit sie mit dem Lichtlevel mitgehen.
var _bulb_materials: Array[StandardMaterial3D] = []
var _bulb_base_colors: Array[Color] = []
var _shade_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	add_to_group("ceiling_lights")
	_rng.randomize()
	_base_energy = base_energy
	_setup_fixture_materials()
	_enter_steady()


## Laesst das Licht fuer die angegebene Dauer heftig und unregelmaessig flackern.
## Wird z.B. vom Generator ausgeloest.
func force_flicker(duration: float = 2.0) -> void:
	if _failed:
		return
	_distress_time = duration
	_is_in_distress = true


## Schaltet die Lampe dauerhaft aus (z.B. wenn die Stromversorgung kollabiert).
## Die Lampe reagiert danach nicht mehr auf force_flicker().
func fail() -> void:
	if _failed:
		return
	_failed = true
	_is_in_distress = false
	_burst_active = false
	_state_time = 0.0
	_level = 0.0
	_apply_level(0.0)
	set_process(false)


func _process(delta: float) -> void:
	# Erzwungenes Flackern hat Vorrang vor dem normalen Zufallsverhalten.
	if _is_in_distress:
		_distress_time -= delta
		if _distress_time <= 0.0:
			_is_in_distress = false
			_level = _rng.randf_range(min_on_level, 1.0)
			_enter_steady()
		else:
			# Harte Spruenge: haeufiger komplett aus, dazwischen grell.
			var roll := _rng.randf()
			if roll < 0.55:
				_level = 0.0
			elif roll < 0.8:
				_level = _rng.randf_range(min_on_level, 1.0)
			else:
				# kurzzeitige Ueberhelligkeit fuer den "Kurzschluss"-Look
				_level = _rng.randf_range(1.0, 1.35)
		_apply_level(_level)
		return

	# Zufaelliges Flackern ist abgeschaltet -> Lampe leuchtet stabil.
	if not random_flicker:
		_level = 1.0
		_apply_level(_level)
		return

	if _burst_active:
		_burst_time -= delta
		if _burst_time <= 0.0:
			_burst_active = false
			_level = _rng.randf_range(min_on_level, 1.0)
		else:
			# Schnelle, unregelmaessige Spruenge zwischen aus und fast voll.
			_level = 0.0 if _rng.randf() < 0.45 else _rng.randf_range(min_on_level, 1.0)
		_apply_level(_level)
		return

	_state_time -= delta
	if _state_time <= 0.0:
		var roll := _rng.randf()
		if roll < 0.28:
			_enter_blackout()
		elif roll < 0.62:
			_enter_burst()
		else:
			_enter_steady()
	else:
		# Leichtes Zittern, damit das Licht nie wirklich ruhig wirkt.
		_level = clampf(_level + _rng.randf_range(-0.04, 0.04), min_on_level, 1.0)

	_apply_level(_level)


func _enter_steady() -> void:
	_state_time = _rng.randf_range(min_steady_time, max_steady_time)
	_level = _rng.randf_range(min_on_level, 1.0)


func _enter_blackout() -> void:
	_state_time = _rng.randf_range(min_blackout_time, max_blackout_time)
	_level = 0.0


func _enter_burst() -> void:
	_burst_active = true
	_burst_time = _rng.randf_range(min_burst_time, max_burst_time)
	_level = _rng.randf_range(min_on_level, 1.0)


## Gluehbirne ("Bulb", unshaded) und Kronleuchter-Schirme bekommen eigene
## Material-Kopien, damit sie bei Flackern/Ausfall dunkel werden.
func _setup_fixture_materials() -> void:
	var bulb := get_node_or_null("Bulb") as MeshInstance3D
	if bulb:
		var mat := bulb.get_active_material(0) as StandardMaterial3D
		if mat:
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var copy := mat.duplicate() as StandardMaterial3D
			bulb.set_surface_override_material(0, copy)
			_bulb_materials.append(copy)
			_bulb_base_colors.append(copy.albedo_color)
	var chandelier := get_node_or_null("Chandelier")
	if chandelier:
		for mi in chandelier.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for i in m.mesh.get_surface_count():
				var mat := m.get_active_material(i) as StandardMaterial3D
				if mat == null or not mat.resource_name.to_lower().begins_with("lamps"):
					continue
				var copy := mat.duplicate() as StandardMaterial3D
				copy.emission_enabled = true
				copy.emission = Color(1.0, 0.82, 0.55)
				m.set_surface_override_material(i, copy)
				_shade_materials.append(copy)
				_add_chandelier_bulbs(chandelier as Node3D, m, i)


## Das Kronleuchter-Modell hat keine Gluehbirnen. Pro Arm (Cluster der
## Glas-Tulpen um die Mitte) wird eine emissive Kugel in den Schirm gesetzt.
func _add_chandelier_bulbs(root: Node3D, mi: MeshInstance3D, surface: int) -> void:
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return
	var to_root := root.global_transform.affine_inverse() * mi.global_transform
	# Nach Winkel um die Mitte (Modell-Hoehe ist die z-Achse des Meshes) in
	# sechs Sektoren teilen; je Sektor den Mittelpunkt bestimmen.
	var sectors := {}
	for v in verts:
		var k := int(floor((atan2(v.y, v.x) + PI) / (TAU / 6.0)))
		if not sectors.has(k):
			sectors[k] = {"sum": Vector3.ZERO, "n": 0}
		var w := to_root * v
		sectors[k]["sum"] += w
		sectors[k]["n"] += 1
	var sphere := SphereMesh.new()
	sphere.radius = chandelier_bulb_radius
	sphere.height = chandelier_bulb_radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	for k in sectors:
		var c: Vector3 = sectors[k]["sum"] / float(sectors[k]["n"])
		var bulb := MeshInstance3D.new()
		bulb.mesh = sphere
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.85, 0.62)
		bulb.material_override = mat
		root.add_child(bulb)
		bulb.position = Vector3(c.x, c.y + chandelier_bulb_lift, c.z)
		_bulb_materials.append(mat)
		_bulb_base_colors.append(mat.albedo_color)


func _apply_level(level: float) -> void:
	for i in _bulb_materials.size():
		var c := _bulb_base_colors[i]
		var k := level * bulb_boost
		_bulb_materials[i].albedo_color = Color(c.r * k, c.g * k, c.b * k, c.a)
	for mat in _shade_materials:
		mat.emission_energy_multiplier = chandelier_bulb_emission * level
	light_energy = _base_energy * brightness_scale * level
	if fixture_material:
		fixture_material.emission_energy_multiplier = fixture_emission_when_on * level
