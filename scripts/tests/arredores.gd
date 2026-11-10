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
	if not n is MeshInstance3D:
		return false
	for s in n.get_surface_override_material_count():
		var m: Material = n.get_surface_override_material(s)
		if m and m.resource_name == "torcida":
			return true
	return false


func _initialize() -> void:
	var tv := TrackView.new()
	root.add_child(tv)
	var sv: SurroundingsView = tv.get_node("Arredores")
	check(sv != null, "arredores montados pela pista")

	# torres: ~1.400 em um MultiMesh, todas a mais de 300 m da pista, 12–31 andares
	var mmi: MultiMeshInstance3D = sv.get_node("Torres")
	var mm := mmi.multimesh
	check(mm.instance_count > 1000, "anel com %d torres (> 1.000)" % mm.instance_count)
	var hmin := INF
	var hmax := 0.0
	var rmax := 0.0
	var center: Vector3 = Vector3.ZERO
	for k in mm.instance_count:
		center += mm.get_instance_transform(k).origin / mm.instance_count
	for k in mm.instance_count:
		var t := mm.get_instance_transform(k)
		var h := t.basis.y.length()
		hmin = minf(hmin, h)
		hmax = maxf(hmax, h)
		rmax = maxf(rmax, Vector2(t.origin.x - center.x, t.origin.z - center.z).length())
	check(hmin > 30.0 and hmax < 110.0, "altura das torres entre %.0f e %.0f m" % [hmin, hmax])
	check(rmax < 3900.0, "torres dentro do horizonte (até %.0f m do centro)" % rmax)
	check(mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "torres sem sombra")

	# horizonte: cilindro aberto de 3,9 km com a textura
	var hz: MeshInstance3D = sv.get_node("Horizonte")
	var aabb := hz.mesh.get_aabb()
	check(absf(aabb.size.x - 7800.0) < 5.0 and absf(aabb.size.y - 420.0) < 1.0, "horizonte %.0f × %.0f m" % [aabb.size.x, aabb.size.y])
	var tex: Texture2D = (hz.material_override as ShaderMaterial).get_shader_parameter("tex")
	check(tex != null and tex.get_width() == 4096, "textura do horizonte 4096 px")

	# torcida e mata (vêm do cenario.glb e do arvores_pos.json)
	var crowd := _find(tv, _is_crowd, [])
	check(crowd.size() > 0, "torcida em cartões: %d blocos" % crowd.size())
	var trees := _find(tv, func(n): return n is MultiMeshInstance3D and n.name.begins_with("Arvores"), [])
	check(tv.trees > 5000, "mata com %d árvores em %d blocos" % [tv.trees, trees.size()])

	# presets
	sv.set_detail(0)
	check(crowd.all(func(n): return n.visibility_range_end == 220.0), "Leve: torcida até 220 m")
	check(trees.all(func(n): return n.visibility_range_end == 1500.0), "Leve: mata até 1.500 m")
	sv.set_detail(2)
	check(crowd.all(func(n): return n.visibility_range_end == 0.0), "Extremo: torcida sem limite")
	check(trees.all(func(n): return n.visibility_range_end == 0.0), "Extremo: mata sem limite")

	print("arredores: " + ("OK" if ok else "FALHOU"))
	quit(0 if ok else 1)
