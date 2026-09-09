# /Users/mymac/zutsuu/assets/kiabou/variations/verify_assets.py
# 生成済みの全素材を再検査し、分離部品と完成セットの位置を照合する。
# モデルの再生成後も、単位・ループ・着せ替え配置の互換性を確認するため。
# 関連: catalog.json, exporting.py, build_variations.py, ASSETS.md
from pathlib import Path
import json
import struct
import sys
import numpy as np
from pxr import Usd, UsdGeom, Gf

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from exporting import verify_pair


def bounds(stem):
    stage = Usd.Stage.Open(str(stem.with_suffix('.usdz')))
    cache = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_])
    return cache.ComputeWorldBound(stage.GetPseudoRoot()).ComputeAlignedRange()


def animation_samples(stem):
    """GLBの実際のキー配列を読み、骨格の回転・移動・まばたきとループ端を検査。"""
    data = stem.with_suffix('.glb').read_bytes()
    json_size = struct.unpack_from('<I', data, 12)[0]
    gltf = json.loads(data[20:20 + json_size])
    buffer = data[28 + json_size:]

    def accessor(index):
        item = gltf['accessors'][index]
        view = gltf['bufferViews'][item['bufferView']]
        assert item['componentType'] == 5126
        columns = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[item['type']]
        offset = view.get('byteOffset', 0) + item.get('byteOffset', 0)
        return np.ndarray((item['count'], columns), dtype='<f4', buffer=buffer, offset=offset,
                          strides=(view.get('byteStride', columns * 4), 4))

    animation = gltf['animations'][0]
    changed = set()
    for channel in animation['channels']:
        sampler = animation['samplers'][channel['sampler']]
        time, values = accessor(sampler['input']), accessor(sampler['output'])
        assert abs(float(time[-1, 0] - time[0, 0]) - 6) < 1e-5
        assert np.all(np.isfinite(values))
        assert np.allclose(values[0], values[-1], atol=1e-5)
        if np.max(np.abs(values - values[0])) > .001:
            changed.add((gltf['nodes'][channel['target']['node']]['name'], channel['target']['path']))
    assert ('dorsal', 'rotation') in changed and ('anal', 'rotation') in changed
    assert ('body', 'translation') in changed
    assert ('eye.L', 'scale') in changed and ('eye.R', 'scale') in changed


catalog = json.loads((ROOT / 'catalog.json').read_text())
count = 0
for entry in catalog['variants']:
    for kind in ('swim', 'restBody', 'covered'):
        info = entry[kind]
        current = verify_pair(ROOT / info['path'], kind == 'swim')
        assert current == {key: info[key] for key in current}
        count += 1
    animation_samples(ROOT / entry['swim']['path'])
    family = entry['family']
    components = [entry['restBody']['path'], 'shared/bed',
                  f'{family}/accessories/pillow', f'{family}/accessories/blanket']
    union = Gf.Range3d()
    for path in components:
        union.UnionWith(bounds(ROOT / path))
    assembled = bounds(ROOT / entry['covered']['path'])
    assert (union.GetMin() - assembled.GetMin()).GetLength() < 1e-5
    assert (union.GetMax() - assembled.GetMax()).GetLength() < 1e-5
    dimensions = bounds(ROOT / entry['swim']['path']).GetSize()
    assert .20 < dimensions[1] < .32, dimensions
    print('CHECKED', entry['id'], 'loop/motion/origin/scale', flush=True)

for item in catalog['accessories'] + [catalog['bed']]:
    verify_pair(ROOT / item['path'], False)
    count += 1
assert count == 25
print('VERIFIED', count, 'GLB/USDZ pairs; 6 animated characters; 6 interchangeable rest sets', flush=True)
