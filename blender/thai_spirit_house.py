import math
import os
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Vector


ROOT = Path(os.path.dirname(os.path.abspath(__file__))).parent
OUT_DIR = ROOT / "output"
RENDER_DIR = OUT_DIR / "renders"
EXPORT_DIR = OUT_DIR / "exports"


def ensure_dirs():
    for path in (OUT_DIR, RENDER_DIR, EXPORT_DIR):
        path.mkdir(parents=True, exist_ok=True)


def clean_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.meshes:
        bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        bpy.data.materials.remove(block)
    for block in bpy.data.images:
        if block.users == 0:
            bpy.data.images.remove(block)


def set_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 64
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1000
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.exposure = -1.1
    scene.view_settings.gamma = 1.0
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.63, 0.68, 0.72, 1.0)
    bg.inputs[1].default_value = 0.28


def set_smooth(obj, angle=math.radians(45)):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    if hasattr(obj.data, "use_auto_smooth"):
        obj.data.use_auto_smooth = True
        obj.data.auto_smooth_angle = angle


def add_bevel(obj, width=0.03, segments=2):
    mod = obj.modifiers.new(name="Bevel", type="BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def assign_material(obj, material):
    if material is None:
        return
    if obj.data.materials:
        obj.data.materials[0] = material
    else:
        obj.data.materials.append(material)


def create_principled_material(name, base_color, roughness=0.5, metallic=0.0, specular=0.5):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    for node in list(nodes):
        if node.name != "Material Output":
            nodes.remove(node)
    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    out = nodes["Material Output"]
    bsdf.inputs["Base Color"].default_value = base_color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = specular
    mat.node_tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def create_wood_material(name, base=(0.62, 0.48, 0.32, 1.0), accent=(0.34, 0.22, 0.11, 1.0), roughness=0.7):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    for node in list(nodes):
        if node.name != "Material Output":
            nodes.remove(node)

    out = nodes["Material Output"]
    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    texcoord = nodes.new(type="ShaderNodeTexCoord")
    mapping = nodes.new(type="ShaderNodeMapping")
    wave = nodes.new(type="ShaderNodeTexWave")
    noise = nodes.new(type="ShaderNodeTexNoise")
    ramp = nodes.new(type="ShaderNodeValToRGB")
    mix = nodes.new(type="ShaderNodeMixRGB")
    bump = nodes.new(type="ShaderNodeBump")

    mapping.inputs["Scale"].default_value = (5.0, 1.0, 1.0)
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    wave.inputs["Scale"].default_value = 6.0
    wave.inputs["Distortion"].default_value = 4.0
    noise.inputs["Scale"].default_value = 15.0
    noise.inputs["Detail"].default_value = 8.0
    ramp.color_ramp.elements[0].color = accent
    ramp.color_ramp.elements[1].color = base
    mix.inputs["Fac"].default_value = 0.2
    bsdf.inputs["Roughness"].default_value = roughness

    links.new(texcoord.outputs["Object"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], wave.inputs["Vector"])
    links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    links.new(wave.outputs["Color"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], mix.inputs["Color1"])
    links.new(noise.outputs["Color"], mix.inputs["Color2"])
    links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(noise.outputs["Fac"], bump.inputs["Height"])
    bump.inputs["Strength"].default_value = 0.12
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def create_cloth_material(name, color):
    return create_principled_material(name, color, roughness=0.9, metallic=0.0, specular=0.35)


def create_emission_material(name, color, strength=8.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    for node in list(nodes):
        if node.name != "Material Output":
            nodes.remove(node)
    emission = nodes.new(type="ShaderNodeEmission")
    out = nodes["Material Output"]
    emission.inputs["Color"].default_value = color
    emission.inputs["Strength"].default_value = strength
    links.new(emission.outputs["Emission"], out.inputs["Surface"])
    return mat


def create_portrait_material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    for node in list(nodes):
        if node.name != "Material Output":
            nodes.remove(node)

    img = bpy.data.images.new("AncestorPortrait", width=256, height=256)
    pixels = []
    for y in range(256):
        for x in range(256):
            u = x / 255.0
            v = y / 255.0
            color = [0.77, 0.69, 0.56, 1.0]
            if 0.18 < u < 0.82 and 0.18 < v < 0.82:
                color = [0.86, 0.8, 0.68, 1.0]
            dx = u - 0.5
            dy = v - 0.58
            if dx * dx / 0.06 + dy * dy / 0.09 < 1.0:
                color = [0.69, 0.57, 0.44, 1.0]
            if dx * dx / 0.01 + (v - 0.47) * (v - 0.47) / 0.018 < 1.0:
                color = [0.2, 0.12, 0.08, 1.0]
            if abs(dx) < 0.045 and 0.28 < v < 0.62:
                color = [0.4, 0.2, 0.1, 1.0]
            pixels.extend(color)
    img.pixels = pixels
    img.pack()

    tex = nodes.new(type="ShaderNodeTexImage")
    tex.image = img
    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    out = nodes["Material Output"]
    bsdf.inputs["Roughness"].default_value = 0.6
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def add_cube(name, size, location, rotation=(0.0, 0.0, 0.0), material=None, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    if bevel > 0.0:
        add_bevel(obj, width=bevel)
    set_smooth(obj)
    return obj


def add_cylinder(name, radius, depth, location, rotation=(0.0, 0.0, 0.0), vertices=24, material=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    set_smooth(obj)
    return obj


def add_plane(name, size, location, rotation=(0.0, 0.0, 0.0), material=None):
    bpy.ops.mesh.primitive_plane_add(size=size, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    return obj


def create_gable(name, width, depth, height, location, material=None):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    w = width * 0.5
    d = depth * 0.5
    verts = [
        (-w, -d, 0.0),
        (w, -d, 0.0),
        (0.0, -d, height),
        (-w, d, 0.0),
        (w, d, 0.0),
        (0.0, d, height),
    ]
    faces = [
        (0, 1, 2),
        (3, 5, 4),
        (0, 3, 4, 1),
        (1, 4, 5, 2),
        (2, 5, 3, 0),
    ]
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj.location = location
    assign_material(obj, material)
    set_smooth(obj, angle=math.radians(30))
    return obj


def add_roof_trim(start, end, height, radius, material):
    direction = Vector(end) - Vector(start)
    mid = (Vector(start) + Vector(end)) * 0.5
    length = direction.length
    yaw = math.atan2(direction.y, direction.x)
    pitch = math.atan2(direction.z, math.sqrt(direction.x ** 2 + direction.y ** 2))
    return add_cylinder(
        "RoofTrim",
        radius=radius,
        depth=length,
        location=(mid.x, mid.y, mid.z + height),
        rotation=(0.0, math.pi * 0.5 - pitch, yaw + math.pi * 0.5),
        vertices=12,
        material=material,
    )


def add_post_row(x_values, y, z_bottom, z_top, radius, material):
    posts = []
    depth = z_top - z_bottom
    z = z_bottom + depth * 0.5
    for x in x_values:
        posts.append(add_cylinder("Post", radius, depth, (x, y, z), material=material))
    return posts


def add_railing(x0, x1, y, z, material):
    span = x1 - x0
    add_cube("RailTop", (span, 0.06, 0.08), ((x0 + x1) * 0.5, y, z + 0.42), material=material, bevel=0.01)
    add_cube("RailMid", (span, 0.05, 0.07), ((x0 + x1) * 0.5, y, z + 0.2), material=material, bevel=0.01)
    count = 8
    for i in range(count + 1):
        x = x0 + span * i / count
        add_cube("Baluster", (0.05, 0.05, 0.34), (x, y, z + 0.18), material=material, bevel=0.008)


def add_steps(width, depth, step_count, base_location, material):
    step_height = 0.18
    step_depth = depth / step_count
    for i in range(step_count):
        add_cube(
            "Step",
            (width, step_depth * (step_count - i), step_height),
            (base_location[0], base_location[1] + (step_depth * i * 0.5), base_location[2] + step_height * 0.5 + i * step_height),
            material=material,
            bevel=0.01,
        )


def add_cloth_banner(x, y, z, material):
    cloth = add_cube("ClothStrip", (0.18, 0.05, 0.65), (x, y, z), material=material, bevel=0.004)
    cloth.rotation_euler = Euler((0.0, 0.14, 0.04), "XYZ")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return cloth


def add_frame_with_portrait(location, material_frame, material_portrait):
    add_cube("Frame", (0.74, 0.06, 0.92), location, material=material_frame, bevel=0.01)
    add_cube("FrameInner", (0.6, 0.02, 0.78), (location[0], location[1] - 0.02, location[2]), material=material_portrait)


def add_candle(location, wax_material, flame_material):
    add_cylinder("Candle", 0.05, 0.28, location, material=wax_material)
    flame = add_cylinder("Flame", 0.015, 0.08, (location[0], location[1], location[2] + 0.18), material=flame_material, vertices=10)
    flame.scale = (1.0, 1.0, 1.3)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def add_lantern(location, body_material, light_material):
    add_cube("LanternBody", (0.18, 0.18, 0.28), location, material=body_material, bevel=0.02)
    add_cube("LanternGlass", (0.11, 0.11, 0.18), (location[0], location[1], location[2] - 0.02), material=light_material, bevel=0.01)


def add_target(name, location):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=location)
    target = bpy.context.object
    target.name = name
    return target


def point_camera(camera, target):
    constraint = camera.constraints.new(type="TRACK_TO")
    constraint.target = target
    constraint.track_axis = "TRACK_NEGATIVE_Z"
    constraint.up_axis = "UP_Y"


def build_scene():
    wood = create_wood_material("WeatheredWood", base=(0.66, 0.57, 0.45, 1.0), accent=(0.34, 0.27, 0.17, 1.0))
    dark_wood = create_wood_material("DarkWood", base=(0.36, 0.25, 0.14, 1.0), accent=(0.15, 0.1, 0.06, 1.0), roughness=0.75)
    roof = create_wood_material("RoofWood", base=(0.31, 0.21, 0.12, 1.0), accent=(0.15, 0.08, 0.04, 1.0), roughness=0.82)
    stone = create_principled_material("Stone", (0.52, 0.51, 0.49, 1.0), roughness=0.95, metallic=0.0, specular=0.25)
    gold = create_principled_material("GoldTrim", (0.74, 0.58, 0.18, 1.0), roughness=0.35, metallic=0.8, specular=0.55)
    fabric_red = create_cloth_material("ClothRed", (0.74, 0.12, 0.08, 1.0))
    fabric_yellow = create_cloth_material("ClothYellow", (0.95, 0.74, 0.16, 1.0))
    fabric_green = create_cloth_material("ClothGreen", (0.1, 0.52, 0.24, 1.0))
    wax = create_principled_material("CandleWax", (0.98, 0.93, 0.82, 1.0), roughness=0.45, metallic=0.0, specular=0.45)
    flame = create_emission_material("Flame", (1.0, 0.55, 0.08, 1.0), strength=18.0)
    glow = create_emission_material("WarmGlow", (1.0, 0.82, 0.52, 1.0), strength=9.0)
    portrait = create_portrait_material("Portrait")

    ground = add_plane("Ground", 36.0, (0.0, 0.0, 0.0))
    bpy.context.view_layer.objects.active = ground
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.subdivide(number_cuts=40)
    bpy.ops.object.mode_set(mode="OBJECT")
    bm = bmesh.new()
    bm.from_mesh(ground.data)
    for vert in bm.verts:
        vert.co.z = math.sin(vert.co.x * 0.32) * 0.05 + math.cos(vert.co.y * 0.28) * 0.04
    bm.to_mesh(ground.data)
    bm.free()
    assign_material(ground, create_principled_material("Grass", (0.48, 0.62, 0.37, 1.0), roughness=1.0, metallic=0.0, specular=0.2))

    add_cube("PedestalBase", (7.8, 5.4, 0.55), (0.0, 0.2, 0.28), material=stone, bevel=0.04)
    add_cube("PedestalTop", (6.9, 4.7, 0.26), (0.0, 0.2, 0.7), material=stone, bevel=0.03)

    floor_z = 2.25
    wall_bottom = floor_z + 0.12
    wall_top = floor_z + 2.05
    roof_base = wall_top + 0.18

    post_x = [-2.8, -1.45, 0.0, 1.45, 2.8]
    add_post_row(post_x, -1.65, 0.82, floor_z, 0.11, dark_wood)
    add_post_row(post_x, 1.35, 0.82, floor_z, 0.11, dark_wood)

    add_cube("FloorMain", (6.5, 3.5, 0.12), (0.0, -0.05, floor_z), material=wood, bevel=0.015)
    add_cube("FrontPorch", (2.2, 1.05, 0.11), (-2.1, 1.9, floor_z), material=wood, bevel=0.015)
    add_cube("FrontWalk", (1.05, 0.9, 0.11), (0.0, 1.78, floor_z), material=wood, bevel=0.015)

    add_steps(1.0, 1.5, 4, (0.0, 2.15, 0.82), wood)

    for x in [-2.7, -1.35, 0.0, 1.35, 2.7]:
        add_cube("FrontBeam", (0.1, 0.1, 2.0), (x, 1.3, floor_z + 1.0), material=dark_wood, bevel=0.008)
    add_cube("BeamTopFront", (5.7, 0.12, 0.12), (0.0, 1.3, wall_top - 0.04), material=dark_wood)
    add_cube("BeamTopRear", (5.7, 0.12, 0.12), (0.0, -1.4, wall_top - 0.04), material=dark_wood)

    add_cube("RearWall", (6.25, 0.14, 1.86), (0.0, -1.55, wall_bottom + 0.93), material=wood, bevel=0.012)
    add_cube("LeftWall", (0.14, 2.84, 1.86), (-3.13, -0.15, wall_bottom + 0.93), material=wood, bevel=0.012)
    add_cube("RightWall", (0.14, 2.84, 1.86), (3.13, -0.15, wall_bottom + 0.93), material=wood, bevel=0.012)
    add_cube("FrontWallLeft", (2.05, 0.14, 0.88), (-2.05, 1.27, wall_bottom + 0.44), material=wood, bevel=0.012)
    add_cube("FrontWallRight", (2.05, 0.14, 0.88), (2.05, 1.27, wall_bottom + 0.44), material=wood, bevel=0.012)
    add_cube("DoorLintel", (1.2, 0.12, 0.2), (0.0, 1.27, wall_top - 0.1), material=dark_wood)
    add_cube("DoorLeft", (0.42, 0.04, 1.55), (-0.44, 1.16, wall_bottom + 0.78), rotation=(0.0, 0.0, math.radians(18)), material=dark_wood, bevel=0.006)
    add_cube("DoorRight", (0.42, 0.04, 1.55), (0.44, 1.16, wall_bottom + 0.78), rotation=(0.0, 0.0, math.radians(-18)), material=dark_wood, bevel=0.006)
    add_cube("WindowPanelLeft", (0.66, 0.04, 0.74), (-1.0, 1.17, wall_bottom + 1.02), rotation=(0.0, 0.0, math.radians(10)), material=dark_wood, bevel=0.006)
    add_cube("WindowPanelRight", (0.66, 0.04, 0.74), (1.0, 1.17, wall_bottom + 1.02), rotation=(0.0, 0.0, math.radians(-10)), material=dark_wood, bevel=0.006)

    add_railing(-3.0, -1.2, 2.38, floor_z, dark_wood)
    add_railing(1.2, 3.0, 2.38, floor_z, dark_wood)
    add_railing(-3.0, -3.0, 1.0, floor_z, dark_wood)
    add_railing(3.0, 3.0, 1.0, floor_z, dark_wood)

    base_roof = create_gable("BaseRoof", 7.4, 4.2, 0.86, (0.0, -0.05, roof_base - 0.22), material=roof)
    add_bevel(base_roof, width=0.02, segments=2)

    roof_sections = [
        (-2.2, 2.55, 1.95, 2.0),
        (0.0, 1.55, 1.3, 1.7),
        (2.2, 2.55, 1.95, 2.0),
    ]
    for idx, (x, width, height, depth) in enumerate(roof_sections):
        gable = create_gable(f"Roof{idx}", width + 0.68, 4.0, height, (x, -0.05, roof_base), material=roof)
        add_bevel(gable, width=0.02, segments=2)
        add_cube(f"GableFace{idx}", (width * 0.82, 0.06, height * 0.7), (x, 1.85, roof_base + height * 0.36), material=wood, bevel=0.01)
        add_cube(f"GableBack{idx}", (width * 0.82, 0.06, height * 0.7), (x, -1.95, roof_base + height * 0.36), material=wood, bevel=0.01)

        left_start = (x - (width + 0.68) * 0.5, -2.0, roof_base)
        left_end = (x, -2.0, roof_base + height)
        right_start = (x + (width + 0.68) * 0.5, -2.0, roof_base)
        ridge_back = (x, -2.0, roof_base + height)
        add_roof_trim(left_start, left_end, 0.02, 0.03, gold)
        add_roof_trim(right_start, ridge_back, 0.02, 0.03, gold)

        left_front = (x - (width + 0.68) * 0.5, 2.0, roof_base)
        ridge_front = (x, 2.0, roof_base + height)
        right_front = (x + (width + 0.68) * 0.5, 2.0, roof_base)
        add_roof_trim(left_front, ridge_front, 0.02, 0.03, gold)
        add_roof_trim(right_front, ridge_front, 0.02, 0.03, gold)

        add_cylinder(f"RoofFinial{idx}", 0.055, 0.7, (x, 2.01, roof_base + height - 0.04), rotation=(math.pi * 0.5, 0.0, 0.0), material=gold, vertices=16)

    add_cube("InteriorPlatform", (2.3, 0.9, 0.3), (0.0, -1.05, floor_z + 0.21), material=dark_wood, bevel=0.02)
    add_cube("AltarTable", (1.8, 0.7, 0.72), (0.0, -0.72, floor_z + 0.48), material=dark_wood, bevel=0.015)
    add_cube("AltarTopCloth", (1.9, 0.76, 0.03), (0.0, -0.72, floor_z + 0.85), material=fabric_yellow)
    add_cube("InnerBenchLeft", (1.0, 0.35, 0.32), (-1.55, -0.52, floor_z + 0.18), material=wood, bevel=0.01)
    add_cube("InnerBenchRight", (1.0, 0.35, 0.32), (1.55, -0.52, floor_z + 0.18), material=wood, bevel=0.01)
    add_cube("FloorMat", (1.15, 0.6, 0.02), (0.0, 0.25, floor_z + 0.08), material=fabric_red)

    add_frame_with_portrait((0.0, -1.48, floor_z + 1.28), gold, portrait)
    add_candle((-0.44, -0.35, floor_z + 0.96), wax, flame)
    add_candle((0.44, -0.35, floor_z + 0.96), wax, flame)
    add_candle((-0.92, -0.48, floor_z + 0.96), wax, flame)
    add_candle((0.92, -0.48, floor_z + 0.96), wax, flame)
    add_lantern((-1.55, 1.15, floor_z + 0.84), gold, glow)
    add_lantern((1.55, 1.15, floor_z + 0.84), gold, glow)

    add_cube("ClothBar", (0.7, 0.05, 0.04), (2.08, 1.04, floor_z + 1.62), material=gold, bevel=0.006)
    add_cloth_banner(1.82, 1.04, floor_z + 1.28, fabric_red)
    add_cloth_banner(2.08, 1.04, floor_z + 1.28, fabric_yellow)
    add_cloth_banner(2.34, 1.04, floor_z + 1.28, fabric_green)

    add_cube("OfferTray", (0.48, 0.35, 0.06), (0.0, -0.1, floor_z + 0.9), material=gold, bevel=0.01)
    for x in (-0.18, 0.0, 0.18):
        add_cylinder("Fruit", 0.08, 0.09, (x, -0.1, floor_z + 0.98), material=create_principled_material(f"Fruit{x}", (0.9, 0.5 + x * 0.2, 0.22, 1.0), roughness=0.45, metallic=0.0, specular=0.45), vertices=20)

    bpy.ops.object.light_add(type="SUN", location=(6.0, -4.0, 10.0))
    sun = bpy.context.object
    sun.data.energy = 0.9
    sun.rotation_euler = Euler((math.radians(42), 0.0, math.radians(36)), "XYZ")

    bpy.ops.object.light_add(type="AREA", location=(0.0, 2.3, 4.6))
    area = bpy.context.object
    area.data.energy = 350
    area.data.shape = "RECTANGLE"
    area.data.size = 6.0
    area.data.size_y = 3.0
    area.rotation_euler = Euler((math.radians(72), 0.0, math.pi), "XYZ")

    front_target = add_target("FrontTarget", (0.0, -0.15, 3.25))
    altar_target = add_target("AltarTarget", (0.0, -0.78, 3.15))

    bpy.ops.object.camera_add(location=(0.0, 10.8, 5.2))
    cam_front = bpy.context.object
    cam_front.data.lens = 35
    cam_front.name = "CameraFront"
    point_camera(cam_front, front_target)

    bpy.ops.object.camera_add(location=(2.05, 2.55, 3.0))
    cam_inside = bpy.context.object
    cam_inside.data.lens = 32
    cam_inside.name = "CameraInterior"
    point_camera(cam_inside, altar_target)

    return cam_front, cam_inside


def render_views(camera_front, camera_inside):
    scene = bpy.context.scene
    for name, camera in (("spirit_house_front", camera_front), ("spirit_house_interior", camera_inside)):
        scene.camera = camera
        scene.render.filepath = str(RENDER_DIR / f"{name}.png")
        bpy.ops.render.render(write_still=True)


def save_outputs():
    bpy.ops.wm.save_as_mainfile(filepath=str(EXPORT_DIR / "thai_spirit_house.blend"))
    bpy.ops.export_scene.gltf(filepath=str(EXPORT_DIR / "thai_spirit_house.glb"), export_format="GLB")


def main():
    ensure_dirs()
    clean_scene()
    set_scene()
    cams = build_scene()
    render_views(*cams)
    save_outputs()


if __name__ == "__main__":
    main()
