# /Users/mymac/zutsuu/assets/kiabou/export_rest_usdz.py
# 毛布で休むきあぼうを、アプリ用の静止USDZに書き出す。
# ブラウザと同じ寝姿をRealityKitでも表示するため。
# 関連: create_rest.py, kiabou-rest.blend, export_kiabou.py, README.md
from pathlib import Path
import bpy
from pxr import Usd, UsdGeom

root = Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(root / 'kiabou-rest.blend'))
bpy.ops.object.select_all(action='DESELECT')
for name in ['KiabouMesh', 'Resting place', 'Little pillow', 'A blanket from someone']:
    obj = bpy.data.objects[name]
    obj.hide_render = False
    obj.select_set(True)
bpy.ops.wm.usd_export(
    filepath=str(root / 'covered.usdz'), selected_objects_only=True,
    export_animation=False, export_lights=False, export_cameras=False,
    convert_orientation=True, export_global_up_selection='Y',
    export_global_forward_selection='NEGATIVE_Z')
stage = Usd.Stage.Open(str(root / 'covered.usdz'))
assert str(UsdGeom.GetStageUpAxis(stage)) == 'Y'
assert len([p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)]) == 4
print('COVERED_USDZ_VERIFIED')
