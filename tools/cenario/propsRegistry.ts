import * as THREE from 'three';

/**
 * Registro de hero props modulares (assets/props/*.glb) para o cenario.mjs exportar
 * em data/track/props.json e o TrackView instanciar no Godot sem duplicar geometria no cenario.glb.
 * Formato de cada entrada: [id, x, y, z, rot_y, sx, sy, sz, essential]
 */
export type PropEntry = [string, number, number, number, number, number, number, number, number];

const _props: PropEntry[] = [];

export function clearProps(): void {
  _props.length = 0;
}

export function addProp(
  id: string,
  pos: THREE.Vector3,
  rotY: number,
  scale: THREE.Vector3 | number = 1,
  essential = false
): void {
  const s = typeof scale === 'number' ? new THREE.Vector3(scale, scale, scale) : scale;
  const r = (v: number) => Math.round(v * 1000) / 1000;
  _props.push([id, r(pos.x), r(pos.y), r(pos.z), r(rotY), r(s.x), r(s.y), r(s.z), essential ? 1 : 0]);
}

export function getProps(): PropEntry[] {
  return _props.slice();
}
