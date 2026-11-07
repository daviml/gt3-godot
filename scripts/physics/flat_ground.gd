# Chão plano de asfalto em y = 0 (FlatGround do web), para os testes de física.
class_name FlatGround
extends Ground


func probe(origin: Vector3, dir: Vector3, max_dist: float, _hint: int) -> float:
	if dir.y > -1e-6:
		return -1.0
	var dist := origin.y / -dir.y
	if dist < 0.0 or dist > max_dist:
		return -1.0
	hit_point = origin + dir * dist
	hit_normal = Vector3.UP
	hit_surface = ASPHALT
	hit_bump = 0.0
	return dist
