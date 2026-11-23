# Calibração das cores de tinta (PLANO-INTERLAGOS-DETALHES.md, Fase 1): mede a cadeia albedo → cor na tela.
# Põe no chão da pista, na frente da câmera de comparação do --atlas (carro escondido), retalhos planos com o
# mesmo material das tintas do cenário ("pinta": relevo e rugosidade do asfalto), cada um com um albedo de teste
# liso, fotografa e lê a cor de tela no centro de cada retalho. tools/ref/calib_tinta.py inverte a cadeia
# (qual albedo dá o sRGB do LMU na tela) a partir disso.
# Uso: godot --path . --script res://scripts/tests/calib_tinta.gd -- --in=<json> --out=<json> [--quality=2]
#      [--s=900,1650,3400] [--track=interlagos] [--png=<pasta>] [--spec=0.2 (especular do material de teste)]
#   <json> de entrada: {"cores": [[r, g, b], ...]} em sRGB 0–255; saída: {"medidas": [{"in", "out", "s"}...]}.
extends SceneTree

const CAM_DIST := 6.8
const CAM_ALT := 2.14
const CAM_PITCH := -12.0
const FOV := 50.0
## retalhos: posições à frente do carro (m) × deslocamento lateral (m); câmera fica 6,8 m atrás do carro
const FRENTE := [0.0, 2.5, 5.0]
const LADO := [-3.6, -2.4, -1.2, 0.0, 1.2, 2.4, 3.6]
const TAM := Vector2(1.0, 2.0)  # largura × comprimento do retalho (m)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var in_path := ""
	var out_path := ""
	var png_dir := ""
	var quality := 2
	var spec := -1.0
	var lista: Array[float] = [900.0, 1650.0, 3400.0]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--in="):
			in_path = a.substr(5)
		elif a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--png="):
			png_dir = a.substr(6)
		elif a.begins_with("--quality="):
			quality = int(a.substr(10))
		elif a.begins_with("--spec="):
			spec = float(a.substr(7))
		elif a.begins_with("--s="):
			lista.clear()
			for p in a.substr(4).split(",", false):
				lista.append(float(p))
	var cfg = JSON.parse_string(FileAccess.get_file_as_string(in_path))
	var cores: Array = cfg.get("cores", [])

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.set_physics_process(false)
	main.set_process(false)
	for n in ["hud", "touch", "speed_blur", "ghost_car"]:
		if main.get(n):
			main.get(n).visible = false
	main._set_quality(quality)
	main.car_view.visible = false
	var track: Track = main.track

	var acam := Camera3D.new()
	acam.near = 0.05
	acam.far = main.cam.far
	acam.environment = main.cam.environment
	acam.attributes = main.cam.attributes
	main.add_child(acam)
	acam.make_current()
	acam.keep_aspect = Camera3D.KEEP_HEIGHT
	acam.fov = FOV

	# material de tinta do cenário (o primeiro "pinta" achado), sem a textura de cor
	var base: BaseMaterial3D = _achar_pinta(main.track_view)
	if base == null:
		printerr("[calib] material pinta não encontrado")
		quit(1)
		return

	var por_quadro := FRENTE.size() * LADO.size()
	var medidas: Array = []
	var holder := Node3D.new()
	main.add_child(holder)
	for _f in 45:
		await process_frame
	var q := 0
	for s: float in lista:
		var k := 0
		while k < cores.size():
			for c in holder.get_children():
				c.queue_free()
			await process_frame
			var lote: Array = []
			var j := 0
			for fr: float in FRENTE:
				for ld: float in LADO:
					if k + j >= cores.size():
						break
					var col: Array = cores[k + j]
					var m := base.duplicate() as BaseMaterial3D
					m.albedo_texture = null
					m.albedo_color = Color8(int(col[0]), int(col[1]), int(col[2]))
					m.render_priority = 0
					if spec >= 0.0:
						m.metallic_specular = spec
					var mi := _retalho(track, s + fr, ld, m)
					holder.add_child(mi)
					lote.append({"in": col, "pos": _pt(track, s + fr, ld)})
					j += 1
			# câmera presa atrás de s, na direção da pista, sem rolagem
			var i := track.index_at(s)
			var fwd: Vector3 = (track.P[(i + 1) % track.n] - track.P[i]).normalized()
			fwd.y = 0.0
			fwd = fwd.normalized()
			var rgt := fwd.cross(Vector3.UP).normalized()
			var up := rgt.cross(fwd).normalized()
			var ground := _pt(track, s, 0.0)
			acam.global_position = ground - fwd * CAM_DIST + up * CAM_ALT
			acam.global_basis = Basis(rgt, deg_to_rad(CAM_PITCH)) * Basis(rgt, up, -fwd)
			for _f in 8:
				await process_frame
			RenderingServer.force_draw(true, 1.0 / 60.0)
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			if png_dir != "":
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + png_dir))
				img.save_png(ProjectSettings.globalize_path("res://%s/q%02d.png" % [png_dir, q]))
			q += 1
			for e in lote:
				# unproject_position dá coordenadas da viewport; a imagem pode ter outro tamanho (tela HiDPI)
				var esc := Vector2(img.get_size()) / root.get_visible_rect().size
				var p2 := acam.unproject_position(e.pos) * esc
				e.out = _mediana(img, Vector2i(roundi(p2.x), roundi(p2.y)), 6)
				e.s = s
				e.erase("pos")
				medidas.append(e)
			k += por_quadro
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"quality": quality, "medidas": medidas}))
	f.close()
	print("[calib] %d medidas em %s" % [medidas.size(), out_path])
	quit(0)


func _achar_pinta(n: Node) -> BaseMaterial3D:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			if m is BaseMaterial3D and String(m.resource_name).begins_with("pinta"):
				return m
	for c in n.get_children():
		var r := _achar_pinta(c)
		if r:
			return r
	return null


func _pt(track: Track, s: float, d: float) -> Vector3:
	var x := fposmod(s / Track.STEP, track.n)
	var i := int(x)
	var j := (i + 1) % track.n
	var f := x - i
	var nn := track.N[i].lerp(track.N[j], f).normalized()
	return track.P[i].lerp(track.P[j], f) + track.R[i].lerp(track.R[j], f) * d + nn * 0.03


## retalho plano seguindo a pista (4 cantos na superfície), normal para cima, UV como as fitas do gerador
func _retalho(track: Track, s: float, d: float, m: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := TAM.x * 0.5
	var hl := TAM.y * 0.5
	var c := [_pt(track, s - hl, d - hw), _pt(track, s - hl, d + hw), _pt(track, s + hl, d + hw), _pt(track, s + hl, d - hw)]
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.25), Vector2(0, 0.25)]
	for t in [0, 2, 1, 0, 3, 2]:
		st.set_uv(uv[t])
		st.add_vertex(c[t])
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _mediana(img: Image, c: Vector2i, r: int) -> Array:
	var rs: Array[float] = []
	var gs: Array[float] = []
	var bs: Array[float] = []
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var p := img.get_pixel(x, y)
			rs.append(p.r * 255.0)
			gs.append(p.g * 255.0)
			bs.append(p.b * 255.0)
	if rs.is_empty():
		return [-1, -1, -1]
	rs.sort()
	gs.sort()
	bs.sort()
	var h := rs.size() / 2
	return [rs[h], gs[h], bs[h]]
