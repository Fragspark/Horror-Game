class_name HauntedMirror
extends HorrorEvent
## Spiegel mit echter Spiegelung (SubViewport + Camera3D).
##
## Die Spiegelkamera sieht Render-Layer 1 (Welt) und 2 (Erscheinungen). Die
## Spielerkamera blendet Layer 2 aus. Dadurch sind Figuren auf Layer 2 nur im
## Spiegel zu sehen. Die Erscheinung steht am ApparitionAnchor (Raumseite des
## Spiegels, z. B. hinter dem Spieler) und wird nur gespiegelt gezeigt.
##
## Event: Betritt der Spieler die TriggerZone und der Director stimmt zu, erscheint
## die Figur, sobald er in den Spiegel schaut, und verschwindet nach kurzer Zeit.

## Render-Layer (1-20), auf dem Erscheinungen nur im Spiegel sichtbar sind.
const APPARITION_LAYER := 2

@export_group("Spiegel")
@export var mirror_size: Vector2 = Vector2(0.9, 1.5)
## Breite der Spiegeltextur in Pixeln (Hoehe ergibt sich aus mirror_size).
@export var texture_width: int = 384
## Ab dieser Entfernung (m) wird die Spiegelung nicht mehr gerendert.
@export var max_render_distance: float = 9.0
@export var mirror_tint: Color = Color(0.82, 0.88, 0.86)
## Helligkeits-Faktor der Spiegelung (1.0 = wie die Welt).
@export_range(1.0, 4.0, 0.05) var mirror_brightness: float = 2.2

@export_group("Erscheinung")
@export var appear_delay: Vector2 = Vector2(0.4, 2.0)
@export var visible_time: Vector2 = Vector2(0.7, 1.6)
## Maximaler Winkel (Grad) zwischen Blickrichtung und Spiegel, damit die Figur erscheint.
@export_range(5.0, 90.0, 1.0) var look_angle: float = 35.0

@onready var viewport: SubViewport = $SubViewport
@onready var mirror_camera: Camera3D = $SubViewport/MirrorCamera
@onready var surface: MeshInstance3D = $MirrorSurface
@onready var anchor: Marker3D = $ApparitionAnchor
@onready var trigger_zone: Area3D = $TriggerZone

var _armed := false
var _busy := false
var _apparition: Node3D
var _hide_check := 0.0
var _ready_to_show_at := 0.0


func _ready() -> void:
	super._ready()
	var height := int(round(texture_width * mirror_size.y / mirror_size.x))
	viewport.size = Vector2i(texture_width, height)
	viewport.own_world_3d = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	# Spiegel-Viewport: keine eigenen Schatten (zweiter Schatten-Atlas waere teuer).
	viewport.positional_shadow_atlas_size = 0

	mirror_camera.cull_mask = (1 << 0) | (1 << (APPARITION_LAYER - 1))
	mirror_camera.keep_aspect = Camera3D.KEEP_WIDTH
	mirror_camera.projection = Camera3D.PROJECTION_FRUSTUM
	mirror_camera.far = 60.0

	var quad := QuadMesh.new()
	quad.size = mirror_size
	surface.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.albedo_color = mirror_tint
	# Spiegel kehren links/rechts um: Kamerabild horizontal spiegeln.
	mat.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	mat.uv1_offset = Vector3(1.0, 0.0, 0.0)
	surface.material_override = mat
	# Die Spiegelflaeche zeichnet die Spiegelkamera nie selbst (Layer 20).
	surface.layers = 1 << 19
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# ... die Spielerkamera aber schon: Layer 20 bleibt dort aktiv.

	trigger_zone.body_entered.connect(_on_trigger_entered)
	_hide_apparition_layer_from_player_camera()


func _process(delta: float) -> void:
	_hide_check -= delta
	if _hide_check <= 0.0:
		_hide_check = 1.0
		_hide_apparition_layer_from_player_camera()
	_update_mirror_camera()
	if _armed and not _busy and Time.get_ticks_msec() / 1000.0 >= _ready_to_show_at:
		_try_show_apparition()


## Die Spielerkamera darf Layer 2 nicht rendern.
func _hide_apparition_layer_from_player_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam != mirror_camera:
		cam.cull_mask &= ~(1 << (APPARITION_LAYER - 1))


## Spiegelkamera bekommt eine Kopie der Welt-Environment ohne teure Effekte
## (Volumetric Fog, SSAO, SSIL, SDFGI, Glow) - im kleinen Spiegelbild nicht sichtbar.
func _ensure_cheap_environment() -> void:
	if mirror_camera.environment != null:
		return
	var world := get_viewport().world_3d
	var src: Environment = world.environment if world else null
	if src == null:
		var we := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
		src = we.environment if we else null
	if src == null:
		return
	var env := src.duplicate() as Environment
	env.volumetric_fog_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.glow_enabled = false
	# Spiegelbild aufhellen: das dunkle Haus soll im Spiegel erkennbar bleiben.
	env.adjustment_enabled = true
	env.adjustment_brightness = mirror_brightness
	env.adjustment_contrast = 1.05
	mirror_camera.environment = env


func _update_mirror_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var plane_origin := surface.global_position
	var basis_s := surface.global_transform.basis.orthonormalized()
	var normal := basis_s.z.normalized()      # QuadMesh schaut nach +Z
	var eye := cam.global_position
	var dist := (eye - plane_origin).dot(normal)

	var visible_now := dist > 0.05 and dist < max_render_distance \
			and _surface_in_view(cam, plane_origin)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible_now \
			else SubViewport.UPDATE_DISABLED
	if not visible_now:
		return
	_ensure_cheap_environment()

	# Kamera hinter dem Spiegel an der gespiegelten Augenposition; Blick durch
	# die Spiegelebene. Off-Axis-Frustum, damit der Ausschnitt exakt der
	# Spiegelflaeche entspricht.
	var mirrored_eye := eye - 2.0 * dist * normal
	var z_axis := -normal
	var y_axis := basis_s.y.normalized()
	var x_axis := y_axis.cross(z_axis).normalized()
	var cam_basis := Basis(x_axis, y_axis, z_axis)
	mirror_camera.global_transform = Transform3D(cam_basis, mirrored_eye)

	var center_cam := cam_basis.inverse() * (plane_origin - mirrored_eye)
	mirror_camera.near = maxf(dist, 0.02)
	mirror_camera.size = mirror_size.x
	mirror_camera.frustum_offset = Vector2(center_cam.x, center_cam.y)


## Liegt irgendein Teil der Spiegelflaeche im Blickfeld der Kamera? Prueft die
## Umkugel der Flaeche gegen die Frustum-Ebenen (nicht nur den Mittelpunkt, sonst
## friert das Spiegelbild ein, sobald nur noch der Rand sichtbar ist).
func _surface_in_view(cam: Camera3D, center: Vector3) -> bool:
	var radius := mirror_size.length() * 0.5 * maxf(surface.global_transform.basis.get_scale().x, 0.001)
	var inside_point := cam.global_position - cam.global_transform.basis.z * (cam.near + 1.0)
	for plane in cam.get_frustum():
		var p := plane as Plane
		# Ebenen-Orientierung robust bestimmen: Auf der Innenseite liegt ein Punkt vor der Kamera.
		var sign_in := 1.0 if p.distance_to(inside_point) >= 0.0 else -1.0
		if p.distance_to(center) * sign_in < -radius:
			return false
	return true


func _on_trigger_entered(body: Node3D) -> void:
	if _armed or _busy or not is_player(body):
		return
	if request_scare():
		_armed = true
		_ready_to_show_at = Time.get_ticks_msec() / 1000.0 \
				+ randf_range(appear_delay.x, appear_delay.y)


func _try_show_apparition() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_mirror := (surface.global_position - cam.global_position).normalized()
	var angle := rad_to_deg((-cam.global_transform.basis.z).angle_to(to_mirror))
	if angle > look_angle or not cam.is_position_in_frustum(surface.global_position):
		return
	_busy = true
	_show_apparition()


func _show_apparition() -> void:
	_apparition = spawn_entity(self, anchor.global_transform)
	if _apparition == null:
		_armed = false
		_busy = false
		cancel_scare()
		return
	entity_call(_apparition, &"face_point", [surface.global_position])
	entity_call(_apparition, &"hold_pose", [idle_animation, 0.0])
	entity_call(_apparition, &"set_render_layers", [1 << (APPARITION_LAYER - 1)])
	# Kein Schatten auf den Boden: sonst verraet er die unsichtbare Figur.
	for node in _apparition.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	play_sound_at(creak_sound, anchor.global_position, -6.0, 12.0)

	await get_tree().create_timer(randf_range(visible_time.x, visible_time.y)).timeout
	if _apparition and is_instance_valid(_apparition):
		_apparition.queue_free()
	_apparition = null
	_armed = false
	_busy = false
