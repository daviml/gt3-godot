# Chão para a física (src/physics/ground.ts do web): a física só precisa de raio para baixo e da penetração
# no muro. Track implementa isso para a pista; FlatGround é o chão plano dos testes.
class_name Ground
extends RefCounted

enum { ASPHALT, KERB, RUNOFF, GRASS, GRAVEL }
# aderência e arrasto de rolagem por superfície (iguais ao SURFACES do web)
const GRIP := [1.0, 0.9, 0.85, 0.55, 0.45]
const DRAG := [0.0, 0.0, 0.01, 0.08, 0.35]
const NAMES := ["asfalto", "zebra", "escape", "grama", "brita"]

# resultado do último probe (evita alocar no laço de física)
var hit_point := Vector3.ZERO
var hit_normal := Vector3.UP
var hit_surface := ASPHALT
## relevo da zebra no ponto (m acima do perfil liso): para vibração do controle e do som
var hit_bump := 0.0
var wall_normal := Vector3.ZERO


## Índice da pista perto de p (0 no chão plano). hint = último índice (-1 = busca completa).
func nearest(_p: Vector3, _hint: int) -> int:
	return 0


## Raio de origin na direção dir (unitária). Devolve a distância (ou -1) e preenche hit_*.
func probe(_origin: Vector3, _dir: Vector3, _max_dist: float, _hint: int) -> float:
	return -1.0


## Penetração (m) de p no muro e normal que empurra de volta (wall_normal); 0 = livre.
func wall_penetration(_p: Vector3, _hint: int) -> float:
	return 0.0
