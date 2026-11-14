# Câmeras (a Camera3D deve ser filha de um nó na origem): perseguição (padrão, estilo LMU), capô e longe. Porte de gt3-time-attack/src/render/camera.ts.
# A perseguição fica presa atrás e acima do carro: gira quase junto com ele, com um atraso curto, altura
# filtrada e pouca variação de distância — dá para sentir a pista sem a câmera balançar.
class_name ChaseCamera
extends RefCounted

const MODES := ["perseguição", "capô", "longe"]


## Mola criticamente amortecida (SmoothDamp): segue o alvo em ~`time` segundos, sem passar dele.
class Spring:
	var value := 0.0
	var vel := 0.0

	func _init(v := 0.0) -> void:
		value = v

	func update(target: float, time: float, dt: float) -> float:
		var omega := 2.0 / maxf(time, 1e-4)
		var x := omega * dt
		var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
		var change := value - target
		var temp := (vel + omega * change) * dt
		vel = (vel - omega * temp) * e
		value = target + (change + temp) * e
		return value

	func reset(v: float) -> void:
		value = v
		vel = 0.0


var mode := 0
var cam: Camera3D
var car: Car
var heading := Vector3(0, 0, -1)
var dist := Spring.new(6.4)
var py := Spring.new()
var look_y := Spring.new()
var fov := Spring.new(55.0)
## força G longitudinal filtrada (sem os picos da troca de marcha)
var gl := Spring.new()
## força G lateral filtrada (apoio em curva)
var glat := Spring.new()
## intensidade da tremida (zebra / alta velocidade), suavizada
var shake := Spring.new()
var time := 0.0
var first := true
## quanto da subida/descida prevista a câmera antecipa (s); 0 = comportamento antigo (só para comparar em teste)
var climb_lead := 0.2
## velocidade de subida suavizada (a rampa muda devagar; tira os pulos da suspensão na zebra)
var climb_v := Spring.new()


func _init(c: Camera3D, cr: Car) -> void:
	cam = c
	car = cr


func mode_name() -> String:
	return MODES[mode]


func next() -> void:
	mode = (mode + 1) % MODES.size()
	first = true


## depois de um reset do carro, a câmera pula direto para trás dele
func snap() -> void:
	first = true


## FOV vertical que mantém pelo menos a visão lateral de uma tela 16:9 em janelas estreitas/retrato.
static func fit_fov(fov16x9: float, aspect: float) -> float:
	if aspect >= 16.0 / 9.0:
		return fov16x9
	var half_h := tan(deg_to_rad(fov16x9) / 2.0) * (16.0 / 9.0)
	return minf(100.0, rad_to_deg(2.0 * atan(half_h / aspect)))


func update(dt: float, frac := 1.0) -> void:
	var v_pos := car.visual_pos(frac)
	var b := car.visual_basis(frac)
	var aspect := 16.0 / 9.0
	if cam.is_inside_tree():
		var vp := cam.get_viewport().get_visible_rect().size
		aspect = vp.x / maxf(1.0, vp.y)
	var fwd := -b.z
	fwd.y = 0.0
	fwd = fwd.normalized()

	if mode == 1:  # capô
		cam.transform = Transform3D(b, v_pos + b * Vector3(0, 0.85, -1.3))
		cam.fov = fit_fov(75.0, aspect)
		return

	# câmera presa atrás do carro: segue a frente dele com um atraso curto (só o bastante para sentir a curva)
	var speed := Vector2(car.vel.x, car.vel.z).length()
	if first:
		heading = fwd
	var far := mode == 2
	var follow_rate := 6.5 if far else 10.0
	heading = heading.lerp(fwd, 1.0 - exp(-dt * follow_rate)).normalized()
	var lag := atan2(heading.x * fwd.z - heading.z * fwd.x, heading.dot(fwd))
	var max_lag := deg_to_rad(6.0 if far else 4.0)
	if absf(lag) > max_lag:
		# mesmo sentido do applyAxisAngle do three.js (rotação positiva em torno de +Y)
		heading = fwd.rotated(Vector3.UP, signf(lag) * max_lag)

	# Perseguição padrão mais próxima e focada no carro; "longe" mantém enquadramento amplo
	var base_dist := 11.0 if far else 5.3
	var height := 3.4 if far else 1.55
	if first:
		dist.reset(base_dist)
		py.reset(v_pos.y + height)
		look_y.reset(v_pos.y + (0.75 if far else 0.65))
		fov.reset(50.0 if far else 55.0)
		gl.reset(0.0)
		glat.reset(0.0)
		shake.reset(0.0)
		climb_v.reset(maxf(0.0, car.vel.y))
		first = false
	# Freada puxa a câmera para frente e aceleração empurra para trás (força G filtrada para não dar tranco na marcha)
	var g := gl.update(clampf(car.g_long, -2.2, 1.0), 0.25 if far else 0.16, dt)
	var lat := glat.update(clampf(car.g_lat, -2.5, 2.5), 0.18, dt)
	var g_dist := (g * 0.16 if g < 0.0 else g * 0.24) if far else (g * 0.34 if g < 0.0 else g * 0.50)
	var d := dist.update(base_dist + g_dist, 0.45 if far else 0.22, dt)
	var right := Vector3(-heading.z, 0.0, heading.x)
	var pos := v_pos - heading * d + (Vector3.ZERO if far else right * (lat * 0.14))
	# altura bem filtrada: zebra e lombada não chacoalham a câmera. A mola atrasa ~0,2 s: numa subida longa
	# (Rahal Straight de Laguna, 13% a 160 km/h = 6 m/s) a câmera ficava 1,2 m abaixo, atrás do teto do carro.
	# Somar a subida prevista nesses 0,2 s cancela o atraso em rampa e mantém o filtro dos trancos curtos.
	var climb := climb_v.update(maxf(0.0, car.vel.y), 0.3, dt) * climb_lead  # na descida o atraso ajuda (câmera alta enxerga a pista caindo)
	pos.y = py.update(v_pos.y + height + climb, 0.2, dt)
	# tremida leve apenas ao passar na zebra (sem vibração contínua em alta velocidade)
	time += dt
	var on_kerb := false
	for w in car.wheels:
		on_kerb = on_kerb or (w.contact and w.surface == Ground.KERB and w.fz > 500.0)
	var kmh := speed * 3.6
	var amp := shake.update(0.012 if on_kerb else 0.0, 0.08, dt)
	if amp > 1e-4:
		pos.y += amp * (sin(time * 61.0) * 0.6 + sin(time * 97.0 + 1.3) * 0.4)
		pos += right * (amp * 0.5 * sin(time * 73.0 + 0.7))
	var look := v_pos + heading * (3.0 if far else 1.1)
	look.y = look_y.update(v_pos.y + (0.8 if far else 0.65) + climb, 0.2, dt)
	var up := Vector3.UP if far else Vector3.UP.rotated(heading, deg_to_rad(clampf(-lat * 0.7, -1.8, 1.8)))
	# transform local: a câmera é filha direta da cena (sem deslocamento), então vale como global
	cam.transform = Transform3D(Basis.looking_at(look - pos, up), pos)
	# FOV abre progressivamente com a velocidade + leve resposta longitudinal de força G
	var target_fov := (50.0 + minf(3.5, speed * 0.045)) if far else (55.0 + minf(9.5, kmh * 0.034) + g * 1.4)
	cam.fov = fit_fov(fov.update(target_fov, 0.8 if far else 0.28, dt), aspect)
