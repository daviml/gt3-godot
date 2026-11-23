/**
 * Fase 2B, etapa F: leva o perfil lateral (data/track/visual_profile.json) da pista ANTIGA (web, 4.294 m, 2.147
 * amostras) para a pista NOVA (data/track/track.json, 4.308 m, 2.154 amostras), pelo mapa de s
 * (tools/tracks/interlagos/s_antigo_novo.json, ./sNovo.ts). Não use `cenario.mjs --extrair-perfil` (reconstruía a v1
 * antiga a partir do código e apagava as edições).
 *
 * Entrada (congelada, para a migração poder ser refeita igual):
 *   build/interlagos/visual_profile_antigo.json   o perfil v1 da Fase 2 (cópia do data/track/visual_profile.json
 *                                                 antes desta etapa; se faltar e o atual ainda for o antigo, copia)
 *   build/interlagos/track_antigo.json            a física antiga (wl/wr, zebra, escape, muro por amostra)
 *   data/track/track.json                         a física nova
 * Saída: data/track/visual_profile.json (v2) e build/interlagos/perfil_2b/relatorio.json (+ .md)
 *
 * Como cada coisa é levada (amostra nova j ← amostra antiga mais próxima de sAntigo(2j); o perfil antigo é avaliado
 * na física antiga, ./perfil.ts → avaliarPerfil, e reescrito na nova):
 *   - fatias: as mesmas, com s0/s1 levados pelo mapa (sNovo, arredondado à amostra); vizinhas que ficam iguais
 *     depois da troca abaixo (ex.: só diferiam em `listrada`/`visual`) são juntadas.
 *   - zebra: a física nova já é a tabela de zebras da Fase 2 (perfil_zebras.ZEBRAS, aplicada por build_track.py),
 *     então a faixa vira `{ tipo: "zebra", larg: "fisica" }` sem `listrada`/`visual`/`minimo`: visual = física.
 *     O relatório lista onde a zebra listrada antiga (avaliada) e a física nova divergem.
 *   - pintura verde e salsicha: mesmas larguras.
 *   - escape: constante → mantém a borda de fora do escape no mesmo lugar em relação à linha branca (zebra + escape
 *     antigos − zebra nova); "fisica" → "fisica"; listas (transições) → reamostradas pela regra da constante.
 *   - barreira: tipo, placas e alambrado iguais; distância = a do muro da física nova (`dist: "fisica"`). Critério
 *     (pedido do Davi): o carro não pode atravessar um muro visual nem bater num muro invisível; na física o muro
 *     é um limite lateral (scripts/track/track.gd), e o muro da física nova é medido (OSM > satélite > perfil antigo
 *     levado pelo mapa, build_track.py), então o desenho segue a física. O relatório mostra quanto o muro do perfil
 *     antigo (levado ao mesmo lugar físico) difere do da física nova, fatia a fatia.
 *   - escape nunca passa da barreira (o fim dele fica ≤ muro − borda − zebra).
 *
 * uso (de REPOS/gt3-godot/tools): npx vite-node cenario/interlagos/migrarPerfil2B.ts [-- --seco]
 */
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { avaliarPerfil, type AmostraLado, type Barreira, type Faixa, type Fatia, type Perfil } from './perfil';
import { dNovo, sAntigo, sNovo } from './sNovo';

const ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const P = (p: string) => resolve(ROOT, p);
const seco = process.argv.includes('--seco');

// ---------------------------------------------------------------- entradas
const ANTIGO = P('build/interlagos/visual_profile_antigo.json');
if (!existsSync(ANTIGO)) {
  const atual = JSON.parse(readFileSync(P('data/track/visual_profile.json'), 'utf8')) as Perfil;
  if (atual.n !== 2147) throw new Error('falta build/interlagos/visual_profile_antigo.json e o perfil atual já não é o antigo');
  mkdirSync(P('build/interlagos'), { recursive: true });
  copyFileSync(P('data/track/visual_profile.json'), ANTIGO);
}
const perfilA = JSON.parse(readFileSync(ANTIGO, 'utf8')) as Perfil;

interface Fis { n: number; length: number; wl: number[]; wr: number[]; kerbL: number[]; kerbR: number[]; runL: number[]; runR: number[]; wallL: number[]; wallR: number[] }
function leTrack(f: string): Fis {
  const t = JSON.parse(readFileSync(P(f), 'utf8'));
  const col = (k: number) => Array.from({ length: t.n }, (_, i) => t.s[i * t.stride + k] as number);
  return { n: t.n, length: t.length, wl: col(8), wr: col(9), kerbL: col(10), kerbR: col(11), runL: col(12), runR: col(13), wallL: col(14), wallR: col(15) };
}
const FA = leTrack('build/interlagos/track_antigo.json');
const FN = leTrack('data/track/track.json');
if (perfilA.n !== FA.n) throw new Error(`perfil antigo com ${perfilA.n} amostras, física antiga com ${FA.n}`);
const PASSO = 2;
const NN = FN.n;
const NA = FA.n;

// perfil antigo avaliado na física antiga (o que o gerador desenhava até a etapa E)
const trackA = {
  length: FA.length,
  samples: Array.from({ length: NA }, (_, i) => ({ wl: FA.wl[i], wr: FA.wr[i], kerbL: FA.kerbL[i], kerbR: FA.kerbR[i], runL: FA.runL[i], runR: FA.runR[i], wallL: FA.wallL[i], wallR: FA.wallR[i] }))
};
const avA = avaliarPerfil(trackA as never, perfilA);

/** largura visual da zebra listrada (igual a trackView.ts: larguraZebra/kerbVisual) */
function zebraVisual(a: AmostraLado): number {
  if (!a.listrada || a.kerb <= 0 && !a.zebraVisual) return 0;
  if (a.zebraVisual === 'normal') return 1.0;
  if (a.zebraVisual === 'saida') return 1.6;
  const t = Math.max(0, Math.min(1, (a.kerb - 1.2) / (2.2 - 1.2)));
  return a.kerb > 0 ? 1.0 + 0.6 * t : 0;
}
const kerbVisualFis = (k: number) => (k <= 0 ? 0 : 1.0 + 0.6 * Math.max(0, Math.min(1, (k - 1.2) / 1.0)));

// fatia antiga de cada amostra antiga, por lado
const fatiaDe = (lado: Fatia[]) => {
  const out = new Int32Array(NA);
  lado.forEach((f, k) => { for (let i = Math.round(f.s0 / PASSO); i <= Math.round(f.s1 / PASSO); i++) out[i] = k; });
  return out;
};

const r3 = (x: number) => Math.round(x * 1000) / 1000;
const r2 = (x: number) => Math.round(x * 100) / 100;

interface Rel {
  fatias: { esq: [number, number]; dir: [number, number] };
  muro: Record<string, unknown>;
  zebras: Record<string, unknown>;
  escape: Record<string, unknown>;
}
const rel: Rel = { fatias: { esq: [0, 0], dir: [0, 0] }, muro: {}, zebras: {}, escape: {} };
const md: string[] = ['# Perfil lateral: pista antiga → nova (Fase 2B, etapa F)', '', 'Gerado por `tools/cenario/interlagos/migrarPerfil2B.ts`.', ''];

function migraLado(nome: 'esq' | 'dir'): Fatia[] {
  const esq = nome === 'esq';
  const fatiasA = perfilA.lados[nome];
  const ofA = fatiaDe(fatiasA);
  const AV = esq ? avA.L : avA.R;
  const wA = esq ? FA.wl : FA.wr;
  const wN = esq ? FN.wl : FN.wr;
  const kN = esq ? FN.kerbL : FN.kerbR;
  const runN = esq ? FN.runL : FN.runR;
  const wallN = esq ? FN.wallL : FN.wallR;

  // amostra antiga de cada amostra nova + lateral do centro antigo
  const io = new Int32Array(NN);
  const dd = new Float64Array(NN);
  for (let j = 0; j < NN; j++) {
    const sa = sAntigo(j * PASSO);
    io[j] = Math.round(sa / PASSO) % NA;
    dd[j] = dNovo(sa);
  }

  // ---- muro: perfil antigo no mesmo lugar físico × física nova (só relatório; o desenho segue a física)
  const muroFis = new Float64Array(NN);
  const muroBorda = new Float64Array(NN);
  for (let j = 0; j < NN; j++) {
    const a = AV[io[j]];
    // lateral do muro antigo (do centro antigo) levada ao centro novo: esq −wall + d → wall − d; dir wall + d
    muroFis[j] = (esq ? a.wall - dd[j] : a.wall + dd[j]) - wallN[j];
    muroBorda[j] = wN[j] + (a.wall - wA[io[j]]) - wallN[j];
  }

  // ---- zebras: listrada antiga (avaliada) × física nova
  const zA = Array.from({ length: NN }, (_, j) => zebraVisual(AV[io[j]]));
  const zN = Array.from({ length: NN }, (_, j) => kerbVisualFis(kN[j]));
  const trechos = (pred: (j: number) => boolean) => {
    const out: [number, number][] = [];
    let a = -1;
    for (let j = 0; j <= NN; j++) {
      const on = j < NN && pred(j);
      if (on && a < 0) a = j;
      if (!on && a >= 0) { out.push([a * PASSO, (j - 1) * PASSO]); a = -1; }
    }
    return out;
  };
  const soAntiga = trechos(j => zA[j] > 0 && zN[j] === 0);
  const soNova = trechos(j => zA[j] === 0 && zN[j] > 0);
  const largDif = trechos(j => zA[j] > 0 && zN[j] > 0 && Math.abs(zA[j] - zN[j]) > 0.15);
  rel.zebras[nome] = {
    listrada_antiga_m: zA.filter(x => x > 0).length * PASSO, fisica_nova_m: zN.filter(x => x > 0).length * PASSO,
    so_na_antiga: soAntiga.map(([a, b]) => ({ s0: a, s1: b, s0_antigo: r2(sAntigo(a)), s1_antigo: r2(sAntigo(b)) })),
    so_na_fisica_nova: soNova.map(([a, b]) => ({ s0: a, s1: b, s0_antigo: r2(sAntigo(a)), s1_antigo: r2(sAntigo(b)) })),
    largura_visual_diferente: largDif.map(([a, b]) => {
      const js = Array.from({ length: (b - a) / PASSO + 1 }, (_, k) => a / PASSO + k);
      return { s0: a, s1: b, antiga: r2(Math.max(...js.map(j => zA[j]))), nova: r2(Math.max(...js.map(j => zN[j]))) };
    })
  };

  // ---- reescreve as fatias
  type Desc = { faixas: Faixa[]; barreira: Barreira; run: number | 'fisica' | null; escCor: string | null };
  const desc: Desc[] = [];
  const corrEsc: number[] = [];
  for (let j = 0; j < NN; j++) {
    const i = io[j];
    const fa = fatiasA[ofA[i]];
    const a = AV[i];
    const faixas: Faixa[] = [];
    if (kN[j] > 0 || fa.faixas.some(x => x.tipo === 'zebra')) faixas.push({ tipo: 'zebra', larg: 'fisica' });
    const pint = fa.faixas.find(x => x.tipo === 'pintura') as Extract<Faixa, { tipo: 'pintura' }> | undefined;
    const sal = fa.faixas.find(x => x.tipo === 'salsicha') as Extract<Faixa, { tipo: 'salsicha' }> | undefined;
    const esc = fa.faixas.find(x => x.tipo === 'escape') as Extract<Faixa, { tipo: 'escape' }> | undefined;
    if (pint) faixas.push({ ...pint });
    if (sal) faixas.push({ ...sal });
    let run: number | 'fisica' | null = null;
    if (esc) {
      if (esc.larg === 'fisica') run = 'fisica';
      else {
        // fim do escape a partir da linha branca: zebra + escape antigos; na nova, menos a zebra nova
        const fim = a.kerb + a.run;
        const kn = kN[j];
        // não passa do muro novo (fim do escape ≤ muro − borda)
        const lim = Math.max(0, wallN[j] - wN[j] - kn);
        const r = Math.max(0, fim - kn);
        run = Math.min(r, lim);
        if (r - lim > 0.01) corrEsc.push(j);
      }
    }
    const b: Barreira = { tipo: fa.barreira.tipo, dist: 'fisica' };
    if (fa.barreira.banner) b.banner = fa.barreira.banner;
    if (fa.barreira.alambrado) b.alambrado = true;
    desc.push({ faixas, barreira: b, run, escCor: esc?.cor ?? null });
  }
  rel.escape[nome] = { amostras_cortadas_no_muro: corrEsc.length, trechos: trechos(j => corrEsc.includes(j)) };

  // fronteiras: as das fatias antigas (levadas pelo mapa) + onde o descritor (sem o valor do escape) muda
  const chave = (d: Desc) => JSON.stringify([d.faixas, d.barreira, d.escCor, d.run === 'fisica' ? 'f' : d.run === null ? 'n' : 'v']);
  const inicio = new Set<number>([0]);
  for (const f of fatiasA) inicio.add(Math.round(sNovo(f.s0) / PASSO) % NN);
  for (let j = 1; j < NN; j++) if (chave(desc[j]) !== chave(desc[j - 1])) inicio.add(j);
  const starts = [...inicio].sort((x, y) => x - y);
  const out: Fatia[] = [];
  for (let k = 0; k < starts.length; k++) {
    const j0 = starts[k];
    const j1 = (k + 1 < starts.length ? starts[k + 1] : NN) - 1;
    const d = desc[j0];
    const faixas: Faixa[] = d.faixas.map(x => ({ ...x }));
    if (d.escCor) {
      let larg: number | 'fisica' | number[];
      if (d.run === 'fisica') larg = 'fisica';
      else {
        const vals = Array.from({ length: j1 - j0 + 1 }, (_, m) => r3(desc[j0 + m].run as number));
        larg = vals.every(v => Math.abs(v - vals[0]) < 0.0015) ? vals[0] : vals;
      }
      // escape vai depois de pintura/salsicha (ordem da linha branca para fora)
      faixas.push({ tipo: 'escape', cor: d.escCor as 'verde', larg });
    }
    const f: Fatia = { s0: j0 * PASSO, s1: j1 * PASSO, faixas, barreira: { ...d.barreira } };
    const prev = out[out.length - 1];
    // junta com a anterior se ficou igual (constantes iguais)
    if (prev && JSON.stringify([prev.faixas, prev.barreira]) === JSON.stringify([f.faixas, f.barreira])) prev.s1 = f.s1;
    else out.push(f);
  }
  rel.fatias[nome] = [fatiasA.length, out.length];

  // relatório do muro por fatia antiga
  const linhas: unknown[] = [];
  fatiasA.forEach((f, k) => {
    const js: number[] = [];
    for (let j = 0; j < NN; j++) if (ofA[io[j]] === k) js.push(j);
    if (!js.length) return;
    const v = js.map(j => muroFis[j]);
    const vb = js.map(j => muroBorda[j]);
    const mn = Math.min(...v), mx = Math.max(...v);
    linhas.push({
      s0_antigo: f.s0, s1_antigo: f.s1, s0: js[0] * PASSO, s1: js[js.length - 1] * PASSO, tipo: f.barreira.tipo,
      dist_antiga: Array.isArray(f.barreira.dist) ? 'lista' : f.barreira.dist, de: f.barreira.de ?? null,
      antigo_mesmo_lugar_menos_fisica: [r2(mn), r2(mx)],
      antigo_mesma_distancia_da_borda_menos_fisica: [r2(Math.min(...vb)), r2(Math.max(...vb))]
    });
  });
  const abs = Array.from(muroFis).map(Math.abs).sort((x, y) => x - y);
  const absB = Array.from(muroBorda).map(Math.abs).sort((x, y) => x - y);
  const q = (a: number[], p: number) => r2(a[Math.min(a.length - 1, Math.floor(a.length * p))]);
  rel.muro[nome] = {
    antigo_mesmo_lugar_menos_fisica_abs: { mediana: q(abs, 0.5), p90: q(abs, 0.9), max: q(abs, 1), acima_1m_m: abs.filter(x => x > 1).length * PASSO },
    antigo_mesma_distancia_da_borda_menos_fisica_abs: { mediana: q(absB, 0.5), p90: q(absB, 0.9), max: q(absB, 1), acima_1m_m: absB.filter(x => x > 1).length * PASSO },
    antigo_mais_perto_que_fisica_mais_de_0_5m_m: Array.from(muroFis).filter(x => x < -0.5).length * PASSO,
    antigo_mais_longe_que_fisica_mais_de_0_5m_m: Array.from(muroFis).filter(x => x > 0.5).length * PASSO,
    por_fatia: linhas
  };
  return out;
}

const esq = migraLado('esq');
const dir = migraLado('dir');
const novo: Perfil = { versao: 2, pista: 'interlagos', passo: PASSO, comprimento: FN.length, n: NN, lados: { esq, dir } };
(novo as unknown as Record<string, unknown>).origem =
  'Fase 2B etapa F: v1 da Fase 2 (pista antiga, 4.294 m) levada para a pista nova por tools/cenario/interlagos/migrarPerfil2B.ts ' +
  '(mapa tools/tracks/interlagos/s_antigo_novo.json); zebras = física; barreiras na distância do muro da física.';

// conferência: o carregador aceita (cobertura sem buraco, n e comprimento)
const fake = { length: FN.length, samples: Array.from({ length: NN }, (_, i) => ({ wl: FN.wl[i], wr: FN.wr[i], kerbL: FN.kerbL[i], kerbR: FN.kerbR[i], runL: FN.runL[i], runR: FN.runR[i], wallL: FN.wallL[i], wallR: FN.wallR[i] })) };
const avN = avaliarPerfil(fake as never, novo);
// nenhum escape além do muro, muro = física
let ruins = 0;
for (const [L, lado] of [[avN.L, 'L'], [avN.R, 'R']] as const)
  L.forEach((a, i) => {
    const w = lado === 'L' ? FN.wl[i] : FN.wr[i];
    const wall = lado === 'L' ? FN.wallL[i] : FN.wallR[i];
    if (Math.abs(a.wall - wall) > 1e-6 || w + a.kerb + a.run > wall + 0.011) ruins++;
  });
if (ruins) throw new Error(`${ruins} amostras com muro ≠ física ou escape além do muro`);

console.log('fatias esq', rel.fatias.esq, 'dir', rel.fatias.dir);
console.log('muro (perfil antigo no mesmo lugar físico − física nova):', JSON.stringify({ esq: (rel.muro.esq as any).antigo_mesmo_lugar_menos_fisica_abs, dir: (rel.muro.dir as any).antigo_mesmo_lugar_menos_fisica_abs }));
console.log('muro (perfil antigo na mesma distância da borda − física nova):', JSON.stringify({ esq: (rel.muro.esq as any).antigo_mesma_distancia_da_borda_menos_fisica_abs, dir: (rel.muro.dir as any).antigo_mesma_distancia_da_borda_menos_fisica_abs }));
console.log('zebras:', JSON.stringify(rel.zebras));
console.log('escape cortado no muro:', JSON.stringify(rel.escape));

mkdirSync(P('build/interlagos/perfil_2b'), { recursive: true });
writeFileSync(P('build/interlagos/perfil_2b/relatorio.json'), JSON.stringify(rel, null, 1));
if (!seco) {
  // mesmo formato do v1: uma fatia por linha (listas longas na mesma linha)
  const txt = JSON.stringify(novo, null, 1).replace(/\[\s+([-0-9.,\s]+?)\s+\]/g, (_, x) => `[${x.replace(/\s+/g, '')}]`);
  writeFileSync(P('data/track/visual_profile.json'), txt + '\n');
  console.log('data/track/visual_profile.json gravado (v2,', NN, 'amostras)');
}
