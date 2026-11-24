/**
 * Cores (albedo) das tintas de Interlagos: zebra, linha branca, faixa verde, salsicha e escapes pintados
 * (PLANO-INTERLAGOS-DETALHES.md, Fase 1 — "cor medida, não no olho").
 *
 * NÃO são as cores que se veem no vídeo. A luz de Interlagos no Godot (data/tracks.json → visual.luz: sol 3,4,
 * exposição 1,3, AgX, saturação 1,2) multiplica o albedo ~4× antes do tonemap: uma tinta clara e saturada usada direto
 * como albedo (ex.: o vermelho do LMU, 209/12/35) chega ao topo da curva do AgX e desbota (salmão 255/150/139; amarelo
 * vira creme, branco estoura). Por isso cada cor aqui é o albedo que, sob essa luz, dá na tela o sRGB medido no LMU.
 *
 * Como foram achadas (20/11/2026): tools/ref/calib_tinta.py renderiza retalhos com o material das tintas no chão da
 * pista (scripts/tests/calib_tinta.gd, câmera do --atlas, s 900/1650/3400) e faz Newton por tinta até a tela bater
 * com o alvo; depois uma passada de correção com as capturas reais (textura com desgaste), medidas por
 * tools/ref/cores.py. Alvo de cada uma (sRGB na tela, LMU) no comentário. Se a luz de Interlagos mudar, rodar de
 * novo: `python tools/ref/calib_tinta.py` e conferir com `tools/ref/cores.py`.
 */
export const TINTA = {
  amarelo: '#849c00', // zebra e salsicha — LMU 205/208/30
  verde: '#095710', // zebra — LMU 42/151/39
  branco: '#73959b', // zebra e faixas brancas do escape vermelho — LMU 180/198/202
  linha: '#8092a2', // linha branca da borda — LMU 194/202/210
  verdeVivo: '#006128', // escape verde e faixa verde logo atrás da zebra — LMU 48/172/100
  verdeAgua: '#173d2c', // escape verde-azulado (Reta Oposta) — LMU 55/126/102
  vermelho: '#670007', // escape vermelho (Reta Oposta) — LMU 209/12/35
  asfalto: '#3e4044' // asfalto sem tinta (Fase 5): pista dos boxes e escape road; a mesma cor da pista dos boxes do buildPitExit (não calibrada)
} as const;

/** Cor um pouco mais escura da mesma tinta (faixa de tom diferente perto da pista, nos escapes). */
export function tintaEscura(hex: string, f = 0.87): string {
  const n = parseInt(hex.slice(1), 16);
  const c = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map(v => Math.round(v * f));
  return '#' + c.map(v => v.toString(16).padStart(2, '0')).join('');
}
