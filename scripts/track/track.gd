# Pista de Interlagos a partir das amostras exportadas do jogo web (data/track.json, uma a cada 2 m).
# Chão analítico para a física (sem colisão de malha), igual ao Track do web (src/track/track.ts), e malhas da
# pista para o visual.
class_name Track
extends Ground

const STEP := 2.0
## zebra padrão (src/track/track.ts): perfil sobe KERB_H na borda da pista e desce até 0 em KERB_WIDTH
const KERB_H := 0.025
const KERB_WIDTH := 1.2
## "zebra pulando" (só no Godot): ondulação de KERB_RIPPLE m a cada KERB_WAVE m, uma por listra da pintura
const KERB_RIPPLE := 0.003
const KERB_WAVE := 1.5

var n := 0
var P: PackedVector3Array
var T: PackedVector3Array
var R: PackedVector3Array
var N: PackedVector3Array
var wl: PackedFloat32Array
var wr: PackedFloat32Array
var kerb_l: PackedFloat32Array
var kerb_r: PackedFloat32Array
var run_l: PackedFloat32Array
var run_r: PackedFloat32Array
var wall_l: PackedFloat32Array
var wall_r: PackedFloat32Array
## curvatura (1/m, + = curva para a direita), como Sample.curv do web
var curv: PackedFloat32Array
var length := 0.0
## trechos com nome (S do Senna, Curva do Sol...): [{name, s0, s1}]
var sections: Array = []
## inclinação lateral (camber, rad, + = lado direito mais alto) por amostra; só em pistas com "bank" no track.json
## (Interlagos não tem: R fica horizontal, exatamente como antes)
var bank := PackedFloat32Array()
var has_bank := false

# resultado do último locate (evita alocar no loop de física)
var li := 0
var ls := 0.0
var lcenter := Vector3.ZERO
var lr := Vector3.RIGHT
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


func _init(path := "", data: Dictionary = {}) -> void:
	var d: Dictionary = data if not data.is_empty() else JSON.parse_string(FileAccess.get_file_as_string(path))
	n = int(d.n)
	var s: Array = d.s
	var st := int(d.stride)
	for i in n:
		var o := i * st
		P.append(Vector3(s[o], s[o + 1], s[o + 2]))
		T.append(Vector3(s[o + 3], s[o + 4], s[o + 5]).normalized())
		R.append(Vector3(s[o + 6], 0, s[o + 7]).normalized())
		N.append(R[i].cross(T[i]).normalized())
		wl.append(s[o + 8]); wr.append(s[o + 9])
		kerb_l.append(s[o + 10]); kerb_r.append(s[o + 11])
		run_l.append(s[o + 12]); run_r.append(s[o + 13])
		wall_l.append(s[o + 14]); wall_r.append(s[o + 15])
	length = n * STEP
	sections = d.get("sections", [])
	# camber: gira a lateral em torno da tangente (mesma conta do tools/tracks/bank.ts, usada no cenário)
	if d.has("bank"):
		has_bank = true
		var b: Array = d.bank
		for i in n:
			var th := float(b[i])
			bank.append(th)
			R[i] = (R[i] * cos(th) + N[i] * sin(th)).normalized()
			N[i] = R[i].cross(T[i]).normalized()
	# curvatura pela variação de rumo em ±5 amostras (igual ao web)
	for i in n:
		var a := T[(i - 5 + n) % n]
		var b := T[(i + 5) % n]
		curv.append(asin(clampf(a.x * b.z - a.z * b.x, -1.0, 1.0)) / (10.0 * STEP))


func has_kerb(i: int) -> bool:
	return kerb_l[i] > 0.0 or kerb_r[i] > 0.0


## nome do trecho em s (o último que começou antes de s, dando a volta)
func section_at(s: float) -> String:
	if sections.is_empty():
		return ""
	var cur: Dictionary = sections[sections.size() - 1]
	for sec in sections:
		if sec.s0 <= s:
			cur = sec
	return cur.name


## Índice da amostra em s (m), dando a volta.
func index_at(s: float) -> int:
	return posmod(roundi(s / STEP), n)


func nearest(p: Vector3, hint: int) -> int:
	return _nearest(p, hint, 12)


## nearest com janela de busca ±win em torno do hint. Rodas e cantos da carroceria ficam a menos de 2,6 m do
## centro do carro (o hint), então ±WIN_NEAR amostras (4 m) bastam e reduzem buscas na física.
const WIN_NEAR := 2

func _nearest(p: Vector3, hint: int, win: int) -> int:
	var best := -1
	var bd := INF
	if hint < 0:
		for i in n:
			var q := P[i]
			var dd := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z) + 4.0 * (q.y - p.y) * (q.y - p.y)
			if dd < bd:
				bd = dd; best = i
		return best
	var w0 := mini(win, 3)
	var best_k := 0
	for k in range(-w0, w0 + 1):
		var i := (hint + k + n) % n
		var q := P[i]
		var dd := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
		if dd < bd:
			bd = dd; best = i; best_k = k
	# Só expande a busca se o mínimo caiu na borda da janela curta (±3 amostras = ±6 m)
	if win > w0 and (best_k == -w0 or best_k == w0):
		for k in range(-win, -w0):
			var i := (hint + k + n) % n
			var q := P[i]
			var dd := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
			if dd < bd:
				bd = dd; best = i
		for k in range(w0 + 1, win + 1):
			var i := (hint + k + n) % n
			var q := P[i]
			var dd := (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
			if dd < bd:
				bd = dd; best = i
	return best


## Posição na pista: preenche li, ls, lcenter, lr, ln, ld (lateral, + direita) e larguras interpoladas.
## Projeção no plano horizontal, como o locate do web.
func locate(p: Vector3, hint: int, win := 12) -> void:
	var i := _nearest(p, hint, win)
	if (p - P[i]).dot(T[i]) < 0.0:
		i = (i - 1 + n) % n
	var j := (i + 1) % n
	var sx := P[j].x - P[i].x
	var sz := P[j].z - P[i].z
	var f := clampf(((p.x - P[i].x) * sx + (p.z - P[i].z) * sz) / (sx * sx + sz * sz), 0.0, 1.0)
	li = i
	ls = (i + f) * STEP
	lcenter = P[i].lerp(P[j], f)
	lr = R[i].lerp(R[j], f).normalized()
	ln = N[i].lerp(N[j], f).normalized()
	var off := p - lcenter
	# com camber, a lateral é medida ao longo da pista inclinada (a altura acima dela fica na normal)
	ld = off.dot(lr) if has_bank else off.x * lr.x + off.z * lr.z
	lwl = lerpf(wl[i], wl[j], f); lwr = lerpf(wr[i], wr[j], f)
	# zebra que começa/termina entre as amostras: vale a mais larga das duas (como no web)
	lkl = maxf(kerb_l[i], kerb_l[j]); lkr = maxf(kerb_r[i], kerb_r[j])
	lrl = lerpf(run_l[i], run_l[j], f); lrr = lerpf(run_r[i], run_r[j], f)
	lwalll = lerpf(wall_l[i], wall_l[j], f); lwallr = lerpf(wall_r[i], wall_r[j], f)


func surface_at(d: float) -> int:
	var a := absf(d)
	var edge := lwl if d < 0.0 else lwr
	var k := lkl if d < 0.0 else lkr
	var r := lrl if d < 0.0 else lrr
	if a <= edge: return ASPHALT
	if a < edge + k: return KERB
	if a < edge + k + r: return RUNOFF
	return GRASS


func probe(origin: Vector3, dir: Vector3, max_dist: float, hint: int) -> float:
	locate(origin, hint, WIN_NEAR)
	var d := ld
	var ad := absf(d)
	# além do muro não há chão desta pista (evita "achar" o chão de outro trecho)
	if ad > (lwalll if d < 0.0 else lwallr) + 2.0:
		return -1.0
	var sfc := surface_at(d)
	var h := 0.0
	hit_bump = 0.0
	if sfc == KERB:
		# perfil da zebra padrão na parte de dentro; a parte larga da saída é plana (web) + ondulação (Godot)
		h = KERB_H * maxf(0.0, 1.0 - (ad - (lwl if d < 0.0 else lwr)) / KERB_WIDTH)
		hit_bump = KERB_RIPPLE * 0.5 * (1.0 - cos(TAU * ls / KERB_WAVE))
		h += hit_bump
	var plane_p := lcenter + lr * d + ln * h
	var den := -dir.dot(ln)
	if den < 1e-4:
		return -1.0
	var dist := (origin - plane_p).dot(ln) / den
	if dist < -0.5 or dist > max_dist:
		return -1.0
	dist = maxf(0.0, dist)
	hit_point = origin + dir * dist
	hit_normal = ln
	hit_surface = sfc
	return dist


func wall_penetration(p: Vector3, hint: int) -> float:
	locate(p, hint, WIN_NEAR)
	if ld > lwallr:
		wall_normal = -lr
		return ld - lwallr
	if ld < -lwalll:
		wall_normal = lr
		return -lwalll - ld
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
