# /Users/mymac/zutsuu/assets/kiabou/create_kiabou.py
# マンボウの「きあぼう」を作り、ゆっくり泳ぐ動作を付ける。
# 承認されたラフの形と顔を保った、編集可能なアプリ用3D原本を残すため。
# 関連: geometry.py, export_kiabou.py, index.html, kiabou.blend
from pathlib import Path
from math import sin, pi
import sys
import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(OUT))
from geometry import body_gradient, side_surface, fin, soften_fin_weights

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.frame_start, scene.frame_end, scene.render.fps = 1, 181, 30
parts = []


def material(name, color, roughness=.5):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = roughness
    return mat


shell = material('Blue back and white belly', (.8, .9, .95), .55)
navy = material('Deep blue fins', (.030, .092, .19), .57)
tail_color = material('Soft blue clavus', (.19, .34, .49), .6)
ink = material('Small quiet face', (.008, .018, .027), .75)


def finish(obj, name, mat, bone):
    obj.name = name
    obj.data.materials.append(mat)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for face in obj.data.polygons:
        face.use_smooth = True
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
    parts.append(obj)
    return obj


def oval(name, location, scale, mat, bone):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, location=location)
    obj = bpy.context.object
    obj.scale = scale
    return finish(obj, name, mat, bone)


# 体は左右に薄い一枚の丸い形。前方を長くしてマンボウの鈍い鼻先を作る。
bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=40, location=(0, 0, 1.4))
body = bpy.context.object
for vertex in body.data.vertices:
    x, y, z = vertex.co
    vertex.co = (x * (.78 if x < 0 else .63), y * .255, z * .67)
finish(body, 'Kiabou body', shell, 'body')
body_gradient(body, shell)

upper = [( .10, 1.93), (.21, 2.22), (.43, 2.58), (.57, 2.71),
         (.63, 2.65), (.62, 2.36), (.60, 1.98), (.38, 1.89)]
lower = [( .12, .88), (.25, .57), (.44, .20), (.55, .10),
         (.61, .17), (.60, .44), (.59, .84), (.37, .92)]
for name, outline, center, base, direction in [('dorsal', upper, (.43, 2.25), 1.90, 1),
                                             ('anal', lower, (.44, .58), .90, -1)]:
    obj = fin(name, outline, center, .042, 0, navy, finish, name)
    soften_fin_weights(obj, name, name + '.tip', base, direction)

clavus = [(.46, 1.93), (.65, 1.94), (.77, 1.87), (.77, 1.77), (.84, 1.67),
          (.82, 1.57), (.88, 1.47), (.85, 1.36), (.88, 1.26), (.82, 1.15),
          (.81, 1.05), (.70, .94), (.54, .92), (.46, 1.04)]
fin('Clavus', clavus, (.64, 1.43), .080, 0, tail_color, finish, 'clavus')
for side, sign in [('L', -1), ('R', 1)]:
    eye_y = sign * (side_surface(-.43, 1.59) + .003)
    oval('Eye.' + side, (-.43, eye_y, 1.59), (.025, .006, .026), ink, 'eye.' + side)
    fin('Pectoral.' + side, [(-.10, 1.39), (.04, 1.47), (.22, 1.44),
        (.23, 1.34), (.12, 1.27), (-.04, 1.30)], (.08, 1.37), .026,
        sign * .263, tail_color, finish, 'pectoral.' + side)

# 控えめな口の線は鼻先の面に沿わせ、唇や眼球の出っ張りを作らない。
curve = bpy.data.curves.new('Mouth', 'CURVE')
curve.dimensions, curve.resolution_u = '3D', 8
curve.bevel_depth, curve.bevel_resolution = .0065, 2
spline = curve.splines.new('BEZIER')
points = [(-.737, -side_surface(-.737, 1.385) - .002, 1.385),
          (-.769, -side_surface(-.769, 1.385) - .002, 1.385),
          (-.780, 0, 1.385), (-.769, side_surface(-.769, 1.385) + .002, 1.385),
          (-.737, side_surface(-.737, 1.385) + .002, 1.385)]
spline.bezier_points.add(len(points) - 1)
for point, coordinate in zip(spline.bezier_points, points):
    point.co = coordinate
    point.handle_left_type = point.handle_right_type = 'AUTO'
obj = bpy.data.objects.new('Mouth', curve)
bpy.context.collection.objects.link(obj)
bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.object.convert(target='MESH')
finish(bpy.context.object, 'Mouth', ink, 'body')

bpy.ops.object.select_all(action='DESELECT')
for obj in parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
mesh = bpy.context.object
mesh.name = 'KiabouMesh'
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
armature = bpy.data.armatures.new('KiabouSkeleton')
rig = bpy.data.objects.new('Kiabou', armature)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bones = [('body', (0, 0, 1.4), None), ('dorsal', (.38, 0, 1.96), 'body'),
         ('dorsal.tip', (.51, 0, 2.36), 'dorsal'), ('anal', (.39, 0, .85), 'body'),
         ('anal.tip', (.51, 0, .45), 'anal'), ('clavus', (.54, 0, 1.4), 'body')]
for side, sign in [('L', -1), ('R', 1)]:
    bones += [('eye.' + side, (-.43, sign * (side_surface(-.43, 1.59) + .003), 1.59), 'body'),
              ('pectoral.' + side, (-.075, sign * .263, 1.36), 'body')]
for name, position, parent in bones:
    bone = armature.edit_bones.new(name)
    bone.head, bone.tail = Vector(position), Vector(position) + Vector((0, 0, .12))
    if parent:
        bone.parent = armature.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')
mesh.parent = rig
modifier = mesh.modifiers.new('Soft fin motion', 'ARMATURE')
modifier.object = rig
rig.scale = (.1, .1, .1)

# 6秒でつながる浮遊。大きなヒレは3秒周期で、ごく静かに左右へ振る。
for frame in range(1, 182):
    phase = (frame - 1) / 180 * 2 * pi
    for name, *_ in bones:
        bone = rig.pose.bones[name]
        bone.rotation_mode = 'XYZ'
        bone.location, bone.rotation_euler, bone.scale = (0, 0, 0), (0, 0, 0), (1, 1, 1)
        if name == 'body':
            bone.location[1] = .035 * sin(phase)
            bone.rotation_euler[2] = .025 * sin(phase)
        elif name.startswith(('dorsal', 'anal')):
            amount = .10 if name.endswith('tip') else .17
            bone.rotation_euler[0] = amount * sin(phase * 2 - (.4 if name.endswith('tip') else 0))
        elif name == 'clavus':
            bone.rotation_euler[1] = .045 * sin(phase * 2)
        elif name.startswith('pectoral.'):
            bone.rotation_euler[1] = .18 * sin(phase * 2) * (-1 if name.endswith('L') else 1)
        elif name.startswith('eye.'):
            bone.scale[1] = 1 - .93 * max(0, 1 - abs(frame - 103) / 4)
        bone.keyframe_insert('location', frame=frame)
        bone.keyframe_insert('rotation_euler', frame=frame)
        bone.keyframe_insert('scale', frame=frame)
rig.animation_data.action.name = 'Drift'
scene.frame_set(1)

# 配布ファイルには含まれない、確認画像用のスタジオ。
floor_mat = material('Studio floor', (.86, .89, .92), .85)
bpy.ops.mesh.primitive_plane_add(size=200)
bpy.context.object.data.materials.append(floor_mat)
scene.world = bpy.data.worlds.new('Kiabou studio')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.8, .87, .94, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .4
for name, location, energy, size in [('Key', (-.4, -.4, .75), 9, .5),
                                    ('Fill', (.35, -.2, .4), 3, .4), ('Rim', (.1, .4, .65), 12, .4)]:
    light = bpy.data.lights.new(name, 'AREA')
    light.energy, light.size = energy, size
    obj = bpy.data.objects.new(name, light)
    bpy.context.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, .14)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
bpy.ops.object.camera_add(location=(-.32, -.85, .31))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, .14)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type, camera.data.ortho_scale = 'ORTHO', .34
scene.camera = camera
scene.render.engine = 'CYCLES'
scene.cycles.samples, scene.cycles.use_denoising = 48, True
scene.render.resolution_x = scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.view_settings.view_transform, scene.view_settings.exposure = 'AgX', -.35
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'kiabou.blend'))
scene.render.filepath = str(OUT / 'preview.png')
bpy.ops.render.render(write_still=True)
print('KIABOU_CREATED', len(mesh.data.vertices), 'vertices')
