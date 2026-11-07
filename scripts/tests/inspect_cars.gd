# Lista, para cada carro, os materiais (nome, metal, rugosidade, transparência, texturas) e o que há dentro dos
# nós das rodas (pinças, discos). Diagnóstico da etapa 6.
# uso: godot --headless --path . --script res://scripts/tests/inspect_cars.gd [-- <id>]
extends SceneTree

func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		only = a
	var cars: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars.json"))
	for c in cars:
		if only != "" and c.id != only:
			continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars/%s.json" % c.id))
		var root: Node = (load(d.model.glb) as PackedScene).instantiate()
		print("== ", c.id)
		var seen := {}
		_walk(root, seen, 0, "")
		for w in d.model.wheels:
			var wn: Node = root.find_child(w.name, true, false)
			print("  roda ", w.name, " superfícies: ", _mats(wn), " filhos: ", _names(wn))
		root.free()
	quit()

func _names(n: Node) -> String:
	var out := []
	for c in n.get_children():
		out.append("%s[%s]" % [c.name, _mats(c)])
		if c.get_child_count() > 0:
			out.append("{" + _names(c) + "}")
	return " ".join(out)

func _mats(n: Node) -> String:
	if not (n is MeshInstance3D):
		return ""
	var m := (n as MeshInstance3D).mesh
	var out := []
	for s in m.get_surface_count():
		var mt := m.surface_get_material(s)
		out.append(String(mt.resource_name) if mt else "-")
	return ",".join(out)

func _walk(n: Node, seen: Dictionary, depth: int, path: String) -> void:
	if n is MeshInstance3D:
		var m := (n as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var mt := m.surface_get_material(s)
			if mt == null or seen.has(mt):
				continue
			seen[mt] = true
			if mt is BaseMaterial3D:
				var b := mt as BaseMaterial3D
				var fmt: int = (m as ArrayMesh).surface_get_format(s) if m is ArrayMesh else 0
				print("  mat %-40s met %.2f%s rough %.2f%s alpha %d a=%.2f uv2=%s nrm=%s em=%s" % [b.resource_name, b.metallic,
					"+T" if b.metallic_texture else "", b.roughness, "+T" if b.roughness_texture else "",
					b.transparency, b.albedo_color.a, "s" if (fmt & Mesh.ARRAY_FORMAT_TEX_UV2) else "-",
					"T" if b.normal_texture else "-", "T" if b.emission_enabled else "-"])
	for c in n.get_children():
		_walk(c, seen, depth + 1, path)
