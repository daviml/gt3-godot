# Auditoria completa dos 13 carros GT3: contagem de triângulos e mapeamento espacial de materiais de luzes/vidros.
# uso: godot --headless --path . --script res://scripts/tests/audit_cars.gd
extends SceneTree

static var _light_re := RegEx.create_from_string("(?i)light|lamp|hl|tl|fl|tail|brake|fog|fof|red_glass|emissive|glass|window")

func _init() -> void:
	var cars: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars.json"))
	var summary := []
	for c in cars:
		var cid: String = str(c.id)
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars/%s.json" % cid))
		var root: Node = (load(d.model.glb) as PackedScene).instantiate()
		var mw: Array = d.model.wheels
		var front_z: float = (float(mw[0].z) + float(mw[1].z)) * 0.5
		var rear_z: float = (float(mw[2].z) + float(mw[3].z)) * 0.5
		var mid_z: float = (front_z + rear_z) * 0.5

		var stats := {"tris_base": 0, "tris_blur": 0, "meshes": 0, "surfaces": 0}
		var mat_zones := {} # mat_name -> {z_min, z_max, tris, zones, mat, nodes}
		_walk(root, Transform3D.IDENTITY, false, mid_z, stats, mat_zones)

		print("=================================================================")
		print("CAR: %s | tris_base=%d | tris_blur=%d | meshes=%d | surfaces=%d | front_z=%.2f rear_z=%.2f" % [
			cid, stats.tris_base, stats.tris_blur, stats.meshes, stats.surfaces, front_z, rear_z
		])

		var front_mats := []
		var rear_mats := []
		var both_mats := []
		var mat_names := mat_zones.keys()
		mat_names.sort()
		for mname in mat_names:
			var info: Dictionary = mat_zones[mname]
			var is_light := _light_re.search(mname) != null
			var zone_str := _classify_zone(info.z_min, info.z_max, mid_z)
			if is_light:
				var m: BaseMaterial3D = info.mat as BaseMaterial3D
				var tex := "T" if (m and m.albedo_texture != null) else "-"
				var em := "T" if (m and m.emission_enabled) else "-"
				var tr := str(m.transparency) if m else "-"
				var col := ("%.2f,%.2f,%.2f,%.2f" % [m.albedo_color.r, m.albedo_color.g, m.albedo_color.b, m.albedo_color.a]) if m else "-"
				print("  [LUZ/VIDRO] %-42s zone=%-5s z=[%.2f..%.2f] tris=%5d tex=%s em=%s tr=%s rgba=(%s)" % [
					mname, zone_str, info.z_min, info.z_max, info.tris, tex, em, tr, col
				])
				if zone_str == "FRONT":
					front_mats.append(mname)
				elif zone_str == "REAR":
					rear_mats.append(mname)
				else:
					both_mats.append(mname)

		summary.append({
			"id": cid,
			"tris_base": stats.tris_base,
			"tris_blur": stats.tris_blur,
			"front": front_mats,
			"rear": rear_mats,
			"both": both_mats,
		})
		root.free()

	print("\n=================================================================")
	print("RESUMO GERAL (13 CARROS)")
	print("=================================================================")
	for s in summary:
		print("%-30s | tris=%7d (+blur %6d) | F=%d R=%d BOTH=%d" % [
			s.id, s.tris_base, s.tris_blur, s.front.size(), s.rear.size(), s.both.size()
		])
	quit()


func _classify_zone(z_min: float, z_max: float, mid_z: float) -> String:
	if z_max < mid_z:
		return "FRONT"
	if z_min > mid_z:
		return "REAR"
	return "BOTH"


func _walk(n: Node, xform: Transform3D, in_blur: bool, mid_z: float, stats: Dictionary, mat_zones: Dictionary) -> void:
	var cur_xform := xform
	if n is Node3D:
		cur_xform = xform * (n as Node3D).transform
	var blur_here := in_blur or n.name.begins_with("blur_")

	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			stats.meshes += 1
			for s in mesh.get_surface_count():
				stats.surfaces += 1
				var arr := mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				var tris: int = (indices.size() / 3) if indices.size() > 0 else (verts.size() / 3)
				if blur_here:
					stats.tris_blur += tris
				else:
					stats.tris_base += tris

				var z_min := INF
				var z_max := -INF
				for v in verts:
					var wv := cur_xform * v
					if wv.z < z_min:
						z_min = wv.z
					if wv.z > z_max:
						z_max = wv.z

				var m := mesh.surface_get_material(s)
				var mname := String(m.resource_name) if (m and m.resource_name != "") else "<sem_nome>"
				if not mat_zones.has(mname):
					mat_zones[mname] = {
						"z_min": z_min,
						"z_max": z_max,
						"tris": tris,
						"mat": m,
					}
				else:
					var info: Dictionary = mat_zones[mname]
					info.z_min = minf(info.z_min, z_min)
					info.z_max = maxf(info.z_max, z_max)
					info.tris += tris

	for c in n.get_children():
		_walk(c, cur_xform, blur_here, mid_z, stats, mat_zones)
