# /Users/mymac/zutsuu/assets/kiabou/personas/shapes.py
# きあぼうの体に合う小物の基本形を作り、共通の骨格へ接続する。
# 顔と原型メッシュを変更せず、衣装も泳ぐ動きに追従させるため。
# 関連: outfits.py, build_personas.py, ../geometry.py, README.md
from math import sin, cos, pi
import bpy
import bmesh
from mathutils import Vector


class Outfit:
    def __init__(self):
        self.parts = []

    def finish(self, obj, name, mat):
        obj.name = name
        obj.data.materials.append(mat)
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        self.parts.append(obj)
        return obj

    def oval(self, name, location, scale, mat):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=20, location=location)
        obj = bpy.context.object
        obj.scale = scale
        return self.finish(obj, name, mat)

    def box(self, name, location, scale, mat):
        bpy.ops.mesh.primitive_cube_add(size=2, location=location)
        obj = bpy.context.object
        obj.scale = scale
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        modifier = obj.modifiers.new('Soft corners', 'BEVEL')
        modifier.width, modifier.segments = .028, 3
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        return self.finish(obj, name, mat)

    def line(self, name, points, radius, mat):
        curve = bpy.data.curves.new(name, 'CURVE')
        curve.dimensions, curve.resolution_u = '3D', 12
        curve.bevel_depth, curve.bevel_resolution = radius, 3
        spline = curve.splines.new('BEZIER')
        spline.bezier_points.add(len(points) - 1)
        for point, coordinate in zip(spline.bezier_points, points):
            point.co = coordinate
            point.handle_left_type = point.handle_right_type = 'AUTO'
        obj = bpy.data.objects.new(name, curve)
        bpy.context.collection.objects.link(obj)
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target='MESH')
        return self.finish(bpy.context.object, name, mat)

    def ring(self, name, location, radius, thickness, mat):
        bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=thickness,
            major_segments=20, minor_segments=10, location=location, rotation=(pi/2,0,0))
        return self.finish(bpy.context.object,name,mat)

    def badge(self, name, location, radius, depth, mat, heart=False):
        points = []
        count = 64 if heart else 10
        for i in range(count):
            t = 2 * pi * i / count
            if heart:
                x = sin(t) ** 3
                z = (13 * cos(t) - 5 * cos(2*t) - 2 * cos(3*t) - cos(4*t)) / 16
            else:
                r = 1 if i % 2 == 0 else .48
                x, z = r * sin(t), r * cos(t)
            points.append((x * radius, z * radius))
        cx, cy, cz = location
        vertices = [(cx+x, cy+y, cz+z) for y in [-depth/2, depth/2] for x, z in points]
        faces = [tuple(reversed(range(count))), tuple(range(count, count*2))]
        faces += [(i, (i+1)%count, (i+1)%count+count, i+count) for i in range(count)]
        obj = self.mesh(name, vertices, faces, mat)
        modifier = obj.modifiers.new('Rounded edge', 'BEVEL')
        modifier.width, modifier.segments = .008, 3
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        return obj

    def mesh(self, name, vertices, faces, mat):
        data = bpy.data.meshes.new(name)
        data.from_pydata(vertices, [], faces)
        data.update()
        bm = bmesh.new(); bm.from_mesh(data)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(data); bm.free()
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        return self.finish(obj, name, mat)

    def cloth(self, name, x0, x1, z0, z1, mat, side=-1):
        from geometry import side_surface
        vertices, faces = [], []
        nx, nz = 18, 14
        for i in range(nx+1):
            x = x0 + (x1-x0) * i/nx
            for j in range(nz+1):
                z = z0 + (z1-z0) * j/nz
                y = side * (side_surface(x, z) + .038 + .012 * sin(i/nx*pi*3) * (1-j/nz))
                vertices.append((x, y, z))
                if i<nx and j<nz:
                    a = i*(nz+1)+j
                    faces.append((a, a+nz+1, a+nz+2, a+1))
        obj = self.mesh(name, vertices, faces, mat)
        modifier = obj.modifiers.new('Cloth thickness', 'SOLIDIFY')
        modifier.thickness = .018
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        return obj

    def bind(self, rig):
        bpy.ops.object.select_all(action='DESELECT')
        for obj in self.parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = self.parts[0]
        bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = 'KiabouOutfit'
        group = obj.vertex_groups.new(name='body')
        group.add(list(range(len(obj.data.vertices))), 1, 'REPLACE')
        obj.parent = rig
        modifier = obj.modifiers.new('Follow the body', 'ARMATURE')
        modifier.object = rig
        return obj
