# Captura automática de prints por posição (s em metros) em Interlagos para comparação visual com o LMU.
# Uso: godot --path . --script res://scripts/tests/capture_compare.gd -- --out=build/compare/godot_atual --quality=2
extends SceneTree

const CHECKPOINTS := [
	["01_senna_entrada", 230.0],
	["02_senna_apex2", 380.0],
	["03_curva_do_sol", 640.0],
	["04_reta_oposta_1", 900.0],
	["05_reta_oposta_2", 1260.0],
	["06_descida_do_lago", 1430.0],
	["07_ferradura_entrada", 1860.0],
	["08_ferradura", 2030.0],
	["09_laranjinha", 2160.0],
	["10_pinheirinho", 2470.0],
	["11_bico_de_pato", 2660.0],
	["12_mergulho", 2960.0],
	["13_juncao", 3180.0],
	["14_subida_boxes", 3650.0],
	["15_arquibancadas", 3980.0],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out_dir := "build/compare/godot_atual"
	var quality := 2
	var only: PackedStringArray = []
	var bench := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--quality="):
			quality = int(a.substr(10))
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a == "--bench":
			bench = true

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out_dir))

	var scene: PackedScene = load("res://scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	main.set_physics_process(false)
	main.set_process(false)
	if main.hud:
		main.hud.visible = false
	if main.touch:
		main.touch.visible = false
	main._set_quality(quality)
	main.chase.mode = 0

	var track: Track = main.track
	var car: Car = main.car
	var chase: ChaseCamera = main.chase

	for cp in CHECKPOINTS:
		var cname: String = cp[0]
		if not only.is_empty() and not (cname in only):
			continue
		var s: float = cp[1]
		var p0: Vector3 = track.P[track.index_at(s)]
		var p1: Vector3 = track.P[track.index_at(s + 4.0)]
		track.locate(p0, -1)
		car.reset(Vector3(p0.x, track.lcenter.y + car.p.cg + 0.02, p0.z), atan2(-(p1.x - p0.x), -(p1.z - p0.z)))
		for w in car.wheels:
			w.contact = true
		main._update_car_view(1.0)
		chase.snap()
		chase.update(1.0 / 60.0, 1.0)
		await process_frame
		await process_frame
		if bench:
			var t0 := Time.get_ticks_usec()
			var frames := 30
			for _f in frames:
				await process_frame
			var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
			print("bench %s (q=%d): %.2f ms/frame (%.1f FPS)" % [cname, quality, ms, 1000.0 / maxf(ms, 0.001)])
		var img := root.get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, cname]
		img.save_png(ProjectSettings.globalize_path("res://" + path))
		print("saved ", path)

	quit(0)

