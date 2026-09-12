# /Users/mymac/zutsuu/assets/kiabou/create_rest.py
# きあぼうが寝床で休む姿と、毛布をかけた姿を書き出す。
# 休む人と気遣う人の体験を、承認済みの3D原型で確認するため。
# 関連: kiabou.blend, create_kiabou.py, rest.js, index.html
from pathlib import Path
from math import pi
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

OUT = Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(OUT / 'kiabou.blend'))
scene = bpy.context.scene
rig = bpy.data.objects['Kiabou']
fish = bpy.data.objects['KiabouMesh']
rig.animation_data_clear()
for bone in rig.pose.bones:
    bone.location, bone.rotation_euler, bone.scale = (0, 0, 0), (0, 0, 0), (1, 1, 1)
    if bone.name.startswith('eye.'):
        bone.scale[1] = .09
rig.pose.bones['body'].rotation_euler[0] = pi / 2
rig.pose.bones['body'].location[1] = -.97
bpy.context.view_layer.update()
# 静止した姿として焼き込み、ビューアやアプリで同じ寝姿にする。
bpy.ops.object.select_all(action='DESELECT')
fish.select_set(True)
bpy.context.view_layer.objects.active = fish
bpy.ops.object.convert(target='MESH')
fish = bpy.context.object
matrix = fish.matrix_world.copy()
fish.parent = None
fish.matrix_world = matrix
parts = [fish]


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = .92
    return mat


linen = material('Warm linen', (.77, .76, .69))
pillow_mat = material('Pillow', (.94, .92, .84))
blanket_mat = material('Quiet blue blanket', (.18, .33, .46))


def cushion(name, location, scale, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, location=location)
    obj = bpy.context.object
    obj.name, obj.scale = name, scale
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    parts.append(obj)
    return obj


cushion('Resting place', (0, 0, .008), (.114, .154, .009), linen)
cushion('Little pillow', (-.062, 0, .020), (.034, .055, .015), pillow_mat)
# 布の面を体の上で盛り上げ、端を寝床へ垂らす。頭は覆わない。
vertices, faces = [], []
nx, ny = 32, 48
surface = BVHTree.FromPolygons([fish.matrix_world @ v.co for v in fish.data.vertices],
                              [list(p.vertices) for p in fish.data.polygons])
heights = []
for i in range(nx + 1):
    x = -.018 + .125 * i / nx
    for j in range(ny + 1):
        y = -.145 + .29 * j / ny
        hit, *_ = surface.ray_cast(Vector((x, y, 1)), Vector((0, 0, -1)))
        z = max(.018, hit.z + .004 if hit else .018)
        heights.append(z)
        vertices.append((x, y, z))
        if i < nx and j < ny:
            a = i * (ny + 1) + j
            faces.append((a, a + ny + 1, a + ny + 2, a + 1))
# 体の表面を下限にして面をならす。ヒレを貫通せず、寝床へ自然に垂れる。
cloth = heights.copy()
for _ in range(90):
    previous = cloth.copy()
    for i in range(nx + 1):
        for j in range(ny + 1):
            a = i * (ny + 1) + j
            neighbors = [previous[u * (ny + 1) + v] for u, v in
                         [(i - 1, j), (i + 1, j), (i, j - 1), (i, j + 1)]
                         if 0 <= u <= nx and 0 <= v <= ny]
            cloth[a] = max(heights[a], sum(neighbors) / len(neighbors) - .00012)
vertices = [(x, y, cloth[k]) for k, (x, y, _) in enumerate(vertices)]
data = bpy.data.meshes.new('Blanket surface')
data.from_pydata(vertices, [], faces)
blanket = bpy.data.objects.new('A blanket from someone', data)
bpy.context.collection.objects.link(blanket)
data.materials.append(blanket_mat)
for face in data.polygons:
    face.use_smooth = True
solid = blanket.modifiers.new('Soft hem', 'SOLIDIFY')
solid.thickness = .002
bevel = blanket.modifiers.new('Rounded hem', 'BEVEL')
bevel.width, bevel.segments = .001, 3

scene.camera.location = (-.34, -.44, .42)
scene.camera.rotation_euler = (Vector((0, 0, .025)) - scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera.data.ortho_scale = .36
scene.render.resolution_x, scene.render.resolution_y = 1000, 850
scene.cycles.samples = 32
for covered in (False, True):
    blanket.hide_render = not covered
    name = 'covered' if covered else 'resting'
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts + ([blanket] if covered else []):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = fish
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + '.glb')), export_format='GLB',
                             use_selection=True, export_animations=False)
    scene.render.filepath = str(OUT / (name + '.png'))
    bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'kiabou-rest.blend'))
print('REST_ASSETS_READY')
