# /Users/mymac/zutsuu/assets/kiabou/variations/props.py
# 原型の寝床に合う雲・雫・楕円の枕と、差し替え用の毛布を作る。
# 休むモデルと同じ原点を使い、着せ替え時の再配置を不要にするため。
# 関連: materials.py, build_variations.py, ../kiabou-rest.blend, ASSETS.md
from math import atan2, cos, pi
import bpy
from materials import PALETTES, solid_material, blanket_material


def freeze_rest_pose(rig, fish):
    rig.animation_data_clear()
    for bone in rig.pose.bones:
        bone.location, bone.rotation_euler, bone.scale = (0, 0, 0), (0, 0, 0), (1, 1, 1)
        if bone.name.startswith('eye.'):
            bone.scale[1] = .09
    rig.pose.bones['body'].rotation_euler[0] = pi / 2
    rig.pose.bones['body'].location[1] = -.97
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    fish.select_set(True)
    bpy.context.view_layer.objects.active = fish
    bpy.ops.object.convert(target='MESH')
    fish = bpy.context.object
    matrix = fish.matrix_world.copy()
    fish.parent = None
    fish.matrix_world = matrix
    fish.name = 'KiabouRestBody'
    return fish


def create_props(family, original, directory):
    names = ['Resting place', 'A blanket from someone']
    with bpy.data.libraries.load(str(original), link=False) as (source, target):
        target.objects = names
    bed, blanket = target.objects
    for obj in (bed, blanket):
        bpy.context.collection.objects.link(obj)
        obj.hide_render = False
    bed.name, blanket.name = 'KiabouBed', 'KiabouBlanket'
    blanket.data.materials.clear()
    blanket.data.materials.append(blanket_material(family, directory))
    uv = blanket.data.uv_layers.new(name='UVMap')
    for loop in blanket.data.loops:
        co = blanket.data.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = ((co.x + .018) / .125, (co.y + .145) / .29)

    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, location=(-.062, 0, .020))
    pillow = bpy.context.object
    pillow.name = 'KiabouPillow'
    for vertex in pillow.data.vertices:
        x, y, z = vertex.co
        if family == 'kasumi':
            angle = atan2(y, x)
            edge = 1 + .12 * cos(5 * angle) + .035 * cos(3 * angle)
            x, y = x * edge, y * edge
        elif family == 'shizuku':
            x *= .84 - .28 * y
        vertex.co = (x * .034, y * .055, z * .015)
    pillow.data.materials.append(solid_material('Kiabou.Pillow', PALETTES[family]['pillow']))
    for polygon in pillow.data.polygons:
        polygon.use_smooth = True
    return bed, pillow, blanket
