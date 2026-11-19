extends Node3D
## Aussenwelt/Nachbarschaft fuer horror_main.tscn.
## Alles wird beim Start prozedural erzeugt (fester Seed => immer gleich):
##   Ebene 1 (0-6 m):  Geländemesh mit Kollision, Veranda, Zaun, Wege, Gras/Unkraut/Laub (MultiMesh),
##                     Struecher und kahle Aeste direkt vor den Fenstern (werfen Mondschatten).
##   Ebene 2 (6-30 m): nasse Strasse, Gehwege, Graben, 3 neu gebaute Nachbarhaeuser, Strommasten + Kabel,
##                     Laternen (2 flackernd, 1 tot).
##   Ebene 3 (30 m+):  Waldrand-Ring aus MultiMesh-Baeumen um die ganze Karte.
## Event-Anker (Marker3D) liegen unter "Anchors" und in der Gruppe "scare_anchors".
## Koordinaten: Haus x -8.9..7.4, z -11..6; Strasse im Sueden (+z) bei z 12-18.

const NB := preload("res://scenes/environment/nb_gen.gd")
const WINDOW := preload("res://scenes/environment/window_dark.tscn")
const FLICKER := preload("res://scenes/scripts/flickering_light.gd")

@export var seed_value: int = 20261117
## Faktor fuer die Baumzahl im Waldring (1.0 = Standard, 0.5 = halb so dicht).
@export var forest_density: float = 1.0

# Gelaendehoehe (Oberkante der flachen Zonen) und Raster
const BASE_H := -0.03
const CELL := 1.25
const TX0 := -52.5
const TZ0 := -52.5
const TNX := 84
const TNZ := 88
## Loch im Gelaende ueber dem Keller (Rasterkanten, innerhalb der Hauswaende).
const CELLAR_HOLE := Rect2(-5.0, -10.0, 10.0, 7.5)

## Zonen, in denen das Gelaende flach bleibt (Haus, Weg, Strasse, Grundstuecke).
const FLAT_RECTS: Array[Rect2] = [
	Rect2(-13.5, -14.5, 24.5, 24.5),   # Haus + Vorgarten + Hinterhof-Streifen
	Rect2(-70.0, 9.5, 140.0, 11.1),    # Strasse mit Gehwegen
	Rect2(-26.5, -6.0, 14.0, 13.5),    # Westnachbar
	Rect2(-19.0, 22.5, 12.0, 11.5),    # Suedwest
	Rect2(6.5, 22.5, 13.0, 11.5),      # Suedost
]

## Bereiche, in denen kein Gras waechst (Gebaeude, Strasse, Wege).
const NO_GRASS: Array[Rect2] = [
	Rect2(-9.7, -11.7, 17.9, 18.4),    # Haus
	Rect2(-2.4, 6.0, 4.8, 4.6),        # Veranda + Weg
	Rect2(-70.0, 10.9, 140.0, 9.6),    # Gehwege + Strasse
	Rect2(-25.8, -6.9, 11.8, 12.7),    # Westnachbar
	Rect2(-19.4, 22.8, 10.2, 10.4),    # Suedwest
	Rect2(7.4, 23.0, 10.2, 9.4),       # Suedost
	Rect2(1.9, -17.2, 3.4, 3.4),       # Schuppen Nord
	Rect2(12.6, -7.6, 3.0, 3.2),       # Schuppen Ost
]

var _rng := RandomNumberGenerator.new()
var _noise: FastNoiseLite
var _patch: FastNoiseLite
var _m: Dictionary = {}
var _swing: Array = []
var _anchors: Node3D
var _t := 0.0


func _ready() -> void:
	_rng.seed = seed_value
	_noise = FastNoiseLite.new()
	_noise.seed = seed_value
	_noise.frequency = 0.085
	_noise.fractal_octaves = 2
	_patch = FastNoiseLite.new()
	_patch.seed = seed_value + 11
	_patch.frequency = 0.2
	_make_materials()
	_anchors = Node3D.new()
	_anchors.name = "Anchors"
	add_child(_anchors)
	_build_terrain()
	_build_street()
	_build_front_yard()
	_build_lamps()
	_build_poles()
	_build_houses()
	_build_sheds()
	_build_garden_models()
	_build_forest()
	_build_anchors()


func _process(delta: float) -> void:
	_t += delta
	for s in _swing:
		var n: Node3D = s["node"]
		var ph: float = s["phase"]
		n.rotation.z = sin(_t * 0.9 + ph) * 0.13 + sin(_t * 2.3 + ph) * 0.03
		n.rotation.x = cos(_t * 0.7 + ph * 1.3) * 0.08
		var l: OmniLight3D = s["light"]
		if l:
			l.light_energy = 0.55 * (0.85 + 0.15 * sin(_t * 11.0 + ph) * sin(_t * 3.1))


# ---------------------------------------------------------------- Materialien

func _tint(path: String, color: Color, rough: float = -1.0) -> StandardMaterial3D:
	var m := (load(path) as StandardMaterial3D).duplicate() as StandardMaterial3D
	m.albedo_color = color
	if rough >= 0.0:
		m.roughness = rough
	return m


func _make_materials() -> void:
	_m["asphalt"] = _tint("res://assets/materials/street_asphalt.tres", Color(0.34, 0.35, 0.37), 0.33)
	_m["sidewalk"] = _tint("res://assets/materials/concrete_basement.tres", Color(0.42, 0.42, 0.41), 0.85)
	_m["path"] = _tint("res://assets/materials/concrete_basement.tres", Color(0.3, 0.3, 0.28), 0.9)
	_m["wall_w"] = _tint("res://assets/materials/wood_light.tres", Color(0.5, 0.5, 0.54))
	_m["wall_sw"] = _tint("res://assets/materials/wood_light.tres", Color(0.46, 0.38, 0.31))
	_m["wall_se"] = _tint("res://assets/materials/wood_light.tres", Color(0.44, 0.47, 0.44))
	_m["trim"] = _tint("res://assets/materials/wood_trim.tres", Color(0.46, 0.45, 0.43))
	_m["roof"] = _tint("res://assets/materials/roof_tiles.tres", Color(0.36, 0.34, 0.35))
	_m["dark_wood"] = _tint("res://assets/materials/wood_dark.tres", Color(0.34, 0.3, 0.26))
	_m["pole_wood"] = _tint("res://assets/materials/wood_dark.tres", Color(0.3, 0.26, 0.22), 0.95)
	_m["foundation"] = _tint("res://assets/materials/concrete_basement.tres", Color(0.3, 0.3, 0.3), 0.9)

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.05, 0.05, 0.055)
	metal.metallic = 0.6
	metal.roughness = 0.5
	_m["metal"] = metal

	var bark := StandardMaterial3D.new()
	bark.vertex_color_use_as_albedo = true
	bark.roughness = 1.0
	bark.metallic_specular = 0.0
	bark.cull_mode = BaseMaterial3D.CULL_DISABLED
	_m["bark"] = bark

	var grass := ShaderMaterial.new()
	grass.shader = load("res://assets/materials/grass_sway.gdshader")
	_m["grass"] = grass

	var lamp_on := StandardMaterial3D.new()
	lamp_on.albedo_color = Color(1.0, 0.85, 0.55)
	lamp_on.emission_enabled = true
	lamp_on.emission = Color(1.0, 0.8, 0.5)
	lamp_on.emission_energy_multiplier = 6.0
	_m["lamp_glow"] = lamp_on
	var lamp_off := StandardMaterial3D.new()
	lamp_off.albedo_color = Color(0.05, 0.05, 0.05)
	lamp_off.roughness = 0.3
	_m["lamp_dead"] = lamp_off

	var puddle := StandardMaterial3D.new()
	puddle.albedo_color = Color(0.012, 0.015, 0.02, 0.85)
	puddle.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puddle.roughness = 0.03
	puddle.metallic_specular = 1.0
	_m["puddle"] = puddle

	var dash := StandardMaterial3D.new()
	dash.albedo_color = Color(0.5, 0.46, 0.33)
	dash.roughness = 0.9
	_m["dash"] = dash

	# Bodenmaterial: Ground037 (PBR-Gras) x Vertex-Farben, world-triplanar
	const GRASS_DIR := "res://assets/textures/outside_gras/Ground037_2K-JPG_"
	var ground := StandardMaterial3D.new()
	ground.vertex_color_use_as_albedo = true
	ground.albedo_texture = load(GRASS_DIR + "Color.jpg")
	ground.roughness_texture = load(GRASS_DIR + "Roughness.jpg")
	ground.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	ground.normal_enabled = true
	ground.normal_texture = load(GRASS_DIR + "NormalGL.jpg")
	ground.normal_scale = 0.8
	ground.metallic_specular = 0.1
	ground.uv1_triplanar = true
	ground.uv1_world_triplanar = true
	ground.uv1_scale = Vector3(0.3, 0.3, 0.3)
	ground.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_m["ground"] = ground


# ---------------------------------------------------------------- Helfer

func _box(parent: Node, nm: String, pos: Vector3, size: Vector3, mat: Material,
		solid: bool = false, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


## Markiert die Kollisionsbox eines mit solid=true erzeugten _box() als
## Untergrund fuer die Spieler-Schritte (Gruppe "surface_*", siehe horror_player.gd).
func _mark_surface(mi: MeshInstance3D, group: String) -> void:
	for c in mi.get_children():
		if c is StaticBody3D:
			c.add_to_group(group)


func _cyl(parent: Node, nm: String, pos: Vector3, r_top: float, r_bot: float, h: float,
		mat: Material, solid: bool = false, sides: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = sides
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if solid:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = maxf(r_top, r_bot)
		sh.height = h
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


func _mesh(parent: Node, nm: String, mesh: Mesh, mat: Material, pos: Vector3,
		yaw_deg: float = 0.0, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _mm(parent: Node, nm: String, mesh: Mesh, mat: Material, xforms: Array,
		shadows: bool = true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


func _in_rects(x: float, z: float, rects: Array[Rect2]) -> bool:
	for r in rects:
		if r.has_point(Vector2(x, z)):
			return true
	return false


func _anchor(nm: String, pos: Vector3, kind: String) -> void:
	var mk := Marker3D.new()
	mk.name = nm
	mk.position = pos
	mk.set_meta("anchor_kind", kind)
	mk.add_to_group("scare_anchors")
	_anchors.add_child(mk)


# ---------------------------------------------------------------- Gelaende

func _flat_dist(x: float, z: float) -> float:
	var best := 1.0e9
	for r in FLAT_RECTS:
		var dx := maxf(maxf(r.position.x - x, 0.0), x - r.end.x)
		var dz := maxf(maxf(r.position.y - z, 0.0), z - r.end.y)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


func ground_h(x: float, z: float) -> float:
	var m := smoothstep(0.0, 4.5, _flat_dist(x, z))
	var h := BASE_H + m * (_noise.get_noise_2d(x, z) * 0.24 + 0.05)
	# Strassengraben hinter dem Suedgehweg
	var dz := absf(z - 21.5)
	if dz < 1.0:
		h -= 0.3 * (1.0 - dz * dz)
	return h


func _ground_color(x: float, z: float) -> Color:
	var p := _patch.get_noise_2d(x, z)
	var c := Color(0.2, 0.25, 0.15).lerp(Color(0.27, 0.21, 0.15), smoothstep(0.05, 0.55, p))
	c = c.lerp(Color(0.12, 0.14, 0.11), 1.0 - smoothstep(-0.7, -0.15, p))
	if absf(x) > 26.0 or z < -18.0 or z > 34.0:
		c *= 0.7
	return c * 1.5


func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var e := 0.4
	for j in TNZ:
		for i in TNX:
			var x0 := TX0 + i * CELL
			var z0 := TZ0 + j * CELL
			var x1 := x0 + CELL
			var z1 := z0 + CELL
			if x0 >= CELLAR_HOLE.position.x - 0.001 and x1 <= CELLAR_HOLE.end.x + 0.001 \
					and z0 >= CELLAR_HOLE.position.y - 0.001 and z1 <= CELLAR_HOLE.end.y + 0.001:
				continue
			var pts := [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]
			var v: Array[Vector3] = []
			var n: Array[Vector3] = []
			var c: Array[Color] = []
			for p in pts:
				var px: float = p.x
				var pz: float = p.y
				v.append(Vector3(px, ground_h(px, pz), pz))
				n.append(Vector3(ground_h(px - e, pz) - ground_h(px + e, pz), 2.0 * e,
						ground_h(px, pz - e) - ground_h(px, pz + e)).normalized())
				c.append(_ground_color(px, pz))
			NB._tri(st, v[0], v[1], v[2], n[0], n[1], n[2], c[0], c[1], c[2])
			NB._tri(st, v[0], v[2], v[3], n[0], n[2], n[3], c[0], c[2], c[3])
			faces.append_array([v[0], v[1], v[2], v[0], v[2], v[3]])
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.add_to_group("surface_grass")
	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = st.commit()
	mi.material_override = _m["ground"]
	body.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


# ---------------------------------------------------------------- Strasse

func _build_street() -> void:
	var s := Node3D.new()
	s.name = "Street"
	add_child(s)
	_mark_surface(_box(s, "Road", Vector3(0, -0.05, 15.15), Vector3(92, 0.1, 6.1), _m["asphalt"], true), "surface_asphalt")
	_mark_surface(_box(s, "SidewalkNear", Vector3(0, -0.04, 11.1), Vector3(92, 0.14, 2.0), _m["sidewalk"], true), "surface_asphalt")
	_mark_surface(_box(s, "SidewalkFar", Vector3(0, -0.04, 19.2), Vector3(92, 0.14, 2.0), _m["sidewalk"], true), "surface_asphalt")
	_box(s, "CurbNear", Vector3(0, 0.03, 12.08), Vector3(92, 0.16, 0.18), _m["sidewalk"])
	_box(s, "CurbFar", Vector3(0, 0.03, 18.22), Vector3(92, 0.16, 0.18), _m["sidewalk"])
	var xf: Array = []
	var x := -42.0
	while x <= 42.0:
		xf.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.012, 15.15)))
		x += 6.0
	var dash := BoxMesh.new()
	dash.size = Vector3(1.4, 0.02, 0.14)
	_mm(s, "LineDashes", dash, _m["dash"], xf, false)
	# Pfuetzen (nur Glanz fuer Laternenlicht)
	var puddles := [
		Vector3(3.6, 0.011, 13.3), Vector3(-14.0, 0.011, 13.6), Vector3(-5.5, 0.011, 16.6),
		Vector3(9.5, 0.011, 17.0), Vector3(-20.0, 0.011, 14.2), Vector3(-10.0, 0.011, 17.2),
	]
	for i in puddles.size():
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.height = 0.004
		cm.radial_segments = 16
		cm.rings = 1
		_mesh(s, "Puddle%d" % i, cm, _m["puddle"], puddles[i], _rng.randf() * 180.0,
				Vector3(_rng.randf_range(0.9, 1.7), 1, _rng.randf_range(0.6, 1.1))).cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- Vorgarten

func _build_front_yard() -> void:
	var y := Node3D.new()
	y.name = "FrontYard"
	add_child(y)
	var wood: Material = _m["dark_wood"]
	# Veranda: Unterbau + Dielen (eine fehlt, eine gebrochen), Kollision = ein Block
	var deck_top := 0.07
	_box(y, "DeckBase", Vector3(0, -0.02, 6.95), Vector3(3.4, 0.18, 1.9), _m["foundation"], true)
	for k in 12:
		if k == 5:
			continue   # fehlende Diele
		var zc := 6.12 + k * 0.155
		var rot := Vector3.ZERO
		var top := deck_top
		if k == 8:
			rot = Vector3(0, 0, 4.0)   # gebrochene, schiefe Diele
			top += 0.012
		_box(y, "Plank%d" % k, Vector3(0, top - 0.02, zc), Vector3(3.36, 0.04, 0.145), wood, false, rot)
	_box(y, "Step", Vector3(0, 0.0, 8.15), Vector3(2.4, 0.07, 0.5), wood, true)
	_mark_surface(_box(y, "Path", Vector3(0, -0.01, 9.35), Vector3(1.6, 0.08, 1.7), _m["path"], true), "surface_asphalt")
	# kaputtes Gelaender links, rechts fehlt es
	_box(y, "RailL", Vector3(-1.62, 0.55, 7.0), Vector3(0.06, 0.06, 1.7), wood, false, Vector3(0, 0, -6.0))
	_box(y, "RailPostL0", Vector3(-1.62, 0.3, 6.2), Vector3(0.08, 0.7, 0.08), wood)
	_box(y, "RailPostL1", Vector3(-1.58, 0.28, 7.7), Vector3(0.08, 0.65, 0.08), wood, false, Vector3(8, 0, 12))

	# Zaun: Pfosten, Riegel, Latten (MultiMesh) + Kollision wie vorher
	var fz := 10.2
	var segs := [Vector2(-9.2, -1.1), Vector2(1.1, 9.2)]
	var pickets: Array = []
	for sg in segs:
		var a: float = sg.x
		var b: float = sg.y
		_box(y, "FenceCol", Vector3((a + b) * 0.5, 0.5, fz), Vector3(b - a, 1.0, 0.1), wood, true).visible = false
		var px := a
		while px <= b + 0.01:
			var post := _box(y, "FencePost", Vector3(px, 0.55, fz), Vector3(0.1, 1.15, 0.1), wood, false,
					Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-7, 7)))
			post.position.y = 0.55 - _rng.randf_range(0.0, 0.08)
			px += 1.6
		_box(y, "RailLow", Vector3((a + b) * 0.5, 0.32, fz + 0.06), Vector3(b - a, 0.05, 0.03), wood, false, Vector3(0, 0, _rng.randf_range(-1.0, 1.0)))
		_box(y, "RailHigh", Vector3((a + b) * 0.5, 0.82, fz + 0.06), Vector3(b - a, 0.05, 0.03), wood, false, Vector3(0, 0, _rng.randf_range(-1.5, 1.5)))
		var lx := a + 0.05
		while lx < b:
			if _rng.randf() > 0.12:
				var hh := _rng.randf_range(0.8, 1.0)
				var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.05, 0.05), 0, _rng.randf_range(-0.09, 0.09)))
				pickets.append(Transform3D(basis, Vector3(lx, 0.1 + hh * 0.5, fz + 0.09)) * Transform3D(Basis.from_scale(Vector3(1, hh, 1)), Vector3.ZERO))
			lx += 0.15
	var pm := BoxMesh.new()
	pm.size = Vector3(0.09, 0.95, 0.02)
	_mm(y, "Pickets", pm, wood, pickets)
	# Torpfosten + schief haengende, offene Tuer
	_box(y, "GatePostL", Vector3(-1.05, 0.75, fz), Vector3(0.18, 1.5, 0.18), wood)
	_box(y, "GatePostR", Vector3(1.05, 0.75, fz), Vector3(0.18, 1.5, 0.18), wood, false, Vector3(0, 0, 3))
	var hinge := Node3D.new()
	hinge.name = "GateHinge"
	hinge.position = Vector3(1.05, 0.0, fz)
	hinge.rotation_degrees = Vector3(0, -68, 0)
	y.add_child(hinge)
	_box(hinge, "GateLeaf", Vector3(-0.8, 0.5, 0), Vector3(1.55, 0.85, 0.05), wood, false, Vector3(0, 0, 7))
	# Briefkasten (schief)
	_box(y, "MailboxPost", Vector3(1.65, 0.6, 10.75), Vector3(0.1, 1.2, 0.1), wood, false, Vector3(0, 0, 6))
	_box(y, "Mailbox", Vector3(1.7, 1.27, 10.75), Vector3(0.35, 0.26, 0.5), _m["metal"], false, Vector3(0, 0, 8))
	_box(y, "MailboxFlag", Vector3(1.9, 1.38, 10.6), Vector3(0.02, 0.14, 0.04), _m["metal"], false, Vector3(0, 0, 8))


# ---------------------------------------------------------------- Laternen

func _build_lamps() -> void:
	var root := Node3D.new()
	root.name = "StreetLamps"
	add_child(root)
	# [Position, Roll in Grad, Licht an?, flackert, Schatten]
	var lamps := [
		[Vector3(3.2, 0, 11.0), 0.0, true, true],
		[Vector3(-14.5, 0, 11.0), 0.0, true, true],
		[Vector3(-10.0, 0, 19.4), 7.0, false, false],
	]
	for i in lamps.size():
		var d: Array = lamps[i]
		var lp := Node3D.new()
		lp.name = "Lamp%d" % i
		lp.position = d[0]
		lp.rotation_degrees.z = d[1]
		root.add_child(lp)
		var on: bool = d[2]
		_cyl(lp, "Base", Vector3(0, 0.25, 0), 0.12, 0.16, 0.5, _m["metal"], true)
		_cyl(lp, "Post", Vector3(0, 2.2, 0), 0.06, 0.09, 4.0, _m["metal"], false)
		_box(lp, "Arm", Vector3(0.36, 4.18, 0), Vector3(0.8, 0.06, 0.06), _m["metal"])
		_box(lp, "Housing", Vector3(0.72, 4.12, 0), Vector3(0.42, 0.12, 0.28), _m["metal"])
		var glow_mat: StandardMaterial3D = (_m["lamp_glow"] as StandardMaterial3D).duplicate() if on else _m["lamp_dead"]
		_box(lp, "Glow", Vector3(0.72, 4.04, 0), Vector3(0.32, 0.03, 0.2), glow_mat)
		if on:
			var l := OmniLight3D.new()
			l.name = "Light"
			l.position = Vector3(0.72, 3.95, 0)
			l.light_color = Color(1.0, 0.86, 0.62)
			l.light_energy = 5.5
			l.light_indirect_energy = 0.3
			l.light_volumetric_fog_energy = 2.6
			l.light_size = 0.18
			l.omni_range = 22.0
			l.omni_attenuation = 1.2
			l.shadow_enabled = false  # Perf: Strassenlampen werfen keine Echtzeit-Schatten
			l.shadow_bias = 0.05
			l.shadow_normal_bias = 1.8
			l.shadow_blur = 2.0
			l.set_script(FLICKER)
			l.set("base_energy", 5.5)
			l.set("min_steady_time", 1.5)
			l.set("min_blackout_time", 0.04)
			l.set("max_blackout_time", 0.25)
			l.set("min_burst_time", 0.15)
			l.set("max_burst_time", 0.8)
			l.set("fixture_material", glow_mat)
			l.set("fixture_emission_when_on", 6.0)
			lp.add_child(l)


# ---------------------------------------------------------------- Strommasten

func _build_poles() -> void:
	var root := Node3D.new()
	root.name = "PowerLines"
	add_child(root)
	var pz := 10.8
	var xs := [-32.0, -12.0, 8.0, 28.0]
	var arm_y := 7.95
	for i in xs.size():
		var px: float = xs[i]
		var p := Node3D.new()
		p.name = "Pole%d" % i
		p.position = Vector3(px, 0, pz)
		p.rotation_degrees = Vector3(_rng.randf_range(-1.2, 1.2), 0, _rng.randf_range(-2.0, 2.0))
		root.add_child(p)
		_cyl(p, "Trunk", Vector3(0, 4.3, 0), 0.1, 0.16, 8.6, _m["pole_wood"], true, 7)
		_box(p, "Arm", Vector3(0, arm_y - 0.1, 0), Vector3(0.12, 0.12, 2.1), _m["pole_wood"])
		_box(p, "ArmLow", Vector3(0, arm_y - 0.9, 0), Vector3(0.1, 0.1, 1.5), _m["pole_wood"], false, Vector3(0, 0, 0))
		for dz in [-0.8, 0.0, 0.8]:
			_cyl(p, "Insulator", Vector3(0, arm_y, dz), 0.03, 0.05, 0.14, _m["metal"], false, 5)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(0.02, 0.02, 0.022)
	for i in xs.size() - 1:
		for dz in [-0.8, 0.0, 0.8]:
			_add_cable(st, Vector3(xs[i], arm_y + 0.08, pz + dz), Vector3(xs[i + 1], arm_y + 0.08, pz + dz), 0.55, c)
	for dz in [-0.8, 0.0, 0.8]:
		_add_cable(st, Vector3(xs[0], arm_y + 0.08, pz + dz), Vector3(-52.0, arm_y - 0.4, pz + dz), 0.6, c)
		_add_cable(st, Vector3(xs[3], arm_y + 0.08, pz + dz), Vector3(52.0, arm_y - 0.4, pz + dz), 0.6, c)
	# Hausanschluesse ueber die Strasse und zum Westnachbarn
	_add_cable(st, Vector3(-12.0, arm_y - 0.9, pz), Vector3(-12.2, 4.7, 24.4), 0.9, c)
	_add_cable(st, Vector3(8.0, arm_y - 0.9, pz), Vector3(11.8, 2.9, 25.2), 0.7, c)
	_add_cable(st, Vector3(-12.0, arm_y - 0.9, pz + 0.4), Vector3(-15.1, 4.8, 3.6), 0.5, c)
	var mi := MeshInstance3D.new()
	mi.name = "Cables"
	mi.mesh = st.commit()
	mi.material_override = _m["metal"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _add_cable(st: SurfaceTool, a: Vector3, b: Vector3, sag: float, col: Color) -> void:
	var pts := NB.sag_points(a, b, sag, 16)
	for i in range(pts.size() - 1):
		NB.tube(st, pts[i], pts[i + 1], 0.011, 0.011, 3, col, col)


# ---------------------------------------------------------------- Haeuser

## Gebaeudekoerper von y=-0.3 bis height, Mitte (cx,cz), mit Kollision.
func _body(h: Node3D, nm: String, cx: float, cz: float, w: float, d: float, height: float, mat: Material) -> MeshInstance3D:
	return _box(h, nm, Vector3(cx, (height - 0.3) * 0.5, cz), Vector3(w, height + 0.3, d), mat, true)


## Satteldach (Prisma). center = Mitte der Wandoberkante. Firstrichtung z (oder x mit ridge_along_x).
func _roof(parent: Node3D, nm: String, center: Vector3, span: float, length: float, pitch_deg: float,
		ridge_along_x: bool, wall_mat: Material, overhang: float = 0.4) -> MeshInstance3D:
	var tp := tan(deg_to_rad(pitch_deg))
	var sp := sin(deg_to_rad(pitch_deg))
	var cp := cos(deg_to_rad(pitch_deg))
	var hw := span * 0.5 + overhang
	var hl := length * 0.5 + 0.25
	var rh := span * 0.5 * tp
	var ye := -overhang * tp
	var ra := Vector3(0, rh, -hl)
	var rb := Vector3(0, rh, hl)
	var la := Vector3(-hw, ye, -hl)
	var lb := Vector3(-hw, ye, hl)
	var rra := Vector3(hw, ye, -hl)
	var rrb := Vector3(hw, ye, hl)
	var nl := Vector3(-sp, cp, 0)
	var nr := Vector3(sp, cp, 0)
	var w := Color.WHITE
	var st1 := SurfaceTool.new()
	st1.begin(Mesh.PRIMITIVE_TRIANGLES)
	NB._tri(st1, la, lb, rb, nl, nl, nl, w, w, w)
	NB._tri(st1, la, rb, ra, nl, nl, nl, w, w, w)
	NB._tri(st1, rra, rrb, rb, nr, nr, nr, w, w, w)
	NB._tri(st1, rra, rb, ra, nr, nr, nr, w, w, w)
	# Unterseite (Dachuntersicht)
	var nd := Vector3.DOWN
	NB._tri(st1, la, lb, rrb, nd, nd, nd, w, w, w)
	NB._tri(st1, la, rrb, rra, nd, nd, nd, w, w, w)
	var mesh := st1.commit()
	mesh.surface_set_material(0, _m["roof"])
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zl := length * 0.5
	var hs := span * 0.5
	NB._tri(st2, Vector3(-hs, 0, zl), Vector3(hs, 0, zl), Vector3(0, rh, zl), Vector3.BACK, Vector3.BACK, Vector3.BACK, w, w, w)
	NB._tri(st2, Vector3(-hs, 0, -zl), Vector3(hs, 0, -zl), Vector3(0, rh, -zl), Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD, w, w, w)
	st2.commit(mesh)
	mesh.surface_set_material(1, wall_mat)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.position = center
	mi.rotation_degrees.y = 90.0 if ridge_along_x else 0.0
	parent.add_child(mi)
	return mi


func _window(parent: Node3D, nm: String, pos: Vector3, yaw: float, sz: Vector2,
		lit: bool = false, round_w: bool = false) -> Node3D:
	var w := WINDOW.instantiate() as Node3D
	w.name = nm
	w.set("size", sz)
	w.set("lit", lit)
	w.set("round_window", round_w)
	w.position = pos
	w.rotation_degrees.y = yaw
	parent.add_child(w)
	return w


func _door(parent: Node3D, nm: String, x: float, z: float, base_y: float = 0.0) -> void:
	_box(parent, nm + "Frame", Vector3(x, base_y + 1.05, z + 0.01), Vector3(1.15, 2.2, 0.06), _m["trim"])
	_box(parent, nm, Vector3(x, base_y + 1.0, z + 0.05), Vector3(0.95, 2.05, 0.05), _m["dark_wood"])


## Veranda an der Vorderseite (+z): Deck, Stufe, Pfosten, schraeges Vordach.
func _porch(h: Node3D, x0: float, x1: float, z0: float, depth: float, top: float, post_count: int) -> void:
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	_box(h, "PorchDeck", Vector3(cx, (top - 0.1) * 0.5, z0 + depth * 0.5), Vector3(w, top + 0.1, depth), _m["dark_wood"], true)
	_box(h, "PorchStep", Vector3(cx, top * 0.25, z0 + depth + 0.25), Vector3(minf(w, 1.6), top * 0.5, 0.5), _m["dark_wood"], true)
	for i in post_count:
		var px := x0 + 0.15 + (w - 0.3) * float(i) / float(maxi(post_count - 1, 1))
		_box(h, "PorchPost%d" % i, Vector3(px, top + 1.2, z0 + depth - 0.12), Vector3(0.13, 2.4, 0.13), _m["trim"],
				false, Vector3(0, 0, _rng.randf_range(-1.0, 1.0)))
	_box(h, "PorchRoof", Vector3(cx, top + 2.55, z0 + depth * 0.5 - 0.1), Vector3(w + 0.4, 0.1, depth + 0.5), _m["roof"], false, Vector3(7, 0, 0))


func _build_houses() -> void:
	var root := Node3D.new()
	root.name = "Houses"
	add_child(root)
	_house_west(root)
	_house_southwest(root)
	_house_southeast(root)


func _house_west(root: Node3D) -> void:
	# Westnachbar: L-foermig, zweigeschossig, Seitenschuppen; ein schwach beleuchtetes Fenster zum Haus hin.
	var h := Node3D.new()
	h.name = "NeighbourWest"
	h.position = Vector3(-18.5, 0, 0.5)
	root.add_child(h)
	var wall: Material = _m["wall_w"]
	_body(h, "BodyMain", 0, 0, 7.0, 6.0, 5.2, wall)
	_body(h, "BodyWing", -5.0, -1.0, 3.0, 4.0, 3.1, wall)
	_roof(h, "RoofMain", Vector3(0, 5.2, 0), 6.0, 7.0, 32.0, true, wall)
	_roof(h, "RoofWing", Vector3(-5.0, 3.1, -1.0), 4.0, 3.0, 22.0, true, wall, 0.3)
	_box(h, "Chimney", Vector3(2.5, 6.4, -1.0), Vector3(0.7, 3.0, 0.7), _m["foundation"])
	# Front (+z, zur Strasse)
	_porch(h, -3.2, 0.9, 3.0, 1.6, 0.35, 3)
	_door(h, "Door", 0.2, 3.0, 0.35)
	_window(h, "FrontL", Vector3(-2.3, 1.7, 3.0), 0, Vector2(0.9, 1.3))
	_window(h, "FrontR", Vector3(2.4, 1.7, 3.0), 0, Vector2(0.9, 1.3))
	for k in 3:
		_window(h, "FrontUp%d" % k, Vector3(-2.3 + 2.3 * k, 3.9, 3.0), 0, Vector2(0.9, 1.2))
	# Ostseite (zum Hauptgebaeude, +x -> yaw 90)
	_window(h, "EastDark", Vector3(3.5, 1.7, -1.6), 90, Vector2(0.9, 1.3))
	_window(h, "EastLit", Vector3(3.5, 1.7, 1.2), 90, Vector2(0.9, 1.3), true)
	_window(h, "EastUp0", Vector3(3.5, 3.9, -1.6), 90, Vector2(0.9, 1.2))
	_window(h, "EastUp1", Vector3(3.5, 3.9, 1.2), 90, Vector2(0.9, 1.2))
	# Rueckseite
	_window(h, "Back0", Vector3(1.5, 1.7, -3.0), 180, Vector2(0.9, 1.3))
	_window(h, "WingWest", Vector3(-6.5, 1.5, -1.0), -90, Vector2(0.8, 1.1))


func _house_southwest(root: Node3D) -> void:
	# Suedwest (gegenueber, Front nach Norden): schmal, Garage, Veranda, Dachboden-Rundfenster, komplett dunkel.
	var h := Node3D.new()
	h.name = "NeighbourSouthWest"
	h.position = Vector3(-12.5, 0, 28.5)
	h.rotation_degrees.y = 180.0
	root.add_child(h)
	var wall: Material = _m["wall_sw"]
	_body(h, "BodyMain", 0, 0, 5.6, 8.0, 5.0, wall)
	_roof(h, "RoofMain", Vector3(0, 5.0, 0), 5.6, 8.0, 35.0, false, wall)
	_body(h, "Garage", 4.6, -1.0, 3.6, 6.0, 2.7, wall)
	_roof(h, "RoofGarage", Vector3(4.6, 2.7, -1.0), 3.6, 6.0, 15.0, false, wall, 0.3)
	_box(h, "GarageDoor", Vector3(4.6, 1.05, 2.03), Vector3(2.9, 2.1, 0.06), _m["dark_wood"])
	_box(h, "Chimney", Vector3(-1.6, 5.8, -1.5), Vector3(0.6, 2.4, 0.6), _m["foundation"])
	_porch(h, -2.6, 2.6, 4.0, 1.4, 0.3, 4)
	_door(h, "Door", 0.0, 4.0, 0.3)
	_window(h, "FrontL", Vector3(-1.8, 1.65, 4.0), 0, Vector2(0.9, 1.3))
	_window(h, "FrontR", Vector3(1.8, 1.65, 4.0), 0, Vector2(0.9, 1.3))
	_window(h, "UpL", Vector3(-1.6, 3.8, 4.0), 0, Vector2(0.9, 1.2))
	_window(h, "UpR", Vector3(1.6, 3.8, 4.0), 0, Vector2(0.9, 1.2))
	_window(h, "Attic", Vector3(0, 5.9, 4.0), 0, Vector2(0.6, 0.6), false, true)
	_window(h, "SideW0", Vector3(-2.8, 1.65, -1.5), -90, Vector2(0.9, 1.3))
	_window(h, "SideW1", Vector3(-2.8, 1.65, 1.5), -90, Vector2(0.9, 1.3))
	_window(h, "SideWUp", Vector3(-2.8, 3.8, 0.0), -90, Vector2(0.9, 1.2))


func _house_southeast(root: Node3D) -> void:
	# Suedost (gegenueber): flaches Haus, grosse Veranda, Gaube mit Fenster (Silhouetten-Anker), schwingende Veranda-Lampe.
	var h := Node3D.new()
	h.name = "NeighbourSouthEast"
	h.position = Vector3(12.5, 0, 28.5)
	h.rotation_degrees.y = 180.0
	root.add_child(h)
	var wall: Material = _m["wall_se"]
	_body(h, "BodyMain", 0, 0, 9.0, 6.5, 3.0, wall)
	_roof(h, "RoofMain", Vector3(0, 3.0, 0), 6.5, 9.0, 30.0, true, wall)
	_box(h, "Chimney", Vector3(2.8, 4.3, -0.5), Vector3(0.7, 2.4, 0.7), _m["foundation"])
	# Gaube
	_box(h, "Dormer", Vector3(0, 3.78, 1.95), Vector3(1.8, 1.25, 1.5), wall)
	_roof(h, "DormerRoof", Vector3(0, 4.4, 1.9), 1.8, 1.6, 35.0, false, wall, 0.2)
	_window(h, "DormerWin", Vector3(0, 3.8, 2.7), 0, Vector2(0.6, 0.8))
	# Veranda
	_porch(h, -4.0, 3.0, 3.25, 2.0, 0.35, 5)
	_door(h, "Door", 1.5, 3.25, 0.35)
	_window(h, "FrontA", Vector3(-3.0, 1.65, 3.25), 0, Vector2(1.1, 1.2))
	_window(h, "FrontB", Vector3(-0.8, 1.65, 3.25), 0, Vector2(1.1, 1.2))
	_window(h, "SideE0", Vector3(4.5, 1.65, -1.0), 90, Vector2(0.9, 1.2))
	_window(h, "SideE1", Vector3(4.5, 1.65, 1.2), 90, Vector2(0.9, 1.2))
	# schwingende Veranda-Lampe
	var pivot := Node3D.new()
	pivot.name = "PorchLampPivot"
	pivot.position = Vector3(1.8, 2.85, 4.55)
	h.add_child(pivot)
	_cyl(pivot, "Chain", Vector3(0, -0.15, 0), 0.008, 0.008, 0.3, _m["metal"], false, 4)
	_cyl(pivot, "Shade", Vector3(0, -0.38, 0), 0.05, 0.14, 0.18, _m["metal"], false, 8)
	var bulb := (_m["lamp_glow"] as StandardMaterial3D).duplicate() as StandardMaterial3D
	bulb.emission_energy_multiplier = 3.0
	_box(pivot, "Bulb", Vector3(0, -0.46, 0), Vector3(0.08, 0.08, 0.08), bulb)
	var l := OmniLight3D.new()
	l.name = "Light"
	l.position = Vector3(0, -0.5, 0)
	l.light_color = Color(1.0, 0.7, 0.4)
	l.light_energy = 0.55
	l.omni_range = 7.0
	l.omni_attenuation = 1.5
	l.light_volumetric_fog_energy = 1.0
	pivot.add_child(l)
	_swing.append({"node": pivot, "phase": 0.7, "light": l})


func _build_sheds() -> void:
	var root := Node3D.new()
	root.name = "Sheds"
	add_child(root)
	var defs := [
		["ShedNorth", Vector3(3.6, 0, -15.5), 12.0, 2.6, 2.2, 2.3],
		["ShedEast", Vector3(14.0, 0, -6.0), -20.0, 2.4, 2.2, 2.2],
	]
	for d in defs:
		var s := Node3D.new()
		s.name = d[0]
		s.position = d[1]
		s.rotation_degrees.y = d[2]
		root.add_child(s)
		var w: float = d[3]
		var dp: float = d[4]
		var ht: float = d[5]
		_body(s, "Body", 0, 0, w, dp, ht, _m["dark_wood"])
		_box(s, "Roof", Vector3(0, ht + 0.12, 0), Vector3(w + 0.5, 0.08, dp + 0.5), _m["roof"], false, Vector3(9, 0, 0))
		_box(s, "Door", Vector3(0, 1.0, dp * 0.5 + 0.03), Vector3(0.9, 1.9, 0.05), _m["metal"])
		_window(s, "Win", Vector3(w * 0.5 - 0.3, 1.5, dp * 0.5), 0, Vector2(0.4, 0.4), false, false)


# ---------------------------------------------------------------- Vegetation

## Liefert [{mesh, xf, mat}] je MeshInstance3D der glTF-Szene, normiert auf Hoehe 1.0,
## Fusspunkt (Mitte unten) im Ursprung. Placement-Scale = gewuenschte Hoehe in Metern.
func _model_parts(path: String) -> Array:
	var out: Array = []
	var inst := (load(path) as PackedScene).instantiate()
	_collect_parts(inst, Transform3D.IDENTITY, out)
	inst.free()
	return out


func _collect_parts(n: Node, t: Transform3D, out: Array) -> void:
	if n is Node3D:
		t = t * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		# get_aabb() ist bei diesen glTFs ungenau -> Grenzen aus den echten Vertices
		var a := AABB()
		var first := true
		for sf in mi.mesh.get_surface_count():
			for v in (mi.mesh.surface_get_arrays(sf)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var tv := t * v
				if first:
					a = AABB(tv, Vector3.ZERO)
					first = false
				else:
					a = a.expand(tv)
		var s := 1.0 / maxf(a.size.y, 0.001)
		var c := a.position + a.size * 0.5
		var xf := Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3.ZERO) 				* Transform3D(Basis.IDENTITY, Vector3(-c.x, -a.position.y, -c.z)) * t
		out.append({"mesh": mi.mesh, "xf": xf, "mat": mi.mesh.surface_get_material(0)})
	for ch in n.get_children():
		_collect_parts(ch, t, out)


const PINE_SINK := -0.1


func _pine_material(src: Material) -> StandardMaterial3D:
	var mat := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.albedo_color = Color(0.42, 0.5, 0.45)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	# Nadeln sind Alpha-Maske: Alpha to Coverage glaettet die Kanten mit MSAA.
	if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	return mat


func _build_garden_models() -> void:
	var root := Node3D.new()
	root.name = "GardenModels"
	add_child(root)
	# --- Kiefern (Nachtton, Alpha-Maske aus dem Modell)
	var pine_parts := _model_parts("res://assets/models/pine_tree/scene.gltf")
	var pine_pos: Array = [Vector3(12.8, 0, 9.5), Vector3(-14.0, 0, 9.5),
			Vector3(-14.5, 0, -14.0), Vector3(12.8, 0, -14.0)]
	var pine_h: Array = [8.5, 7.2, 9.0, 7.8]
	for part in pine_parts:
		var mat := _pine_material(part["mat"])
		var xs: Array = []
		for i in pine_pos.size():
			var p: Vector3 = pine_pos[i]
			p.y = ground_h(p.x, p.z) + PINE_SINK
			var h: float = pine_h[i]
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(h, h, h))
			xs.append(Transform3D(b, p) * (part["xf"] as Transform3D))
		_mm(root, "Pines", part["mesh"], mat, xs, true)
	for i in pine_pos.size():
		var p: Vector3 = pine_pos[i]
		var body := StaticBody3D.new()
		body.name = "PineCol%d" % i
		body.position = Vector3(p.x, ground_h(p.x, p.z) + 1.2, p.z)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.3
		cyl.height = 2.4
		cs.shape = cyl
		body.add_child(cs)
		root.add_child(body)
	# --- Gras-Buschel (4 Varianten), dicht im Garten, locker auf dem Rest
	var grass_parts := _model_parts("res://assets/models/grass_variations/scene.gltf")
	var gbuckets: Array = []
	for i in grass_parts.size():
		gbuckets.append([])
	var target := 1100
	var tries := 0
	var count := 0
	while count < target and tries < target * 6:
		tries += 1
		var in_garden := _rng.randf() < 0.75
		var x := _rng.randf_range(-13.0, 11.0) if in_garden else _rng.randf_range(-30.0, 30.0)
		var z := _rng.randf_range(-14.0, 9.8) if in_garden else _rng.randf_range(-22.0, 38.0)
		if _in_rects(x, z, NO_GRASS):
			continue
		if _patch.get_noise_2d(x * 1.3, z * 1.3) < -0.2 and _rng.randf() < 0.7:
			continue
		var v := _rng.randi() % grass_parts.size()
		var h := _rng.randf_range(0.3, 0.6)
		var w := h * _rng.randf_range(0.8, 1.3)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(w, h, w))
		gbuckets[v].append(Transform3D(b, Vector3(x, ground_h(x, z) - 0.02, z)) * (grass_parts[v]["xf"] as Transform3D))
		count += 1
	for v in grass_parts.size():
		if gbuckets[v].is_empty():
			continue
		var gmat := (grass_parts[v]["mat"] as StandardMaterial3D).duplicate() as StandardMaterial3D
		gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		gmat.alpha_scissor_threshold = 0.5
		gmat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		gmat.albedo_color = Color(0.4, 0.46, 0.38)
		gmat.roughness = 1.0
		gmat.metallic_specular = 0.0
		_mm(root, "GrassModel%d" % v, grass_parts[v]["mesh"], gmat, gbuckets[v], false)


func _build_forest() -> void:
	var root := Node3D.new()
	root.name = "Forest"
	add_child(root)
	var parts := _model_parts("res://assets/models/pine_tree/scene.gltf")
	var xs: Array = []
	var step := 3.4 / maxf(forest_density, 0.1)
	var x := -50.0
	while x <= 50.0:
		var z := -50.0
		while z <= 53.0:
			var px := x + _rng.randf_range(-1.4, 1.4)
			var pz := z + _rng.randf_range(-1.4, 1.4)
			z += step
			# innerhalb der Spielkarte (+ Rand) und auf der Strasse: keine Baeume
			if absf(px) < 27.5 and pz > -19.5 and pz < 35.5:
				continue
			if pz > 10.5 and pz < 21.0 and absf(px) < 40.0:
				continue
			var out := maxf(maxf(absf(px) - 26.0, -18.0 - pz), pz - 34.0)
			if out > 13.0 and _rng.randf() > 0.4:
				continue
			var h := _rng.randf_range(8.0, 13.0)
			var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(h, h, h))
			xs.append(Transform3D(b, Vector3(px, ground_h(px, pz) - 0.35, pz)))
		x += step
	for part in parts:
		var mat := _pine_material(part["mat"])
		var arr: Array = []
		for t in xs:
			arr.append((t as Transform3D) * (part["xf"] as Transform3D))
		_mm(root, "Trees", part["mesh"], mat, arr, false)


func _build_anchors() -> void:
	# Fenster-/Haus-Anker (Position = Weltkoordinaten)
	_anchor("Anchor_LitWindow_West", Vector3(-14.6, 1.7, 1.7), "lit_window")
	_anchor("Anchor_Silhouette_SE", Vector3(12.5, 3.8, 26.1), "window_silhouette")
	_anchor("Anchor_PorchLamp_SE", Vector3(10.7, 2.4, 23.95), "swinging_lamp")
	_anchor("Anchor_DeadStreetLamp", Vector3(-9.3, 4.0, 19.4), "dead_lamp")
	_anchor("Anchor_Mailbox", Vector3(1.65, 1.3, 10.75), "mailbox")
	_anchor("Anchor_Gate", Vector3(0.0, 0.5, 10.2), "gate")
	_anchor("Anchor_Figure_ForestN", Vector3(-4.0, 0.0, -22.0), "forest_figure")
	_anchor("Anchor_Figure_ForestE", Vector3(31.0, 0.0, -3.0), "forest_figure")
	_anchor("Anchor_Figure_ForestW", Vector3(-31.0, 0.0, 6.0), "forest_figure")
