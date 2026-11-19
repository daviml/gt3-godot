"""
Polimento dos modelos 3D GT3 (.glb) via Blender headless:
1. Separa materiais únicos de luzes frente+trás em HEADLIGHT_<id> (Z < mid_z) e BRAKELIGHT_<id> (Z >= mid_z).
2. Aplica Decimate (COLLAPSE) limpo nos carros acima de 100k triângulos base para melhorar FPS mobile.

Uso:
  blender --background --python tools/car_polish.py -- --inspect acura-nsx-gt3
  blender --background --python tools/car_polish.py -- --apply mclaren-720s-gt3
  blender --background --python tools/car_polish.py -- --all
"""
import json
import os
import sys
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Materiais de luz que cobrem frente e trás no mesmo material
SPLIT_LIGHT_MATS = {
    "bmw-m4-gt3": ["BMWMAT_Lights1"],
    "ferrari-488-gt3": ["LIGHTS"],
    "audi-r8-lms-gt3": ["rAudi_R8LMSGT3_2019LightA_Material1"],
    "lamborghini-huracan-gt3": ["Lamborghini_HuracanGT3Evo2_2024LightA_Material"],
    "mclaren-720s-gt3": ["McLaren_720SGT3_2019LightA_Material"],
    "nissan-gtr-gt3": ["NNissan_GTRNISMOGT3_2015LightA_Material1"],
    "bentley-continental-gt3-2020": ["2020_bentley_gt3_lights.etc.png"],
    "lamborghini-gallardo-gt3": ["gt3Vehicle_Exterior_mm_lights1", "light_glass"],
    "aston-v12-vantage-gt3": ["Vehicle_Exterior_mm_lights"],
}

HIGH_POLY_THRESHOLD = 100000
TARGET_BASE_TRIS = 78000


def parse_args():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    mode = "inspect"
    targets = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--inspect":
            mode = "inspect"
            if i + 1 < len(argv):
                targets.append(argv[i + 1])
                i += 1
        elif a == "--apply":
            mode = "apply"
            if i + 1 < len(argv):
                targets.append(argv[i + 1])
                i += 1
        elif a == "--all":
            mode = "apply"
            with open(os.path.join(ROOT, "data", "cars.json"), "r", encoding="utf-8") as f:
                targets = [c["id"] for c in json.load(f)]
        i += 1
    return mode, targets


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load_car_meta(car_id: str) -> dict:
    p = os.path.join(ROOT, "data", "cars", f"{car_id}.json")
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)


def mid_z_of(meta: dict) -> float:
    mw = meta["model"]["wheels"]
    front_z = (float(mw[0]["z"]) + float(mw[1]["z"])) * 0.5
    rear_z = (float(mw[2]["z"]) + float(mw[3]["z"])) * 0.5
    return (front_z + rear_z) * 0.5


def glb_path_of(car_id: str) -> str:
    return os.path.join(ROOT, "assets", "cars", car_id, f"{car_id}.glb")


def count_tris(mesh) -> int:
    total = 0
    for p in mesh.polygons:
        n = len(p.vertices)
        if n >= 3:
            total += n - 2
    return total


def inspect_car(car_id: str):
    clear_scene()
    glb = glb_path_of(car_id)
    bpy.ops.import_scene.gltf(filepath=glb)
    meta = load_car_meta(car_id)
    mz = mid_z_of(meta)
    print(f"\n=== INSPECT {car_id} (mid_z={mz:.3f}) ===")
    mat_stats = {}
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        mesh = obj.data
        mw = obj.matrix_world
        for poly in mesh.polygons:
            mname = "<none>"
            if poly.material_index < len(mesh.materials) and mesh.materials[poly.material_index]:
                mname = mesh.materials[poly.material_index].name
            c_world = mw @ poly.center
            gltf_z = -c_world.y
            st = mat_stats.setdefault(mname, {"polys": 0, "zmin": 1e9, "zmax": -1e9, "objs": set()})
            st["polys"] += 1
            st["zmin"] = min(st["zmin"], gltf_z)
            st["zmax"] = max(st["zmax"], gltf_z)
            st["objs"].add(obj.name)
    for mname, st in sorted(mat_stats.items()):
        objs_str = ",".join(sorted(st["objs"]))[:40]
        print(f"  {mname:45s} polys={st['polys']:6d} gltf_z=[{st['zmin']:6.2f}..{st['zmax']:6.2f}] objs={objs_str}")


def split_material_by_z(mat_name: str, front_name: str, rear_name: str, z_split: float) -> tuple[int, int]:
    orig = bpy.data.materials.get(mat_name)
    if orig is None:
        return (0, 0)
    front_mat = bpy.data.materials.get(front_name) or orig.copy()
    front_mat.name = front_name
    rear_mat = bpy.data.materials.get(rear_name) or orig.copy()
    rear_mat.name = rear_name

    n_front = 0
    n_rear = 0
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        mesh = obj.data
        orig_idx = None
        for idx, m in enumerate(mesh.materials):
            if m == orig:
                orig_idx = idx
                break
        if orig_idx is None:
            continue

        # Garante slots para front_mat e rear_mat
        if front_mat.name not in [m.name for m in mesh.materials if m]:
            mesh.materials.append(front_mat)
        if rear_mat.name not in [m.name for m in mesh.materials if m]:
            mesh.materials.append(rear_mat)

        f_idx = next(i for i, m in enumerate(mesh.materials) if m == front_mat)
        r_idx = next(i for i, m in enumerate(mesh.materials) if m == rear_mat)

        mw = obj.matrix_world
        for poly in mesh.polygons:
            if poly.material_index == orig_idx:
                gltf_z = -(mw @ poly.center).y
                if gltf_z < z_split:
                    poly.material_index = f_idx
                    n_front += 1
                else:
                    poly.material_index = r_idx
                    n_rear += 1

    return (n_front, n_rear)


def polish_car(car_id: str):
    glb = glb_path_of(car_id)
    needs_split = car_id in SPLIT_LIGHT_MATS or car_id == "acura-nsx-gt3"
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=glb)
    meta = load_car_meta(car_id)
    mz = mid_z_of(meta)

    base_tris_before = sum(
        count_tris(obj.data)
        for obj in bpy.data.objects
        if obj.type == "MESH" and not obj.name.startswith("blur_")
    )
    needs_decimate = base_tris_before > HIGH_POLY_THRESHOLD

    if not needs_split and not needs_decimate:
        print(f"[SKIP] {car_id}: tris_base={base_tris_before} e luzes já separadas.")
        return

    print(f"\n=== POLISH {car_id} (tris_base={base_tris_before}, mid_z={mz:.3f}) ===")

    # 1. Separação de materiais de luzes
    if car_id == "acura-nsx-gt3":
        m5 = bpy.data.materials.get("Material.005")
        if m5:
            m5.name = "BRAKELIGHT_nsx"
            print("  [LUZ] Material.005 -> BRAKELIGHT_nsx")
        nf, nr = split_material_by_z("glasses_pivot_glass_light__0", "HEADLIGHT_nsx", "window_glass_nsx", -1.4)
        print(f"  [LUZ] glasses_pivot_glass_light__0 -> HEADLIGHT_nsx ({nf} polys) / window_glass_nsx ({nr} polys)")
    elif car_id in SPLIT_LIGHT_MATS:
        tag = car_id.replace("-", "_")
        for idx, mat_name in enumerate(SPLIT_LIGHT_MATS[car_id]):
            suf = f"_{idx}" if idx > 0 else ""
            fn = f"HEADLIGHT_{tag}{suf}"
            rn = f"BRAKELIGHT_{tag}{suf}"
            nf, nr = split_material_by_z(mat_name, fn, rn, mz)
            print(f"  [LUZ] {mat_name} -> {fn} ({nf} polys) / {rn} ({nr} polys)")

    # 2. Decimate limpo nos carros > 100k triângulos
    if needs_decimate:
        ratio = max(0.45, min(0.85, TARGET_BASE_TRIS / float(base_tris_before)))
        print(f"  [DECIMATE] ratio={ratio:.3f} (alvo ~{TARGET_BASE_TRIS} tris)")
        bpy.ops.object.select_all(action="DESELECT")
        for obj in bpy.data.objects:
            if obj.type != "MESH" or obj.name.startswith("blur_"):
                continue
            if len(obj.data.polygons) < 300:
                continue
            # Aplica modificador Decimate preservando UVs e geometria
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            mod = obj.modifiers.new(name="PolishDecimate", type="DECIMATE")
            mod.decimate_type = "COLLAPSE"
            mod.ratio = ratio
            mod.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=mod.name)
            obj.select_set(False)

    base_tris_after = sum(
        count_tris(obj.data)
        for obj in bpy.data.objects
        if obj.type == "MESH" and not obj.name.startswith("blur_")
    )
    print(f"  [RESULT] tris_base: {base_tris_before} -> {base_tris_after}")

    # 3. Exporta GLB sobrescrevendo o asset final
    bpy.ops.export_scene.gltf(
        filepath=glb,
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
        export_skins=False,
        export_animations=False,
    )
    print(f"  [SAVED] {glb}")


def main():
    mode, targets = parse_args()
    for cid in targets:
        if mode == "inspect":
            inspect_car(cid)
        elif mode == "apply":
            polish_car(cid)


if __name__ == "__main__":
    main()
