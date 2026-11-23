# Fase 2B, etapa E: mapa de s DEFINITIVO entre a pista antiga e a nova, nas unidades dos track.json exportados
# (o s que o jogo usa: amostra i ↔ s = 2·i, ao longo da curva 3D).
#
#   antiga: build/interlagos/track_antigo.json  (data/track/track.json até a etapa E, exportado do web, 4.294 m)
#   nova:   data/track/track.json               (tools/pista.ts -- interlagos)
#   saída:  tools/tracks/interlagos/s_antigo_novo.json
#
# Para cada amostra antiga (a cada 2 m), o ponto (x, z) é projetado na polilinha nova (mesma conta do
# Track.locate do Godot: segmento mais próximo, projeção no plano): s_novo = (j + u)·2 e d = posição lateral do
# centro antigo em relação ao novo (m, > 0 à direita de quem corre). O mapa é forçado a ser monotônico.
# A etapa F usa isto para levar perfil visual, cenário, atlas e listas de transição do s antigo para o novo:
#   s_novo = interp(s_antigo, mapa.s_antigo, mapa.s_novo)   (periódico: comprimentoAntigo → comprimentoNovo)
#
# uso (de REPOS/gt3-godot, depois do pista.ts): python tools/tracks/interlagos/mapa_s.py
import json
import os
import sys

import numpy as np

sys.stdout.reconfigure(encoding='utf-8')
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))


def le(p):
    t = json.load(open(p, encoding='utf-8'))
    A = np.array(t['s'], float).reshape(t['n'], t['stride'])
    return t, A


t0, A0 = le(os.path.join(ROOT, 'build', 'interlagos', 'track_antigo.json'))
t1, A1 = le(os.path.join(ROOT, 'data', 'track', 'track.json'))
if t1['n'] == t0['n'] and np.allclose(A0[:, :3], A1[:, :3]):
    raise SystemExit('data/track/track.json ainda é a pista antiga: rode antes `npx vite-node pista.ts -- interlagos`')
P0, P1 = A0[:, [0, 2]], A1[:, [0, 2]]
n1 = len(P1)
L0, L1 = 2.0 * len(P0), 2.0 * n1
seg = np.roll(P1, -1, 0) - P1
sl2 = (seg ** 2).sum(1)
R1 = A1[:, [6, 7]] / np.linalg.norm(A1[:, [6, 7]], axis=1)[:, None]

# segmento mais próximo (busca completa vetorizada em blocos: 2.147 × 2.154)
s_new = np.zeros(len(P0))
d_new = np.zeros(len(P0))
dist = np.zeros(len(P0))
for a in range(0, len(P0), 256):
    Q = P0[a:a + 256]
    rel = Q[:, None, :] - P1[None, :, :]
    u = np.clip((rel * seg[None]).sum(2) / sl2[None], 0.0, 1.0)
    f = P1[None] + seg[None] * u[..., None]
    dd = np.linalg.norm(Q[:, None, :] - f, axis=2)
    j = dd.argmin(1)
    k = np.arange(len(Q))
    uj = u[k, j]
    s_new[a:a + 256] = (j + uj) * 2.0
    c = f[k, j]
    r = R1[j] * (1 - uj)[:, None] + R1[(j + 1) % n1] * uj[:, None]
    r /= np.linalg.norm(r, axis=1)[:, None]
    d_new[a:a + 256] = ((Q - c) * r).sum(1)
    dist[a:a + 256] = dd[k, j]

s_old = np.arange(len(P0)) * 2.0
# desenrola (começa perto de 0) e força monotonia
s_un = np.unwrap(s_new * 2 * np.pi / L1) * L1 / (2 * np.pi)
s_un -= np.round(s_un[0] / L1) * L1
if s_un[-1] < s_un[0]:
    raise SystemExit('sentido invertido')
plat = int(np.sum(np.diff(s_un) <= 0))
s_mono = np.maximum.accumulate(s_un)
k = L1 / L0
dif = s_mono - s_old
dif_k = s_mono - s_old * k
st = {
    'comprimentoAntigo': L0, 'comprimentoNovo': L1, 'escala': round(k, 6),
    's0_novo_da_amostra_antiga_0': round(float(s_mono[0]), 2),
    'max_abs_s_novo_menos_s_antigo': round(float(np.abs(dif).max()), 2),
    'onde_s_antigo': float(s_old[np.abs(dif).argmax()]),
    'max_abs_menos_escala': round(float(np.abs(dif_k).max()), 2),
    'onde_escala_s_antigo': float(s_old[np.abs(dif_k).argmax()]),
    'lateral_mediana_abs': round(float(np.median(np.abs(d_new))), 2),
    'lateral_p95_abs': round(float(np.percentile(np.abs(d_new), 95)), 2),
    'lateral_max_abs': round(float(np.abs(d_new).max()), 2),
    'onde_lateral_s_antigo': float(s_old[np.abs(d_new).argmax()]),
    'passo_novo_por_2m_antigo': [round(float(np.diff(s_mono).min()), 3), round(float(np.diff(s_mono).max()), 3)],
    'nao_monotonicos_corrigidos': plat,
}
out = {
    'descricao': 's do track.json ANTIGO (build/interlagos/track_antigo.json, amostra i, s = 2·i, 4.294 m) → s do '
                 'track.json NOVO (data/track/track.json, s = 2·i do Track, 4.308 m), pela projeção do ponto antigo '
                 'na polilinha nova (como Track.locate). d = posição lateral do centro antigo em relação ao novo (m, '
                 '> 0 à direita de quem corre): um objeto a lateral `l` da linha antiga fica a `l + d` da nova. '
                 'Monotônico; periódico (s_antigo + comprimentoAntigo ↔ s_novo + comprimentoNovo). Gerado por mapa_s.py.',
    'passoAntigo': 2, 'n': len(P0), 'comprimentoAntigo': L0, 'comprimentoNovo': L1,
    'estatisticas': st,
    's_antigo': [round(float(x), 1) for x in s_old],
    's_novo': [round(float(x), 2) for x in s_mono],
    'd': [round(float(x), 2) for x in d_new],
}
json.dump(out, open(os.path.join(HERE, 's_antigo_novo.json'), 'w', encoding='utf-8'), ensure_ascii=False)
print('mapa de s antigo → novo:', json.dumps(st, ensure_ascii=False))
