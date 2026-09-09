# /Users/mymac/zutsuu/assets/kiabou/geometry.py
# きあぼうの薄く丸いヒレと、背中から腹への配色を作る。
# ラフのマンボウらしいシルエットを滑らかな立体にするため。
# 関連: create_kiabou.py, export_kiabou.py, kiabou.blend
from math import sqrt
import bpy
import bmesh
import numpy as np
from mathutils import Vector


def smooth(value):
    t = np.clip(value, 0, 1)
    return t * t * (3 - 2 * t)


def body_gradient(body, material):
    v = np.linspace(0, 1, 512)[:, None]
    white, middle, navy = np.array((.92, .95, .97)), np.array((.30, .49, .66)), np.array((.025, .069, .145))
    first, second = smooth((v - .35) / .33), smooth((v - .64) / .27)
    linear = (white * (1 - first) + middle * first) * (1 - second) + navy * second
    rgba = np.ones((512, 8, 4), dtype=np.float32)
    rgba[:, :, :3] = (1.055 * linear ** (1 / 2.4) - .055)[:, None, :]
    image = bpy.data.images.new('Kiabou blue gradient', width=8, height=512, alpha=True)
    image.colorspace_settings.name = 'sRGB'
    image.pixels.foreach_set(rgba.ravel())
    image.pack()
    node = material.node_tree.nodes.new('ShaderNodeTexImage')
    node.image, node.extension = image, 'EXTEND'
    material.node_tree.links.new(node.outputs['Color'], material.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    for loop in body.data.loops:
        z = body.data.vertices[loop.vertex_index].co.z
        body.data.uv_layers.active.data[loop.index].uv = (.5, (z / .67 + 1) / 2)


def side_surface(x, z):
    return .255 * sqrt(max(0, 1 - (x / (.78 if x < 0 else .63)) ** 2 - ((z - 1.4) / .67) ** 2))


def fin(name, outline, center, depth, y_offset, material, finish, bone):
    # 閉曲線をCatmull–Rom補間し、両側の面を膨らませて薄いヒレにする。
    points = []
    controls = [Vector(p) for p in outline]
    for i in range(len(controls)):
        a, b, c, d = [controls[j % len(controls)] for j in [i - 1, i, i + 1, i + 2]]
        for step in range(8):
            t = step / 8
            points.append(.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t ** 2 + (-a + 3 * b - 3 * c + d) * t ** 3))
    vertices, faces = [], []
    n, rings = len(points), 7
    center = Vector(center)
    for sign in [-1, 1]:
        start = len(vertices)
        vertices.append((center.x, y_offset + sign * depth, center.y))
        for ring in range(1, rings + 1):
            radius = ring / rings
            for p in points:
                q = center + (p - center) * radius
                vertices.append((q.x, y_offset + sign * depth * sqrt(max(0, 1 - radius ** 2)), q.y))
            base = start + 1 + (ring - 1) * n
            for j in range(n):
                if ring == 1:
                    faces.append((start, base + j, base + (j + 1) % n))
                else:
                    faces.append((base - n + j, base + j, base + (j + 1) % n, base - n + (j + 1) % n))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    # 表裏の外周を共有して閉じた形状にし、法線方向をそろえる。
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.000001)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, name, material, bone)


def soften_fin_weights(obj, root, tip, base_z, direction):
    root_group = obj.vertex_groups[root]
    tip_group = obj.vertex_groups.new(name=tip)
    body_group = obj.vertex_groups.new(name='body')
    for v in obj.data.vertices:
        height = (v.co.z - base_z) * direction
        root_weight = max(0, min(1, height / .18))
        tip_weight = max(0, min(1, (height - .28) / .40))
        root_group.add([v.index], root_weight * (1 - tip_weight), 'REPLACE')
        tip_group.add([v.index], root_weight * tip_weight, 'REPLACE')
        body_group.add([v.index], 1 - root_weight, 'REPLACE')
