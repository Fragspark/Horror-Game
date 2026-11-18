extends RefCounted
## Prozedurale Mesh-Helfer fuer die Nachbarschaft (Baeume, Struecher, Gras, Kabel).
## Alles statisch, kein class_name (kein Import-Cache noetig): per preload() nutzen.
## Vegetation bekommt Vertex-Farben und wird mit cull_disabled-Materialien benutzt.


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	# Godot: Vorderseite = im Uhrzeigersinn. Windung anhand der Soll-Normalen korrigieren.
	var g := (b - a).cross(c - a)
	if g.dot(na + nb + nc) > 0.0:
		var t := b; b = c; c = t
		var tn := nb; nb = nc; nc = tn
		var tc := cb; cb = cc; cc = tc
	st.set_color(ca); st.set_normal(na); st.add_vertex(a)
	st.set_color(cb); st.set_normal(nb); st.add_vertex(b)
	st.set_color(cc); st.set_normal(nc); st.add_vertex(c)


static func _axis_basis(a: Vector3) -> Basis:
	var y := a.normalized()
	var up := Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Konischer Stab von p0 nach p1 (offen, ohne Kappen).
static func tube(st: SurfaceTool, p0: Vector3, p1: Vector3, r0: float, r1: float,
		sides: int, c0: Color, c1: Color) -> void:
	var b := _axis_basis(p1 - p0)
	var d: Array[Vector3] = []
	for i in sides:
		var a := TAU * float(i) / float(sides)
		d.append(b.x * cos(a) + b.z * sin(a))
	for i in sides:
		var j := (i + 1) % sides
		var a0 := p0 + d[i] * r0
		var a1 := p1 + d[i] * r1
		var b0 := p0 + d[j] * r0
		var b1 := p1 + d[j] * r1
		_tri(st, a0, a1, b1, d[i], d[i], d[j], c0, c1, c1)
		_tri(st, a0, b1, b0, d[i], d[j], d[j], c0, c1, c0)


static func _branch(st: SurfaceTool, rng: RandomNumberGenerator, p0: Vector3, dir: Vector3,
		length: float, r0: float, depth: int, c_base: Color, c_tip: Color,
		spread: float, bias: Vector3) -> void:
	var p1 := p0 + dir * length
	var sides := 5 if depth >= 2 else 3
	tube(st, p0, p1, r0, maxf(r0 * 0.55, 0.004), sides, c_base, c_tip)
	if depth <= 0 or length < 0.3:
		return
	var n := 2 + rng.randi() % 2
	for k in n:
		var t := rng.randf_range(0.4, 0.95)
		var bp := p0.lerp(p1, t)
		var rv := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.15, 0.8), rng.randf_range(-1, 1)).normalized()
		var nd := (dir + rv * spread + bias * 0.35).normalized()
		_branch(st, rng, bp, nd, length * rng.randf_range(0.5, 0.75), r0 * 0.5, depth - 1,
				c_base.lerp(c_tip, t), c_tip, spread, bias)
	var cd := (dir + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, 0.25), rng.randf_range(-0.3, 0.3)) + bias * 0.1).normalized()
	_branch(st, rng, p1, cd, length * 0.72, r0 * 0.55, depth - 1, c_tip, c_tip, spread, bias)


## Kahler Laubbaum. bias zieht die Aeste in eine Richtung (z.B. zum Fenster hin).
static func bare_tree(seed_v: int, height: float, depth: int = 3, bias: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c_base := Color(0.05, 0.045, 0.04)
	var c_tip := Color(0.035, 0.032, 0.03)
	var trunk_h := height * rng.randf_range(0.35, 0.5)
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12)) + bias * 0.12
	var top := Vector3(0, trunk_h, 0) + lean * trunk_h
	var rt := height * 0.028
	tube(st, Vector3(0, -0.15, 0), top, rt * 1.35, rt * 0.7, 6, c_base, c_tip)
	var crown := 4 + rng.randi() % 3
	for i in crown:
		var a := TAU * float(i) / float(crown) + rng.randf() * 0.8
		var up := rng.randf_range(0.35, 0.9)
		var dir := (Vector3(cos(a), up, sin(a)) + bias * 0.4).normalized()
		var len := height * rng.randf_range(0.28, 0.4)
		var start := Vector3(0, 0, 0).lerp(top, rng.randf_range(0.75, 1.0))
		_branch(st, rng, start, dir, len, rt * 0.62, depth, c_tip, c_tip, 0.85, bias)
	# Mittelast nach oben
	_branch(st, rng, top, Vector3(lean.x, 1, lean.z).normalized(), height * 0.3, rt * 0.6, depth, c_tip, c_tip, 0.7, bias)
	return st.commit()


## Dunkle Fichte aus ausgefransten Kegelstufen.
static func spruce(seed_v: int, height: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_c := Color(0.04, 0.035, 0.03)
	tube(st, Vector3(0, -0.1, 0), Vector3(0, height * 0.9, 0), height * 0.025, height * 0.008, 5, trunk_c, trunk_c)
	var layers := 9
	var sides := 7
	for l in layers:
		var f := float(l) / float(layers)
		var y0 := height * (0.12 + 0.82 * f)
		var rad := height * 0.17 * (1.0 - f) + 0.12
		var y1 := y0 + height * 0.2 * (1.0 - f * 0.5)
		var cb := Color(0.015, 0.03, 0.022).lerp(Color(0.03, 0.05, 0.036), rng.randf())
		var ct := Color(0.02, 0.035, 0.026)
		var ring: Array[Vector3] = []
		for i in sides:
			var a := TAU * float(i) / float(sides) + rng.randf() * 0.4
			var rr := rad * rng.randf_range(0.7, 1.15)
			ring.append(Vector3(cos(a) * rr, y0 - rr * 0.18, sin(a) * rr))
		var apex := Vector3(0, y1, 0)
		for i in sides:
			var j := (i + 1) % sides
			var n := ((ring[i] + ring[j]) * 0.5 - Vector3(0, y0, 0)).normalized() + Vector3(0, 0.5, 0)
			n = n.normalized()
			_tri(st, ring[i], ring[j], apex, n, n, n, cb, cb, ct)
	return st.commit()


## Kahler Strauch: viele duenne Zweige (gibt gute Schatten) + vereinzelte dunkle Blaetter.
static func shrub(seed_v: int, radius: float, leafy: float = 0.5) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c0 := Color(0.04, 0.035, 0.03)
	var c1 := Color(0.03, 0.03, 0.025)
	var n := 22
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf() * 0.5
		var out := rng.randf_range(0.25, 1.0)
		var dir := Vector3(cos(a) * out, rng.randf_range(0.7, 1.4), sin(a) * out).normalized()
		_branch(st, rng, Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1)), dir,
				radius * rng.randf_range(0.7, 1.25), radius * 0.035, 2, c0, c1, 0.8, Vector3.ZERO)
	var leaf_n := int(60.0 * leafy)
	for i in leaf_n:
		var a := rng.randf() * TAU
		var rr := radius * rng.randf_range(0.2, 1.05)
		var p := Vector3(cos(a) * rr, rng.randf_range(0.25, 1.1) * radius, sin(a) * rr)
		var s := radius * rng.randf_range(0.1, 0.2)
		var u := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized() * s
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized() * s
		var lc := Color(0.02, 0.04, 0.02).lerp(Color(0.05, 0.04, 0.025), rng.randf())
		var nn := u.cross(v).normalized()
		_tri(st, p, p + u, p + v, nn, nn, nn, lc, lc, lc)
	return st.commit()


## Grasbueschel aus kreuz und quer stehenden Dreiecks-Halmen.
static func grass_tuft(seed_v: int, height: float, width: float, blades: int = 6) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in blades:
		var a := rng.randf() * TAU
		var off := Vector3(rng.randf_range(-0.13, 0.13), 0, rng.randf_range(-0.13, 0.13))
		var side := Vector3(cos(a), 0, sin(a)) * width * 0.5
		var h := height * rng.randf_range(0.55, 1.1)
		var bend_a := rng.randf() * TAU
		var tip := off + Vector3(cos(bend_a), 0, sin(bend_a)) * h * rng.randf_range(0.1, 0.45) + Vector3(0, h, 0)
		var col_b := Color(0.025, 0.032, 0.02).lerp(Color(0.04, 0.045, 0.028), rng.randf())
		var col_t := Color(0.075, 0.09, 0.05).lerp(Color(0.1, 0.095, 0.05), rng.randf())
		var n := Vector3(0, 1, 0)
		_tri(st, off - side, off + side, tip, n, n, n, col_b, col_b, col_t)
	return st.commit()


## Duenne Roehre durch Punkte (Stromkabel).
static func cable_mesh(points: PackedVector3Array, radius: float = 0.012) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(0.02, 0.02, 0.022)
	for i in range(points.size() - 1):
		tube(st, points[i], points[i + 1], radius, radius, 3, c, c)
	return st.commit()


## Durchhaengende Kabelkurve zwischen a und b.
static func sag_points(a: Vector3, b: Vector3, sag: float, steps: int = 14) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	return pts


## Flaches Quad (Laubblatt) zum Streuen per MultiMesh.
static func leaf_quad(size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := Vector3.UP
	var c := Color(0.08, 0.05, 0.03)
	var c2 := Color(0.05, 0.035, 0.02)
	var a := Vector3(-size * 0.5, 0, -size * 0.7)
	var b := Vector3(size * 0.5, 0, -size * 0.7)
	var cc := Vector3(size * 0.6, 0, size * 0.7)
	var d := Vector3(-size * 0.6, 0, size * 0.7)
	_tri(st, a, b, cc, n, n, n, c, c, c2)
	_tri(st, a, cc, d, n, n, n, c, c2, c2)
	return st.commit()
