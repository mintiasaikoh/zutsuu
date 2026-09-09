# /Users/mymac/zutsuu/assets/kiabou/variations/build_variations.py
# 色3種×模様の有無のきあぼうと、交換可能な寝具をまとめて生成する。
# 編集用原本・アプリ用素材・確認画像を再現可能な手順で揃えるため。
# 関連: materials.py, props.py, exporting.py, ASSETS.md
from pathlib import Path
import hashlib
import json
import sys
import bpy

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from materials import PALETTES, apply_appearance
from props import freeze_rest_pose, create_props
from exporting import export_pair, render

catalog = {
    '_file': '/Users/mymac/zutsuu/assets/kiabou/variations/catalog.json',
    '_role': '生成した着せ替え素材のパスと構造を列挙する。',
    '_reason': '実装担当が存在する素材だけを読み込めるようにするため。',
    '_related': ['ASSETS.md', 'build_variations.py', 'index.html'],
    'version': 1, 'upAxis': 'Y', 'metersPerUnit': 1,
    'variants': [], 'accessories': [],
}
geometry_hash = None

for family, palette in PALETTES.items():
    for patterned in (False, True):
        style = 'pattern' if patterned else 'plain'
        directory = ROOT / family / style
        textures = directory / 'textures'
        textures.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.open_mainfile(filepath=str(ROOT.parent / 'kiabou.blend'))
        scene = bpy.context.scene
        scene.frame_set(1)
        rig, fish = bpy.data.objects['Kiabou'], bpy.data.objects['KiabouMesh']
        apply_appearance(fish, family, patterned, textures)
        # 色・模様を選び直しても形、UV、骨格の重みが変わらない。
        contract = [(tuple(v.co), [(g.group, g.weight) for g in v.groups]) for v in fish.data.vertices]
        contract += [tuple(uv.uv) for uv in fish.data.uv_layers.active.data]
        digest = hashlib.sha256(repr(contract).encode()).hexdigest()
        if geometry_hash is None:
            geometry_hash = digest
        assert digest == geometry_hash, 'Geometry or UV differs between appearances'
        first = {b.name: b.matrix.copy() for b in rig.pose.bones}
        scene.frame_set(181)
        for bone in rig.pose.bones:
            assert max(abs(value) for row in bone.matrix - first[bone.name] for value in row) < 1e-5
        scene.frame_set(23)
        for name in ('dorsal', 'anal'):
            assert abs(rig.pose.bones[name].matrix.to_quaternion().rotation_difference(
                first[name].to_quaternion()).angle) > .1
        scene.frame_set(1)
        entry = dict(id=f'{family}-{style}', family=family, label=palette['label'], style=style)
        entry['swim'] = dict(path=f'{family}/{style}/swim', **export_pair(directory / 'swim', [rig, fish], True))
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(directory / 'swim.blend'))
        render(scene, directory / 'swim.png')

        fish = freeze_rest_pose(rig, fish)
        entry['restBody'] = dict(path=f'{family}/{style}/rest-body',
                                 **export_pair(directory / 'rest-body', [fish]))
        props_directory = ROOT / family / 'accessories'
        props_directory.mkdir(parents=True, exist_ok=True)
        bed, pillow, blanket = create_props(family, ROOT.parent / 'kiabou-rest.blend', props_directory)
        if not patterned:
            for kind, obj in [('pillow', pillow), ('blanket', blanket)]:
                catalog['accessories'].append(dict(id=f'{family}-{kind}', kind=kind,
                    path=f'{family}/accessories/{kind}', **export_pair(props_directory / kind, [obj])))
            if family == 'kasumi':
                catalog['bed'] = dict(path='shared/bed', **export_pair(ROOT / 'shared' / 'bed', [bed]))
        entry['covered'] = dict(path=f'{family}/{style}/covered',
                                **export_pair(directory / 'covered', [fish, bed, pillow, blanket]))
        bpy.ops.wm.save_as_mainfile(filepath=str(directory / 'rest.blend'))
        render(scene, directory / 'covered.png', resting=True)
        catalog['variants'].append(entry)
        print('VARIANT_VERIFIED', entry['id'], flush=True)

catalog['sharedGeometryUVHash'] = geometry_hash
(ROOT / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
print('ALL_VARIATIONS_READY', len(catalog['variants']), flush=True)
