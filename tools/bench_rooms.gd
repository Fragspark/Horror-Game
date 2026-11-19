extends Node
## Bench: Spieler in Raeumen bewegen, Tueren auf/zu, Frame-/GPU-Zeit + Draw-Calls ausgeben.
## Aufruf (ohne --headless): godot --path . res://tools/bench_rooms.tscn
var main: Node
var player: Node3D
var vp_rid: RID

func _ready() -> void:
	main = load("res://scenes/horror_main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(3.0).timeout
	player = get_tree().get_first_node_in_group("Player") as Node3D
	vp_rid = get_tree().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var spots := {
		"Schlafzimmer": Vector3(2.6, 0.2, -0.2),
		"Bad": Vector3(5.6, 0.2, -1.3),
		"Keller": Vector3(0.8, -2.6, -6.0),
		"Kueche": Vector3(-5.6, 0.2, -7.0),
	}
	var mode := OS.get_environment("BENCH_DOORSHADOW")
	if mode == "off":
		for d in get_tree().get_nodes_in_group("door"):
			for m in d.find_children("*", "GeometryInstance3D", true, false):
				(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		print("== Tuer-Schatten AUS ==")
	var kill := OS.get_environment("BENCH_KILL")
	if "moon" in kill:
		for l in main.find_children("*", "DirectionalLight3D", true, false):
			(l as Light3D).shadow_enabled = false
	if "flash" in kill:
		for l in main.find_children("Flashlight", "SpotLight3D", true, false):
			(l as Light3D).shadow_enabled = false
	if "omni" in kill:
		for l in main.find_children("*", "OmniLight3D", true, false):
			(l as Light3D).shadow_enabled = false
	if "player" in kill:
		for g in player.find_children("*", "GeometryInstance3D", true, false):
			print("Spieler-Geometrie: ", g.get_path(), " shadow=", (g as GeometryInstance3D).cast_shadow)
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	print("== kill: ", kill)
	for nm in spots:
		await _run(nm + " laufen", spots[nm], true, false)
		await _run(nm + " laufen+Tueren", spots[nm], true, true)
	get_tree().quit()

func _run(label: String, pos: Vector3, move: bool, doors: bool, no_flash := false) -> void:
	player.global_position = pos
	var fl := player.find_child("Flashlight", true, false) as Light3D
	if fl and no_flash:
		fl.visible = false
	await get_tree().create_timer(0.6).timeout
	var gpu := 0.0; var cpu := 0.0; var dc := 0.0; var n := 0; var worst := 0.0
	var ds := get_tree().get_nodes_in_group("door")
	for f in 150:
		if move:
			player.global_position = pos + Vector3(sin(f * 0.1) * 0.8, 0, cos(f * 0.1) * 0.5)
			player.rotation.y += 0.03
		if doors and f % 40 == 0:
			for d in ds:
				if (d as Node3D).global_position.distance_to(pos) < 8.0 and d.has_method("open_door"):
					if d.is_open: d.close_door(player)
					else: d.open_door(player)
		await get_tree().process_frame
		if f > 20:
			var g := RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
			var c := RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
			gpu += g; cpu += c; worst = maxf(worst, g)
			dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			n += 1
	if fl: fl.visible = true
	print("%-34s GPU %.2f ms (max %.2f)  CPU %.2f ms  DC %d" % [label, gpu / n, worst, cpu / n, dc / n])
