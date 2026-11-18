extends Node3D
## 3D-Hintergrund fuers Hauptmenue: das Haus bei Nacht, von der Strasse aus.
##
## Alles entsteht im Code: Nachbarschaft (neighborhood.tscn), das Haus
## (house_exterior.tscn, identisch zum Spiel), zwei beleuchtete Fenster (eines flackert), Mond,
## Nebel und eine langsame Kamerafahrt. Gelegentlich steht eine dunkle Gestalt
## im oberen Fenster.

const NEIGHBORHOOD := preload("res://scenes/environment/neighborhood.tscn")
const FLICKER := preload("res://scenes/scripts/flickering_light.gd")
const SKY_SHADER := preload("res://assets/materials/night_sky.gdshader")
const HOUSE := preload("res://scenes/environment/house_exterior.tscn")

var camera: Camera3D
var _t: float = 0.0
var _figure: Node3D
var _figure_timer: float = 14.0


func _ready() -> void:
	var nb := NEIGHBORHOOD.instantiate()
	nb.set("forest_density", 0.55)
	add_child(nb)

	_build_environment()
	_build_house()

	camera = Camera3D.new()
	camera.fov = 52.0
	camera.near = 0.1
	camera.far = 160.0
	add_child(camera)
	camera.make_current()
	_update_camera()


func _process(delta: float) -> void:
	_t += delta
	_update_camera()
	_figure_timer -= delta
	if _figure_timer <= 0.0 and _figure:
		_figure.visible = not _figure.visible
		_figure_timer = 1.6 if _figure.visible else randf_range(16.0, 32.0)


## Sehr langsame Fahrt auf das Haus zu mit leichtem Schwanken (Handkamera).
func _update_camera() -> void:
	if camera == null:
		return
	var drift := fmod(_t, 90.0) / 90.0
	var pos := Vector3(
		-1.2 + sin(_t * 0.13) * 0.45,
		1.55 + sin(_t * 0.27) * 0.04,
		23.0 - drift * 3.0)
	camera.position = pos
	camera.look_at(Vector3(-0.8 + sin(_t * 0.09) * 0.3, 3.8, 0.0), Vector3.UP)


func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("zenith_color", Color(0.008, 0.014, 0.036))
	sky_mat.set_shader_parameter("horizon_color", Color(0.075, 0.095, 0.155))
	sky_mat.set_shader_parameter("ground_color", Color(0.02, 0.026, 0.04))
	sky_mat.set_shader_parameter("star_strength", 0.25)
	sky_mat.set_shader_parameter("cloud_amount", 0.6)
	sky_mat.set_shader_parameter("moon_size", 0.034)
	sky_mat.set_shader_parameter("moon_color", Color(0.72, 0.84, 1.0))
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = 8.0
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.24, 0.31, 0.46)
	env.ambient_light_energy = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.05, 0.065, 0.1)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.2
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.24, 0.29, 0.38)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 48.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.65
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-38.0, 150.0, 0.0)
	moon.light_color = Color(0.62, 0.73, 1.0)
	moon.light_energy = 0.4
	moon.light_volumetric_fog_energy = 1.4
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	add_child(moon)


## Das echte Haus aus dem Spiel (Aussenhuelle ohne Innenleben), damit Menue und
## Spiel dasselbe Gebaeude zeigen. Erzeugt mit house_exterior.tscn.
func _build_house() -> void:
	var house := HOUSE.instantiate()
	house.name = "MenuHouse"
	add_child(house)

	var front_z := 6.0
	# Warmes Licht hinter dem oberen Fenster (flackert) und im Erdgeschoss.
	_add_window_light(Vector3(1.6, 5.0, front_z - 1.0), 3.4, true)
	_add_window_light(Vector3(-4.4, 1.6, front_z - 1.0), 2.4, false)

	# Dunkle Gestalt im flackernden Fenster.
	_figure = Node3D.new()
	_figure.position = Vector3(1.6, 4.45, front_z - 0.35)
	_figure.visible = false
	var black := StandardMaterial3D.new()
	black.albedo_color = Color.BLACK
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var body := CSGCylinder3D.new()
	body.radius = 0.2
	body.height = 1.1
	body.material = black
	body.position = Vector3(0, 0.3, 0)
	_figure.add_child(body)
	var head := CSGSphere3D.new()
	head.radius = 0.17
	head.material = black
	head.position = Vector3(0, 1.05, 0)
	_figure.add_child(head)
	add_child(_figure)

	# Verandalampe.
	_add_window_light(Vector3(1.0, 2.5, front_z + 1.6), 1.4, false, Color(1.0, 0.78, 0.5))


func _add_window_light(pos: Vector3, energy: float, flicker: bool, color: Color = Color(1.0, 0.68, 0.34)) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 16.0
	l.light_volumetric_fog_energy = 1.5
	l.shadow_enabled = false
	if flicker:
		l.set_script(FLICKER)
		l.set("base_energy", energy)
		l.set("random_flicker", true)
	add_child(l)
