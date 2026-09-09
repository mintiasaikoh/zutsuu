# /Users/mymac/zutsuu/assets/kiabou/personas/build_personas.py
# 5つのキャラクター衣装と、対応する色だけの3D素材を生成する。
# 既存の体形・表情・泳ぎを保った追加着せ替えを配布するため。
# 関連: outfits.py, shapes.py, ../variations/exporting.py, README.md
from pathlib import Path
import json
import sys
import bpy

ROOT = Path(__file__).resolve().parent
sys.path[:0] = [str(ROOT), str(ROOT.parent/'variations'), str(ROOT.parent)]
from outfits import PROFILES, create_outfit
from materials import PALETTES, apply_appearance
from exporting import export_pair, render
from props import freeze_rest_pose, create_props

catalog = {
    '_file': '/Users/mymac/zutsuu/assets/kiabou/personas/catalog.json',
    '_role': 'キャラクター衣装の生成済み素材を列挙する。',
    '_reason': '実装担当が色だけ・衣装付きの正しいモデルを選ぶため。',
    '_related': ['README.md','build_personas.py','outfits.py'],
    'version': 1, 'upAxis': 'Y', 'metersPerUnit': 1, 'personas': [],
}

for family, profile in PROFILES.items():
    directory = ROOT/family
    textures = directory/'textures'
    textures.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(ROOT.parent/'kiabou.blend'))
    scene = bpy.context.scene
    scene.frame_set(1)
    rig, fish = bpy.data.objects['Kiabou'], bpy.data.objects['KiabouMesh']
    original = [tuple(v.co) for v in fish.data.vertices]
    PALETTES[family] = dict(profile, pillow=(.84,.81,.74),
        blanket=tuple(channel*.75+.08 for channel in profile['middle']))
    apply_appearance(fish,family,False,textures)
    entry = dict(id=family,label=profile['label'])
    entry['plain'] = dict(path=f'{family}/plain', **export_pair(directory/'plain',[rig,fish],True))
    render(scene,directory/'plain.png')
    outfit = create_outfit(family,rig,textures)
    assert [tuple(v.co) for v in fish.data.vertices] == original
    assert len(rig.data.bones)==10
    entry['costume'] = dict(path=f'{family}/costume', **export_pair(directory/'costume',[rig,fish,outfit],True))
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(directory/'costume.blend'))
    render(scene,directory/'costume.png')
    # 休む姿では、帽子やチェーンを外す。体の色だけを引き継ぐ。
    outfit.hide_render = True
    fish = freeze_rest_pose(rig,fish)
    bed,pillow,blanket = create_props(family,ROOT.parent/'kiabou-rest.blend',textures)
    entry['covered'] = dict(path=f'{family}/covered',
        **export_pair(directory/'covered',[fish,bed,pillow,blanket]))
    bpy.ops.wm.save_as_mainfile(filepath=str(directory/'rest.blend'))
    render(scene,directory/'covered.png',resting=True)
    catalog['personas'].append(entry)
    print('PERSONA_VERIFIED',family,flush=True)
(ROOT/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
print('ALL_PERSONAS_READY',len(catalog['personas']),flush=True)
