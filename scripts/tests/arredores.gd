# Etapa 9: arredores no nível LMU. Monta a pista exportada (TrackView + SurroundingsView) e confere o anel de
# torres (quantidade, distância da pista, altura, uma chamada de desenho), o cilindro do horizonte, a torcida em
# cartões, a mata em capões e os limites de desenho dos presets (set_detail).
# uso: godot --headless --path . --script res://scripts/tests/arredores.gd
extends SceneTree

var ok := true


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func _find(n: Node, pred: Callable, out: Array) -> Array:
	if pred.call(n):
		out.append(n)
	for c in n.get_children():
		_find(c, pred, out)
	return out


func _is_crowd(n: Node) -> bool:
	return n is MeshInstance3D and SurroundingsView._is_crowd(n)


func _initialize() -> void:
	# teste de Interlagos: não depende da última pista escolhida no jogo (user://jogo.cfg)
	Game.track_id = Game.DEFAULT_TRACK
	_run.call_deferred()


func _run() -> void:
	var tv := TrackView.new()
	root.add_child(tv)
	await process_frame
	var sv: SurroundingsView = tv.get_node("Arredores")
	check(sv != null, "arredores montados pela pista")

	# torres: ~1.400 em um MultiMesh, todas a mais de 300 m da pista, 12–31 andares
	var mmi: MultiMeshInstance3D = sv.get_node("Torres")
	var mm := mmi.multimesh
	check(mm.instance_count > 1000, "anel com %d torres (> 1.000)" % mm.instance_count)
	# (no modo headless o MultiMesh não guarda as transformações: confere pelos dados exportados)
	var a: Array = JSON.parse_string(FileAccess.get_file_as_string(SurroundingsView.towers_path()))
	var hz_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SurroundingsView.horizon_path()))
	var hmin := INF
	var hmax := 0.0
	var rmin := INF
	var rmax := 0.0
	for k in a.size() / 8:
		var o := k * 8
		hmin = minf(hmin, a[o + 5])
		hmax = maxf(hmax, a[o + 5])
		var r := Vector2(a[o] - hz_data.x, a[o + 2] - hz_data.z).length()
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
	check(hmin > 30.0 and hmax < 200.0, "altura das torres (com o desnível do chão) entre %.0f e %.0f m" % [hmin, hmax])
	check(rmin > 300.0 and rmax < 3900.0, "torres entre %.0f e %.0f m do centro (dentro do horizonte)" % [rmin, rmax])
	check(mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "torres sem sombra")

	# horizonte: cilindro aberto de 3,9 km com a textura
	var hz: MeshInstance3D = sv.get_node("Horizonte")
	var aabb := hz.mesh.get_aabb()
	check(absf(aabb.size.x - 7800.0) < 5.0 and absf(aabb.size.y - 420.0) < 1.0, "horizonte %.0f × %.0f m" % [aabb.size.x, aabb.size.y])
	var tex: Texture2D = (hz.material_override as ShaderMaterial).get_shader_parameter("tex")
	check(tex != null and tex.get_width() == 4096, "textura do horizonte 4096 px")

	# torcida e mata (vêm do cenario.glb e do arvores_pos.json)
	var crowd := _find(tv, _is_crowd, [])
	check(crowd.size() > 10, "torcida em cartões: %d blocos de até 120 m" % crowd.size())
	var big := 0.0
	for c in crowd:
		var b: AABB = c.global_transform * c.get_aabb()
		big = maxf(big, maxf(b.size.x, b.size.z))
	check(big < 200.0, "maior bloco da torcida: %.0f m" % big)
	var trees := _find(tv, func(n): return n is MultiMeshInstance3D and SurroundingsView._is_tree(n), [])
	check(tv.trees > 5000, "mata com %d árvores em %d blocos" % [tv.trees, trees.size()])

	# presets: 0 = Mínimo, 1 = Leve, 2 = Médio, 3 = Extremo
	sv.set_detail(0)
	check(crowd.all(func(n): return not n.visible), "Mínimo: torcida desligada")
	sv.set_detail(1)
	check(crowd.all(func(n): return n.visible and n.visibility_range_end <= 220.0), "Leve: torcida até 220 m")
	check(trees.all(func(n): return n.visibility_range_end <= 1500.0), "Leve: mata até 1.500 m")
	sv.set_detail(3)
	check(crowd.all(func(n): return n.visible and n.visibility_range_end == 0.0), "Extremo: torcida sem limite")
	check(trees.all(func(n): return n.visibility_range_end == 0.0), "Extremo: mata sem limite")

	print("arredores: " + ("OK" if ok else "FALHOU"))
	quit(0 if ok else 1)
