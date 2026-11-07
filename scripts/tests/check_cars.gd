# Confere os dados exportados pelo tools/prep.ts: cada carro de data/cars.json abre, tem acerto e acha as 4 rodas.
# uso: godot --headless --path . --script res://scripts/tests/check_cars.gd
extends SceneTree

func _init() -> void:
	var ok := true
	var cars: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars.json"))
	for c in cars:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cars/%s.json" % c.id))
		var scene: PackedScene = load(d.model.glb)
		var root := scene.instantiate() if scene else null
		var found := 0
		for w in d.model.wheels:
			if root and root.find_child(w.name, true, false):
				found += 1
		var p: Dictionary = d.params
		var line := "%-24s rodas %d/4  massa %d  peso dianteiro %.2f  limitador %d  marchas %d" % [c.id, found, p.mass, p.weightFront, p.engine.limiter, p.gearbox.ratios.size()]
		if found != 4 or root == null:
			ok = false
			line += "  <-- FALHOU"
		print(line)
		if root:
			root.free()
	var t: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/track/track.json"))
	print("pista: %d amostras, %d curvas com nome" % [t.n, t.sections.size()])
	var snd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sounds.json"))
	for b in snd.banks:
		for f in snd.banks[b]:
			if not ResourceLoader.exists(f.file):
				ok = false
				print("som faltando: ", f.file)
	print("sons: %d bancos, %d efeitos" % [snd.banks.size(), snd.fx.size()])
	print("OK" if ok else "FALHOU")
	quit(0 if ok else 1)
