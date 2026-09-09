# /Users/mymac/zutsuu/assets/kiabou/variations/exporting.py
# 素材をGLB・USDZに書き出し、構造と同梱データを検査する。
# カメラや照明の混入、骨格・アニメーションの欠落を出荷前に見つけるため。
# 関連: build_variations.py, materials.py, catalog.json, ASSETS.md
import json
import struct
import tempfile
import zipfile
from pathlib import Path
import bpy
from pxr import Usd, UsdGeom, UsdSkel, UsdUtils, Sdf


def export_pair(stem, objects, animated=False):
    stem.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(stem.with_suffix('.glb')), export_format='GLB', use_selection=True,
        export_animations=animated, export_frame_range=True,
        export_animation_mode='ACTIVE_ACTIONS', export_nla_strips_merged_animation_name='Drift')
    bpy.ops.wm.usd_export(
        filepath=str(stem.with_suffix('.usdz')), selected_objects_only=True,
        export_animation=animated, export_armatures=animated,
        export_lights=False, export_cameras=False, convert_orientation=True,
        export_global_up_selection='Y', export_global_forward_selection='NEGATIVE_Z')
    if animated:
        set_usdz_initial_pose(stem.with_suffix('.usdz'))
    return verify_pair(stem, animated)


def set_usdz_initial_pose(path):
    """Blenderは動くXformの既定値を省く。停止中も開始フレームと同じ姿にする。"""
    with tempfile.TemporaryDirectory(prefix='kiabou-usdz-') as folder:
        with zipfile.ZipFile(path) as archive:
            layer_name = archive.namelist()[0]
            archive.extractall(folder)
        layer_path = Path(folder) / layer_name
        stage = Usd.Stage.Open(str(layer_path))
        for prim in stage.Traverse():
            for attr in prim.GetAttributes():
                times = attr.GetTimeSamples()
                if times and attr.Get(Usd.TimeCode.Default()) is None:
                    attr.Set(attr.Get(times[0]), Usd.TimeCode.Default())
        stage.GetRootLayer().Save()
        package = Path(folder) / 'normalized.usdz'
        assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer_path)), str(package))
        path.write_bytes(package.read_bytes())


def verify_pair(stem, animated):
    data = stem.with_suffix('.glb').read_bytes()
    assert data[:4] == b'glTF'
    gltf = json.loads(data[20:20 + struct.unpack_from('<I', data, 12)[0]])
    assert not gltf.get('cameras') and not gltf.get('extensions', {}).get('KHR_lights_punctual')
    assert all('bufferView' in image for image in gltf.get('images', [])), 'External texture'
    if animated:
        assert len(gltf['skins'][0]['joints']) == 10
        assert gltf['animations'][0]['name'] == 'Drift'
    else:
        assert not gltf.get('animations') and not gltf.get('skins')
    stage = Usd.Stage.Open(str(stem.with_suffix('.usdz')))
    assert str(UsdGeom.GetStageUpAxis(stage)) == 'Y'
    assert abs(UsdGeom.GetStageMetersPerUnit(stage) - 1) < 1e-6
    assert not any(p.IsA(UsdGeom.Camera) for p in stage.Traverse())
    for prim in stage.Traverse():
        for attribute in prim.GetAttributes():
            value = attribute.Get()
            if isinstance(value, Sdf.AssetPath) and value.path:
                assert value.resolvedPath.startswith(str(stem.with_suffix('.usdz')) + '['), 'External USD texture'
    animations = [UsdSkel.Animation(p) for p in stage.Traverse() if p.IsA(UsdSkel.Animation)]
    if animated:
        assert animations and animations[0].GetRotationsAttr().GetNumTimeSamples() > 1
        for prim in stage.Traverse():
            for attribute in prim.GetAttributes():
                if attribute.GetNumTimeSamples():
                    assert attribute.Get(Usd.TimeCode.Default()) is not None
        attr = animations[0].GetRotationsAttr()
        times = attr.GetTimeSamples()
        # 元の6秒ループの端が、USDにもそのまま残っていることを確認。
        first, last = attr.Get(times[0]), attr.Get(times[-1])
        for a, b in zip(first, last):
            assert abs(a.GetReal() - b.GetReal()) < 1e-4
            assert (a.GetImaginary() - b.GetImaginary()).GetLength() < 1e-4
    else:
        assert not animations
    return dict(glbBytes=len(data), usdzBytes=stem.with_suffix('.usdz').stat().st_size,
                meshes=len(gltf['meshes']), materials=len(gltf.get('materials', [])),
                animations=len(gltf.get('animations', [])))


def render(scene, path, resting=False):
    from mathutils import Vector
    target = Vector((0, 0, .025 if resting else .14))
    scene.camera.location = (-.34, -.44, .42) if resting else (-.32, -.85, .31)
    scene.camera.rotation_euler = (target - scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera.data.ortho_scale = .36 if resting else .34
    scene.render.resolution_x = scene.render.resolution_y = 760
    scene.cycles.samples = 24
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
