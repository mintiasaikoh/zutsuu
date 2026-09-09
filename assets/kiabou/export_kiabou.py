# /Users/mymac/zutsuu/assets/kiabou/export_kiabou.py
# きあぼうをUSDZとGLBへ書き出し、骨格・動作・テクスチャを検査する。
# アプリ用の素材に、確認画像と同じ配色と泳ぐ動きを持たせるため。
# 関連: create_kiabou.py, geometry.py, index.html, README.md
from pathlib import Path
import json
import struct
import bpy
from pxr import Usd, UsdSkel, UsdGeom

OUT = Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(OUT / 'kiabou.blend'))
rig = bpy.data.objects['Kiabou']
bpy.context.scene.frame_set(1)
first = {bone.name: bone.matrix.copy() for bone in rig.pose.bones}
bpy.context.scene.frame_set(181)
for bone in rig.pose.bones:
    delta = bone.matrix - first[bone.name]
    assert max(abs(value) for row in delta for value in row) < .00001, 'Loop discontinuity'
bpy.context.scene.frame_set(23)
for name in ['dorsal', 'anal']:
    difference = rig.pose.bones[name].matrix.to_quaternion().rotation_difference(first[name].to_quaternion())
    assert abs(difference.angle) > .10, 'Fin animation missing'
bpy.context.scene.frame_set(46)
assert (rig.pose.bones['body'].matrix.translation - first['body'].translation).length > .03
bpy.context.scene.frame_set(1)
bpy.ops.object.select_all(action='DESELECT')
for name in ['Kiabou', 'KiabouMesh']:
    bpy.data.objects[name].select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(filepath=str(OUT / 'kiabou.glb'), export_format='GLB',
                         use_selection=True, export_animations=True, export_frame_range=True,
                         export_animation_mode='ACTIVE_ACTIONS', export_nla_strips_merged_animation_name='Drift')
bpy.ops.wm.usd_export(filepath=str(OUT / 'kiabou.usdz'), selected_objects_only=True,
                      export_animation=True, export_armatures=True, export_lights=False,
                      export_cameras=False, convert_orientation=True,
                      export_global_up_selection='Y', export_global_forward_selection='NEGATIVE_Z')
data = (OUT / 'kiabou.glb').read_bytes()
assert data[:4] == b'glTF'
gltf = json.loads(data[20:20 + struct.unpack_from('<I', data, 12)[0]])
assert gltf['skins'] and gltf['animations'][0]['name'] == 'Drift'
assert len(gltf['images']) == 1
stage = Usd.Stage.Open(str(OUT / 'kiabou.usdz'))
animations = [UsdSkel.Animation(p) for p in stage.Traverse() if p.IsA(UsdSkel.Animation)]
assert animations and animations[0].GetRotationsAttr().GetNumTimeSamples() > 1
assert str(UsdGeom.GetStageUpAxis(stage)) == 'Y'
mesh = bpy.data.objects['KiabouMesh'].data
print('VERIFIED', json.dumps({
    'glb_bytes': len(data), 'usdz_bytes': (OUT / 'kiabou.usdz').stat().st_size,
    'vertices': len(mesh.vertices), 'triangles': sum(len(p.vertices) - 2 for p in mesh.polygons),
    'bones': len(rig.data.bones), 'seconds': 6, 'animation': 'Drift', 'loop_and_motion': 'passed'
}, indent=2))
