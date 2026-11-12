// Teste de paridade da física, lado web: roda a física do jogo web (src/physics/car.ts) nos mesmos ensaios do
// scripts/tests/paridade.gd e grava os números em data/tests/paridade-web.json, junto com o acerto usado.
// O Godot lê esse arquivo e compara com a física dele (godot --headless --script res://scripts/tests/paridade.gd).
//
// Ensaios (iguais aos do vitest tests/physics.test.ts, scripts/envelope.ts, tests/track.test.ts e
// scripts/tune-physics.ts): assentar parado, 0–100, máxima, 200–0, g lateral a 72 e 216 km/h, envelope por
// velocidade (lateral, freada, aceleração), volta do Bot simples e volta lançada do RefBot (carros com
// referência do iRacing).
//
// uso (de REPOS/gt3-godot/tools): npx vite-node paridade.ts               todos os carros + GT3 base
//                                 npx vite-node paridade.ts -- corvette-c6r-gt3 gt3-generic
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Vector3 } from 'three';
import { Car, CarInput, CarParams, PHYSICS_HZ } from '../../gt3-time-attack/src/physics/car';
import { FlatGround } from '../../gt3-time-attack/src/physics/ground';
import { CARS, carParams, modelMeta } from '../../gt3-time-attack/src/cars';
import { Track, TrackData } from '../../gt3-time-attack/src/track/track';
import { Bot } from '../../gt3-time-attack/src/track/bot';
import { RefBot } from '../../gt3-time-attack/src/track/refBot';
import { refAt, Reference } from '../../gt3-time-attack/src/track/reference';

const WEB = new URL('../../gt3-time-attack/', import.meta.url);
const web = (p: string) => fileURLToPath(new URL(p, WEB));
const OUT = fileURLToPath(new URL('../data/tests/paridade-web.json', import.meta.url));

const DT = 1 / PHYSICS_HZ;
const flat = new FlatGround();
const track = new Track(JSON.parse(readFileSync(web('data/tracks/interlagos.json'), 'utf8')) as TrackData);
const inp = (o: Partial<CarInput> = {}): CarInput => ({ steer: 0, throttle: 0, brake: 0, shiftUp: false, shiftDown: false, ...o });
// referência do iRacing de cada carro que tem uma (a mesma do tune-physics)
const REFS: Record<string, string> = {
  'audi-r8-lms-gt3': 'interlagos-r8'
};

function newCar(p: CarParams): Car {
  const car = new Car(p);
  car.reset(new Vector3(0, p.cgHeight, 0), 0);
  for (let i = 0; i < PHYSICS_HZ; i++) car.step(DT, inp(), flat); // assenta na suspensão
  return car;
}

function accelerateTo(car: Car, target: number, maxT = 60): number {
  car.assists.autoGearbox = true;
  let t = 0;
  while (car.forwardSpeed < target && t < maxT) {
    car.step(DT, inp({ throttle: 1 }), flat);
    t += DT;
  }
  return t;
}

function maxLateralG(p: CarParams, v: number): number {
  const car = newCar(p);
  accelerateTo(car, v);
  car.assists.autoGearbox = true;
  let best = 0;
  const T = 12;
  const fwd = new Vector3();
  for (let t = 0; t < T; t += DT) {
    const err = v - car.forwardSpeed;
    car.step(DT, inp({ throttle: Math.max(0, Math.min(1, err * 0.5 + 0.3)), steer: (t / T) * 0.7 }), flat);
    car.body.dirToWorld(fwd.set(0, 0, -1), fwd);
    const beta = Math.acos(Math.min(1, car.body.vel.dot(fwd) / Math.max(car.speed, 1e-3)));
    if (beta > 0.15) break;
    best = Math.max(best, Math.abs(car.gLat));
  }
  return best;
}

// ---- envelope (scripts/envelope.ts)
function rolling(p: CarParams, v: number): Car {
  const car = new Car(p);
  car.assists.autoGearbox = true;
  car.reset(new Vector3(0, p.cgHeight, 0), 0);
  for (let i = 0; i < PHYSICS_HZ / 2; i++) car.step(DT, inp(), flat);
  car.body.vel.set(0, 0, -v);
  for (const w of car.wheels) w.omega = v / p.wheelRadius;
  const G = p.gearbox;
  car.gear = 1;
  for (let g = G.ratios.length; g >= 1; g--) {
    const rpm = ((v / p.wheelRadius) * G.ratios[g - 1] * G.final * 60) / (2 * Math.PI);
    if (rpm > 5000) { car.gear = g; break; }
  }
  return car;
}

function lateral(p: CarParams, v: number): { g: number; end: string } {
  const car = rolling(p, v);
  let best = 0;
  let end = 'segurou';
  const T = 10;
  const fwd = new Vector3();
  const gs: number[] = [];
  for (let t = 0; t < T; t += DT) {
    const err = v - car.forwardSpeed;
    car.step(DT, inp({ throttle: Math.max(0, Math.min(1, err * 0.6 + 0.35)), steer: (t / T) * 0.6 }), flat);
    car.body.dirToWorld(fwd.set(0, 0, -1), fwd);
    const beta = Math.acos(Math.min(1, car.body.vel.dot(fwd) / Math.max(car.speed, 1e-3)));
    if (beta > 0.12) { end = 'traseira escapa'; break; }
    if (car.forwardSpeed < v * 0.9) { end = 'sai de frente'; break; }
    gs.push(Math.abs(car.gLat));
    if (gs.length > 150) gs.shift();
    if (gs.length === 150) best = Math.max(best, gs.reduce((a, b) => a + b) / 150);
  }
  return { g: best, end };
}

function brakeCurve(p: CarParams): Record<string, number> {
  const car = rolling(p, 75);
  const out: Record<string, number> = {};
  let last = car.forwardSpeed;
  let acc = 0, n = 0, bin = Math.floor((last * 3.6) / 20);
  for (let t = 0; t < 10 && car.forwardSpeed > 15; t += DT) {
    car.step(DT, inp({ brake: 1 }), flat);
    const v = car.forwardSpeed;
    acc += (last - v) / DT; n++;
    last = v;
    const b = Math.floor((v * 3.6) / 20);
    if (b !== bin) { if (t > 0.3 && bin * 20 >= 80) out[bin * 20] = acc / n / 9.81; acc = 0; n = 0; bin = b; }
  }
  return out;
}

function accelCurve(p: CarParams): { curve: Record<string, number>; v40: number } {
  const car = rolling(p, 20);
  const out: Record<string, number> = {};
  let last = car.forwardSpeed;
  let acc = 0, n = 0, bin = Math.floor((last * 3.6) / 20);
  for (let t = 0; t < 40; t += DT) {
    car.step(DT, inp({ throttle: 1 }), flat);
    const v = car.forwardSpeed;
    acc += (v - last) / DT; n++;
    last = v;
    const b = Math.floor((v * 3.6) / 20);
    if (b !== bin) { if (bin * 20 >= 100) out[bin * 20] = acc / n / 9.81; acc = 0; n = 0; bin = b; }
  }
  return { curve: out, v40: car.forwardSpeed * 3.6 };
}

// ---- voltas
function botLap(p: CarParams): { lap: number; maxOff: number } {
  const car = new Car(p);
  car.assists.autoGearbox = true;
  const start = track.poseAt(-40);
  car.reset(start.pos.clone().add(new Vector3(0, p.cgHeight + 0.05, 0)), start.heading);
  const bot = new Bot(track, car);
  let t = 0, lapStart = -1, lap = NaN, maxOff = 0;
  let lastS = track.locate(car.body.pos)!.s;
  while (t < 300) {
    const i = bot.drive();
    car.step(DT, i, track);
    t += DT;
    const loc = track.locate(car.body.pos);
    if (!loc) break;
    maxOff = Math.max(maxOff, Math.abs(loc.d) - (loc.d < 0 ? loc.wl : loc.wr));
    if (lastS > track.length - 100 && loc.s < 100) {
      if (lapStart >= 0) { lap = t - lapStart; break; }
      lapStart = t;
    }
    lastS = loc.s;
  }
  return { lap, maxOff };
}

function refLap(p: CarParams, refName: string): { lap: number; maxErr: number; offTrack: number; vmax: number } {
  const ref = JSON.parse(readFileSync(web(`data/reference/${refName}.json`), 'utf8')) as Reference;
  const car = new Car(p);
  car.assists.autoGearbox = true;
  const bot = new RefBot(track, car, ref);
  const s0 = track.length - 300;
  const p0 = bot.linePoint(s0, new Vector3());
  const p1 = bot.linePoint(s0 + 4, new Vector3());
  car.reset(p0.clone().setY(track.locate(p0)!.center.y + p.cgHeight + 0.02), Math.atan2(-(p1.x - p0.x), -(p1.z - p0.z)));
  const v0 = refAt(ref, ref.v, s0);
  car.body.vel.set(p1.x - p0.x, 0, p1.z - p0.z).normalize().multiplyScalar(v0);
  car.gear = p.gearbox.ratios.length;
  for (const w of car.wheels) w.omega = v0 / p.wheelRadius;
  let t = 0, lastS = s0, lapStart = -1, crossed = 0, maxErr = 0, offTrack = 0, vmax = 0;
  while (t < 200) {
    car.step(DT, bot.drive(), track);
    t += DT;
    if (bot.s < lastS - track.length / 2) {
      crossed++;
      if (crossed === 1) lapStart = t;
      else break;
    }
    lastS = bot.s;
    if (crossed === 1) {
      maxErr = Math.max(maxErr, Math.abs(bot.lineError));
      vmax = Math.max(vmax, car.forwardSpeed * 3.6);
      const loc = track.locate(car.body.pos);
      if (loc && Math.abs(loc.d) > (loc.d > 0 ? loc.wr : loc.wl) + 1.5) offTrack += DT;
    }
    if (car.body.pos.y < -50) break;
  }
  return { lap: crossed >= 2 ? t - lapStart : NaN, maxErr, offTrack, vmax };
}

function measure(id: string, p: CarParams) {
  const t0 = performance.now();
  const r: Record<string, unknown> = {};
  {
    const car = newCar(p);
    const start = car.body.pos.clone();
    for (let i = 0; i < PHYSICS_HZ * 5; i++) car.step(DT, inp(), flat);
    r.parado_desliza = Math.hypot(car.body.pos.x - start.x, car.body.pos.z - start.z);
    r.parado_altura = car.body.pos.y;
  }
  r.t0_100 = accelerateTo(newCar(p), 100 / 3.6);
  {
    const car = newCar(p);
    accelerateTo(car, 200, 60);
    r.maxima = car.forwardSpeed * 3.6;
  }
  {
    const car = newCar(p);
    accelerateTo(car, 200 / 3.6);
    const start = car.body.pos.clone();
    const q0 = car.body.quat.clone();
    let t = 0;
    while (car.forwardSpeed > 0.5 && t < 20) {
      car.step(DT, inp({ brake: 1 }), flat);
      t += DT;
    }
    r.freada_200_0_m = car.body.pos.distanceTo(start);
    r.freada_200_0_s = t;
    r.freada_desvio = car.body.quat.angleTo(q0);
  }
  r.lateral_72 = maxLateralG(p, 20);
  r.lateral_216 = maxLateralG(p, 60);
  const env: Record<string, number> = {};
  const ends: Record<string, string> = {};
  for (const kmh of [70, 90, 110, 130, 150, 170, 190, 220]) {
    const L = lateral(p, kmh / 3.6);
    env[kmh] = L.g;
    ends[kmh] = L.end;
  }
  r.envelope_lateral = env;
  r.envelope_limite = ends;
  r.envelope_freada = brakeCurve(p);
  const ac = accelCurve(p);
  r.envelope_aceleracao = ac.curve;
  r.velocidade_40s = ac.v40;
  const b = botLap(p);
  r.bot_volta = b.lap;
  r.bot_saida_max = b.maxOff;
  if (REFS[id]) {
    const L = refLap(p, REFS[id]);
    r.refbot_ref = REFS[id];
    r.refbot_volta = L.lap;
    r.refbot_erro_max = L.maxErr;
    r.refbot_fora = L.offTrack;
    r.refbot_maxima = L.vmax;
  }
  console.log(`${id.padEnd(26)} 0–100 ${(r.t0_100 as number).toFixed(2)} s  máx ${(r.maxima as number).toFixed(1)}  ` +
    `200–0 ${(r.freada_200_0_m as number).toFixed(1)} m  lat ${(r.lateral_72 as number).toFixed(2)}/${(r.lateral_216 as number).toFixed(2)} g  ` +
    `bot ${b.lap.toFixed(2)} s${r.refbot_volta ? `  refbot ${(r.refbot_volta as number).toFixed(3)} s` : ''}  (${((performance.now() - t0) / 1000).toFixed(1)} s)`);
  return r;
}

const args = process.argv.slice(2).filter(a => a !== '--');
const base = JSON.parse(readFileSync(web('data/cars/gt3-generic.json'), 'utf8')) as CarParams;
const all: [string, CarParams][] = [['gt3-generic', base], ...CARS.map(e => [e.id, carParams(e, modelMeta(e.id))] as [string, CarParams])];
const pick = args.length ? all.filter(([id]) => args.includes(id)) : all;
let prev: { carros: Record<string, unknown> } = { carros: {} };
if (args.length) {
  try {
    prev = JSON.parse(readFileSync(OUT, 'utf8'));
  } catch { /* primeiro uso */ }
}
for (const [id, p] of pick) prev.carros[id] = { params: p, web: measure(id, p) };
mkdirSync(fileURLToPath(new URL('../data/tests/', import.meta.url)), { recursive: true });
writeFileSync(OUT, JSON.stringify({ gerado: new Date().toISOString(), carros: prev.carros }, null, 1));
console.log('gravado', OUT);
