# Pista de Interlagos a partir das amostras exportadas do jogo web (data/track.json, uma a cada 2 m).
# Chão analítico para a física (sem colisão de malha), igual ao jogo web, e malhas da pista para o visual.
class_name Track
extends RefCounted

const STEP := 2.0
const KERB_H := 0.025

enum { ASPHALT, KERB, RUNOFF, GRASS }
# aderência e arrasto por superfície (src/physics/ground.ts)
const GRIP := [1.0, 0.9, 0.85, 0.55]
const DRAG := [0.0, 0.0, 0.01, 0.08]

var n := 0
var P: PackedVector3Array
var T: PackedVector3Array
var R: PackedVector3Array
var wl: PackedFloat32Array
var wr: PackedFloat32Array
var kerb_l: PackedFloat32Array
var kerb_r: PackedFloat32Array
var run_l: PackedFloat32Array
var run_r: PackedFloat32Array
var wall_l: PackedFloat32Array
var wall_r: PackedFloat32Array
var length := 0.0

# resultado do último locate (evita alocar no loop de física)
var li := 0
var lcenter := Vector3.ZERO
var lr := Vector3.RIGHT
var lt := Vector3.FORWARD
var ln := Vector3.UP
var ld := 0.0
var lwl := 0.0
var lwr := 0.0
var lkl := 0.0
var lkr := 0.0
var lrl := 0.0
var lrr := 0.0
var lwalll := 0.0
var lwallr := 0.0


func _init(path: String) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	n = int(d.n)
	var s: Array = d.s
	var st := int(d.stride)
	for i in n:
		var o := i * st
		P.append(Vector3(s[o], s[o + 1], s[o + 2]))
		T.append(Vector3(s[o + 3], s[o + 4], s[o + 5]).normalized())
		R.append(Vector3(s[o + 6], 0, s[o + 7]).normalized())
		wl.append(s[o + 8]); wr.append(s[o + 9])
		kerb_l.append(s[o + 10]); kerb_r.append(s[o + 11])
		run_l.append(s[o + 12]); run_r.append(s[o + 13])
		wall_l.append(s[o + 14]); wall_r.append(s[o + 15])
	length = n * STEP


func nearest(p: Vector3, hint: int) -> int:
	var best := -1
	var bd := INF
	if hint < 0:
		for i in n:
			var q := P[i]
			var dd := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z) + 4.0 * (q.y - p.y) * (q.y - p.y)
			if dd < bd:
				bd = dd; best = i
		return best
	for k in range(-12, 13):
		var i := (hint + k + n) % n
		var q := P[i]
		var dd := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
		if dd < bd:
			bd = dd; best = i
	return best


## Posição na pista: preenche li, lcenter, lr, lt, ln, ld (lateral, + direita) e larguras interpoladas.
func locate(p: Vector3, hint: int) -> void:
	var i := nearest(p, hint)
	if (p - P[i]).dot(T[i]) < 0.0:
		i = (i - 1 + n) % n
	var j := (i + 1) % n
	var seg := P[j] - P[i]
	var f := clampf((p - P[i]).dot(seg) / seg.length_squared(), 0.0, 1.0)
	li = i
	lcenter = P[i].lerp(P[j], f)
	lr = R[i].lerp(R[j], f).normalized()
	lt = seg.normalized()
	ln = lr.cross(lt).normalized()
	var off := p - lcenter
	ld = off.x * lr.x + off.z * lr.z
	lwl = lerpf(wl[i], wl[j], f); lwr = lerpf(wr[i], wr[j], f)
	lkl = lerpf(kerb_l[i], kerb_l[j], f); lkr = lerpf(kerb_r[i], kerb_r[j], f)
	lrl = lerpf(run_l[i], run_l[j], f); lrr = lerpf(run_r[i], run_r[j], f)
	lwalll = lerpf(wall_l[i], wall_l[j], f); lwallr = lerpf(wall_r[i], wall_r[j], f)


func surface_at(d: float) -> int:
	var a := absf(d)
	var edge := lwl if d < 0.0 else lwr
	var k := lkl if d < 0.0 else lkr
	var r := lrl if d < 0.0 else lrr
	if a <= edge: return ASPHALT
	if a <= edge + k: return KERB
	if a <= edge + k + r: return RUNOFF
	return GRASS


## Raio de origin na direção dir (unitária). Devolve a distância (ou -1) e deixa hit_point/hit_normal/hit_surface.
var hit_point := Vector3.ZERO
var hit_normal := Vector3.UP
var hit_surface := ASPHALT

func probe(origin: Vector3, dir: Vector3, max_dist: float, hint: int) -> float:
	locate(origin, hint)
	var sfc := surface_at(ld)
	var plane_p := lcenter + ln * (KERB_H if sfc == KERB else (-0.02 if sfc == GRASS else 0.0))
	var den := dir.dot(ln)
	if den > -1e-4:
		return -1.0
	var dist := (plane_p - origin).dot(ln) / den
	if dist < 0.0 or dist > max_dist:
		return -1.0
	hit_point = origin + dir * dist
	hit_normal = ln
	hit_surface = sfc
	return dist


## Penetração no muro (m) e normal que empurra de volta (wall_normal).
var wall_normal := Vector3.ZERO

func wall_penetration(p: Vector3, hint: int) -> float:
	locate(p, hint)
	if ld < -lwalll:
		wall_normal = lr
		return -lwalll - ld
	if ld > lwallr:
		wall_normal = -lr
		return ld - lwallr
	return 0.0


# ---------------------------------------------------------------- malhas

## Faixa ao longo da pista entre dois deslocamentos laterais (funções do índice), na altura y.
func ribbon(a: Callable, b: Callable, y: float, mat: Material, u_scale := 4.0, v_scale := 4.0, skip_zero := false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := 0.0
	for k in n + 1:
		var i := k % n
		var oa: float = a.call(i)
		var ob: float = b.call(i)
		var up := R[i].cross(T[i]).normalized()
		var pa := P[i] + R[i] * oa + up * y
		var pb := P[i] + R[i] * ob + up * y
		if k > 0:
			var j := (k - 1) % n
			var oa0: float = a.call(j)
			var ob0: float = b.call(j)
			if not (skip_zero and absf(ob - oa) < 0.01 and absf(ob0 - oa0) < 0.01):
				var up0 := R[j].cross(T[j]).normalized()
				var qa := P[j] + R[j] * oa0 + up0 * y
				var qb := P[j] + R[j] * ob0 + up0 * y
				var s0 := s - STEP
				_quad(st, qa, qb, pa, pb, Vector2(oa0 / u_scale, s0 / v_scale), Vector2(ob0 / u_scale, s0 / v_scale),
					Vector2(oa / u_scale, s / v_scale), Vector2(ob / u_scale, s / v_scale), up)
		s += STEP
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


func _quad(st: SurfaceTool, qa: Vector3, qb: Vector3, pa: Vector3, pb: Vector3, uqa: Vector2, uqb: Vector2, upa: Vector2, upb: Vector2, nrm: Vector3) -> void:
	# a = esquerda, b = direita; q = amostra anterior, p = atual. Ordem horária vista de cima (Godot: frente = horário)
	for v in [[qa, uqa], [pa, upa], [pb, upb], [qa, uqa], [pb, upb], [qb, uqb]]:
		st.set_normal(nrm)
		st.set_uv(v[1])
		st.add_vertex(v[0])


## Muro vertical no deslocamento lateral off(i), de y0 a y1.
func wall(off: Callable, y0: float, y1: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := 0.0
	for k in range(1, n + 1):
		var i := k % n
		var j := k - 1
		var a := P[j] + R[j] * float(off.call(j))
		var b := P[i] + R[i] * float(off.call(i))
		var nrm := -R[i] * signf(float(off.call(i)))
		for v in [[a + Vector3.UP * y0, Vector2(s / 3.0, 1)], [a + Vector3.UP * y1, Vector2(s / 3.0, 0)], [b + Vector3.UP * y1, Vector2((s + STEP) / 3.0, 0)],
				[a + Vector3.UP * y0, Vector2(s / 3.0, 1)], [b + Vector3.UP * y1, Vector2((s + STEP) / 3.0, 0)], [b + Vector3.UP * y0, Vector2((s + STEP) / 3.0, 1)]]:
			st.set_normal(nrm)
			st.set_uv(v[1])
			st.add_vertex(v[0])
		s += STEP
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi
