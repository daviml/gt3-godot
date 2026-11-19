"""
Gera hero props modulares low-poly em Blender headless para o gt3-godot:
  - assets/props/marshal_post.glb
  - assets/props/crane.glb
  - assets/props/ambulance.glb
  - assets/props/gantry_tower.glb
  - assets/props/corkscrew_bridge.glb

Uso:
  "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe" --background --python tools/gen_hero_props.py
"""
import math
import os
import bpy
import bmesh
from mathutils import Vector, Matrix

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "assets", "props")


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_mat(name, color, roughness=0.6, metallic=0.0, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None and "Emission Color" in bsdf.inputs:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def add_box(name, size, loc, mat, rot=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier="Bevel")
    obj.data.materials.append(mat)
    return obj


def add_cyl(name, radius, depth, loc, mat, rot=(0.0, 0.0, 0.0), verts=10):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def add_beam(name, p0, p1, thickness, mat):
    v0 = Vector(p0)
    v1 = Vector(p1)
    diff = v1 - v0
    length = diff.length
    if length < 1e-4:
        return None
    mid = (v0 + v1) * 0.5
    quat = Vector((0, 0, 1)).rotation_difference(diff.normalized())
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=mid)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (thickness, thickness, length)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = quat
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.materials.append(mat)
    return obj


def export_glb(filename):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
    )
    tris = sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH")
    print(f"Exported {filename} ({tris} faces) -> {path}")


def build_marshal_post():
    clear_scene()
    concrete = make_mat("concrete", (0.55, 0.55, 0.53), roughness=0.9)
    white = make_mat("cabin_white", (0.92, 0.92, 0.90), roughness=0.65)
    orange = make_mat("roof_orange", (0.91, 0.42, 0.08), roughness=0.55)
    glass = make_mat("window_glass", (0.12, 0.22, 0.34), roughness=0.12, metallic=0.45)
    frame = make_mat("dark_frame", (0.15, 0.16, 0.18), roughness=0.5, metallic=0.4)
    steel = make_mat("steel", (0.68, 0.70, 0.72), roughness=0.4, metallic=0.7)
    flag_y = make_mat("flag_yellow", (0.95, 0.80, 0.02), roughness=0.75)
    beacon = make_mat("beacon_amber", (0.98, 0.55, 0.05), roughness=0.2, emission=(1.0, 0.5, 0.05), emission_strength=1.2)

    # Note: Blender Z is up; GLTF export_yup=True maps Blender (X, Y, Z) -> Godot (X, Z, -Y)
    # So front of cabin faces -Y in Blender (+Z in Godot)
    add_box("plinth", (2.5, 2.5, 0.25), (0, 0, 0.125), concrete)
    add_box("cabin", (2.1, 2.1, 2.15), (0, 0, 1.325), white, bevel=0.05)

    # Recessed window frames & glass on front (-Y) and sides (±X)
    add_box("win_front_frame", (1.65, 0.14, 0.88), (0, -1.03, 1.72), frame)
    add_box("win_front_glass", (1.52, 0.16, 0.74), (0, -1.03, 1.72), glass)
    add_box("win_sides_frame", (2.16, 1.45, 0.85), (0, 0.05, 1.72), frame)
    add_box("win_sides_glass", (2.18, 1.32, 0.72), (0, 0.05, 1.72), glass)

    # Rear door (+Y)
    add_box("door_frame", (0.88, 0.08, 1.85), (0, 1.04, 1.18), frame)
    add_box("door_panel", (0.76, 0.10, 1.75), (0, 1.04, 1.18), white)

    # Overhanging orange safety roof + trim + beacon
    add_box("roof", (2.75, 2.75, 0.18), (0, 0, 2.48), orange, bevel=0.03)
    add_box("roof_cap", (2.3, 2.3, 0.10), (0, 0, 2.60), orange)
    add_cyl("beacon", 0.11, 0.20, (-0.75, -0.75, 2.74), beacon, verts=8)

    # Flagpole & waved yellow marshal flag
    add_cyl("pole", 0.035, 2.4, (1.18, -1.05, 3.30), steel, verts=8)
    # Flag mesh (3 segments slightly curved)
    mesh = bpy.data.meshes.new("flag_mesh")
    bm = bmesh.new()
    pts = [
        (1.20, -1.05, 4.45), (1.52, -1.00, 4.42), (1.84, -1.08, 4.46), (2.14, -1.02, 4.43),
        (1.20, -1.05, 3.88), (1.52, -1.00, 3.86), (1.84, -1.08, 3.89), (2.14, -1.02, 3.87),
    ]
    vs = [bm.verts.new(p) for p in pts]
    for i in range(3):
        bm.faces.new((vs[i], vs[i + 1], vs[i + 5], vs[i + 4]))
    bm.to_mesh(mesh)
    bm.free()
    flag_obj = bpy.data.objects.new("marshal_flag", mesh)
    bpy.context.collection.objects.link(flag_obj)
    flag_obj.data.materials.append(flag_y)

    export_glb("marshal_post.glb")


def build_crane():
    clear_scene()
    yellow = make_mat("crane_yellow", (0.94, 0.74, 0.04), roughness=0.52, metallic=0.25)
    dark = make_mat("crane_dark", (0.14, 0.15, 0.16), roughness=0.75, metallic=0.3)
    tire = make_mat("tire_rubber", (0.10, 0.10, 0.11), roughness=0.88)
    rim = make_mat("wheel_rim", (0.65, 0.67, 0.70), roughness=0.4, metallic=0.7)
    glass = make_mat("cab_glass", (0.12, 0.20, 0.30), roughness=0.12, metallic=0.45)
    beacon = make_mat("beacon", (1.0, 0.55, 0.05), roughness=0.2, emission=(1.0, 0.55, 0.05), emission_strength=1.5)

    # Chassis facing -Y in Blender (+Z in Godot)
    add_box("chassis", (2.4, 6.6, 0.65), (0, 0, 0.85), dark)
    add_box("deck", (2.5, 6.2, 0.25), (0, 0.1, 1.25), yellow)

    # 6 wheels
    for wy in (-2.1, 0.8, 2.2):
        for wx in (-1.18, 1.18):
            add_cyl(f"tire_{wx}_{wy}", 0.55, 0.38, (wx, wy, 0.55), tire, rot=(0, math.pi / 2, 0), verts=12)
            add_cyl(f"rim_{wx}_{wy}", 0.30, 0.40, (wx, wy, 0.55), rim, rot=(0, math.pi / 2, 0), verts=10)

    # Front cab
    add_box("cab", (2.25, 1.9, 1.55), (0, -2.15, 2.10), yellow, bevel=0.06)
    add_box("cab_windshield", (1.95, 0.10, 0.80), (0, -3.08, 2.30), glass)
    add_box("cab_side_win", (2.29, 1.10, 0.68), (0, -2.15, 2.32), glass)
    add_cyl("cab_beacon", 0.12, 0.18, (0, -2.15, 2.96), beacon, verts=8)

    # Outrigger pads
    for oy in (-1.0, 2.7):
        for ox in (-1.35, 1.35):
            add_box(f"outrigger_{ox}_{oy}", (0.45, 0.45, 0.22), (ox, oy, 0.25), yellow)

    # Rotating turret & counterweight
    add_box("turret", (2.0, 2.6, 1.15), (0, 0.9, 1.95), yellow, bevel=0.05)
    add_box("counterweight", (2.3, 1.1, 1.35), (0, 2.4, 2.05), dark, bevel=0.04)

    # Angled lattice boom (rising from turret toward -Y / +Z)
    base_l = Vector((-0.38, 1.3, 2.4))
    base_r = Vector((0.38, 1.3, 2.4))
    tip_l = Vector((-0.26, -7.2, 14.8))
    tip_r = Vector((0.26, -7.2, 14.8))
    top_off = Vector((0, 0.45, 0.45))

    add_beam("boom_bl", base_l, tip_l, 0.18, yellow)
    add_beam("boom_br", base_r, tip_r, 0.18, yellow)
    add_beam("boom_tl", base_l + top_off, tip_l + top_off * 0.65, 0.16, yellow)
    add_beam("boom_tr", base_r + top_off, tip_r + top_off * 0.65, 0.16, yellow)

    # Cross struts along boom
    for k in range(6):
        t = k / 5.0
        pl = base_l.lerp(tip_l, t)
        pr = base_r.lerp(tip_r, t)
        ptl = (base_l + top_off).lerp(tip_l + top_off * 0.65, t)
        ptr = (base_r + top_off).lerp(tip_r + top_off * 0.65, t)
        add_beam(f"strut_b_{k}", pl, pr, 0.10, yellow)
        add_beam(f"strut_t_{k}", ptl, ptr, 0.10, yellow)
        add_beam(f"strut_l_{k}", pl, ptl, 0.10, yellow)
        add_beam(f"strut_r_{k}", pr, ptr, 0.10, yellow)

    # Pulley head, cable and hook
    head = (tip_l + tip_r) * 0.5 + Vector((0, -0.2, 0.1))
    add_box("pulley_head", (0.70, 0.65, 0.55), head, dark)
    hook_pos = head - Vector((0, 0, 3.8))
    add_cyl("cable", 0.03, 3.8, (head + hook_pos) * 0.5, dark, verts=6)
    add_box("hook_block", (0.35, 0.35, 0.48), hook_pos, dark)

    export_glb("crane.glb")


def build_ambulance():
    clear_scene()
    white = make_mat("amb_white", (0.95, 0.95, 0.94), roughness=0.35, metallic=0.1)
    red = make_mat("amb_red", (0.86, 0.12, 0.12), roughness=0.4)
    glass = make_mat("amb_glass", (0.10, 0.18, 0.26), roughness=0.10, metallic=0.5)
    tire = make_mat("amb_tire", (0.10, 0.10, 0.11), roughness=0.88)
    rim = make_mat("amb_rim", (0.72, 0.74, 0.76), roughness=0.35, metallic=0.75)
    bumper = make_mat("amb_bumper", (0.18, 0.19, 0.21), roughness=0.6)
    bar_red = make_mat("light_red", (0.95, 0.1, 0.1), roughness=0.2, emission=(1.0, 0.1, 0.1), emission_strength=1.4)
    bar_blue = make_mat("light_blue", (0.1, 0.4, 1.0), roughness=0.2, emission=(0.15, 0.45, 1.0), emission_strength=1.4)

    # Rear medical box (+Y) + front cab (-Y)
    add_box("med_box", (2.15, 3.45, 1.95), (0, 0.85, 1.38), white, bevel=0.05)
    add_box("cab_body", (2.02, 1.55, 1.45), (0, -1.60, 1.12), white, bevel=0.06)
    add_box("cab_hood", (1.96, 0.85, 0.82), (0, -2.35, 0.82), white, bevel=0.05)
    add_box("bumper_f", (2.06, 0.22, 0.32), (0, -2.78, 0.48), bumper)
    add_box("bumper_r", (2.18, 0.22, 0.32), (0, 2.58, 0.48), bumper)

    # Windows
    add_box("windshield", (1.78, 0.14, 0.68), (0, -2.02, 1.48), glass, rot=(0.35, 0, 0))
    add_box("cab_side_win", (2.06, 0.85, 0.56), (0, -1.55, 1.48), glass)

    # Rescue stripe & medical crosses
    add_box("stripe", (2.19, 3.46, 0.26), (0, 0.85, 1.12), red)
    add_box("cross_h", (2.21, 0.72, 0.20), (0, 0.85, 1.75), red)
    add_box("cross_v", (2.21, 0.20, 0.72), (0, 0.85, 1.75), red)
    add_box("cross_back_h", (0.64, 0.06, 0.18), (0, 2.57, 1.65), red)
    add_box("cross_back_v", (0.18, 0.06, 0.64), (0, 2.57, 1.65), red)

    # Lightbars
    add_box("bar_l", (0.55, 0.24, 0.14), (-0.32, -1.55, 1.92), bar_red)
    add_box("bar_r", (0.55, 0.24, 0.14), (0.32, -1.55, 1.92), bar_blue)
    add_box("bar_rear", (0.90, 0.18, 0.12), (0, 2.45, 2.40), bar_red)

    # 4 wheels
    for wy in (-1.85, 1.55):
        for wx in (-0.98, 0.98):
            add_cyl(f"tire_{wx}_{wy}", 0.40, 0.26, (wx, wy, 0.40), tire, rot=(0, math.pi / 2, 0), verts=12)
            add_cyl(f"rim_{wx}_{wy}", 0.23, 0.28, (wx, wy, 0.40), rim, rot=(0, math.pi / 2, 0), verts=10)

    export_glb("ambulance.glb")


def build_gantry_tower():
    clear_scene()
    steel = make_mat("tower_steel", (0.24, 0.26, 0.29), roughness=0.48, metallic=0.65)
    concrete = make_mat("tower_base", (0.55, 0.55, 0.53), roughness=0.9)

    add_box("footing", (1.35, 1.35, 0.45), (0, 0, 0.225), concrete)
    w = 0.42
    h = 7.2
    # 4 vertical corner columns
    for cx in (-w, w):
        for cy in (-w, w):
            add_beam(f"col_{cx}_{cy}", (cx, cy, 0.45), (cx, cy, h), 0.12, steel)

    # Horizontal & diagonal braces (4 bays)
    levels = [0.45, 2.1, 3.8, 5.5, h]
    for i in range(len(levels) - 1):
        z0, z1 = levels[i], levels[i + 1]
        for sgn in (-1, 1):
            add_beam(f"hx_{i}_{sgn}", (-w, sgn * w, z1), (w, sgn * w, z1), 0.08, steel)
            add_beam(f"hy_{i}_{sgn}", (sgn * w, -w, z1), (sgn * w, w, z1), 0.08, steel)
            add_beam(f"dx_{i}_{sgn}", (-w, sgn * w, z0), (w, sgn * w, z1), 0.07, steel)
            add_beam(f"dy_{i}_{sgn}", (sgn * w, -w, z0), (sgn * w, w, z1), 0.07, steel)

    add_box("cap_plate", (1.1, 1.1, 0.14), (0, 0, h + 0.07), steel)
    export_glb("gantry_tower.glb")


def build_corkscrew_bridge():
    """
    Truss modular de 1.0 m de vão normalizado em X ([-0.5, +0.5]) para ser escalada para a largura da pista.
    """
    clear_scene()
    steel = make_mat("bridge_steel", (0.28, 0.30, 0.34), roughness=0.45, metallic=0.65)
    deck_mat = make_mat("bridge_deck", (0.45, 0.46, 0.48), roughness=0.85)
    rail_mat = make_mat("bridge_rail", (0.72, 0.74, 0.76), roughness=0.4, metallic=0.6)

    # Deck & side chords (normalized X in [-0.5, 0.5], Z height 0..2.2m above deck base, Y depth 2.2m)
    add_box("deck", (1.0, 2.2, 0.22), (0, 0, 0.11), deck_mat)
    for sy in (-1.05, 1.05):
        add_box(f"lower_chord_{sy}", (1.0, 0.12, 0.14), (0, sy, 0.14), steel)
        add_box(f"upper_chord_{sy}", (1.0, 0.12, 0.14), (0, sy, 2.15), steel)
        add_box(f"handrail_{sy}", (1.0, 0.06, 0.06), (0, sy * 0.94, 1.15), rail_mat)

    # Diagonal & vertical lattice bays (6 bays across [-0.5, +0.5])
    bays = 6
    for i in range(bays + 1):
        x = -0.5 + i / bays
        for sy in (-1.05, 1.05):
            add_box(f"post_{i}_{sy}", (0.025, 0.10, 2.05), (x, sy, 1.14), steel)
            if i < bays:
                x_next = -0.5 + (i + 1) / bays
                z_a = 0.14 if i % 2 == 0 else 2.15
                z_b = 2.15 if i % 2 == 0 else 0.14
                add_beam(f"diag_{i}_{sy}", (x, sy, z_a), (x_next, sy, z_b), 0.04, steel)

    # Top overhead cross ties
    for i in range(bays + 1):
        x = -0.5 + i / bays
        add_box(f"top_tie_{i}", (0.025, 2.15, 0.10), (x, 0, 2.15), steel)

    export_glb("corkscrew_bridge.glb")


if __name__ == "__main__":
    build_marshal_post()
    build_crane()
    build_ambulance()
    build_gantry_tower()
    build_corkscrew_bridge()
