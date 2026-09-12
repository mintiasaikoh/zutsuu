# /Users/mymac/zutsuu/assets/kiabou/personas/verify_personas.py
# 5種類の衣装について、原型維持・骨格追従・ループ・同梱素材を検査する。
# 小物の追加が体の形やアニメーションを壊していないことを確認するため。
# 関連: build_personas.py, catalog.json, ../variations/exporting.py, README.md
from pathlib import Path
import json
import struct
import sys
import numpy as np
from pxr import Usd,UsdGeom

ROOT = Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'variations'))
from exporting import verify_pair


def read_glb(stem):
    data=stem.with_suffix('.glb').read_bytes()
    size=struct.unpack_from('<I',data,12)[0]
    return json.loads(data[20:20+size]),data[28+size:]


def samples(gltf,buffer,index):
    a=gltf['accessors'][index]; view=gltf['bufferViews'][a['bufferView']]
    dtype={5126:'<f4',5123:'<u2',5121:'u1'}[a['componentType']]
    cols={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    width=np.dtype(dtype).itemsize
    return np.ndarray((a['count'],cols),dtype=dtype,buffer=buffer,
        offset=view.get('byteOffset',0)+a.get('byteOffset',0),
        strides=(view.get('byteStride',cols*width),width))


def body_attributes(gltf,buffer):
    node=next(n for n in gltf['nodes'] if n.get('name')=='KiabouMesh')
    return [[samples(gltf,buffer,p['attributes'][a]) for a in ('POSITION','NORMAL','TEXCOORD_0','JOINTS_0','WEIGHTS_0')]
            for p in gltf['meshes'][node['mesh']]['primitives']]


catalog=json.loads((ROOT/'catalog.json').read_text())
assert len(catalog['personas'])==5
for item in catalog['personas']:
    for kind in ('plain','costume','covered'):
        info=item[kind]; stem=ROOT/info['path']
        result=verify_pair(stem,kind!='covered')
        assert result=={key:info[key] for key in result}
        if kind=='covered':
            continue
        gltf,buffer=read_glb(stem)
        assert all(len(skin['joints'])==10 for skin in gltf['skins'])
        changed=set()
        animation=gltf['animations'][0]
        for channel in animation['channels']:
            sampler=animation['samplers'][channel['sampler']]
            time,values=[samples(gltf,buffer,sampler[k]) for k in ('input','output')]
            assert abs(float(time[-1,0]-time[0,0])-6)<1e-5
            assert np.all(np.isfinite(values)) and np.allclose(values[0],values[-1],atol=1e-5)
            if np.max(abs(values-values[0]))>.001:
                changed.add((gltf['nodes'][channel['target']['node']]['name'],channel['target']['path']))
        for target in [('body','translation'),('dorsal','rotation'),('anal','rotation'),('eye.L','scale')]:
            assert target in changed
        stage=Usd.Stage.Open(str(stem.with_suffix('.usdz')))
        extent=UsdGeom.BBoxCache(Usd.TimeCode.Default(),['default']).ComputeWorldBound(stage.GetPseudoRoot()).ComputeAlignedRange()
        assert .20<extent.GetSize()[1]<.34
    base,bb=read_glb(ROOT/item['plain']['path'])
    dressed,db=read_glb(ROOT/item['costume']['path'])
    for plain,clothed in zip(body_attributes(base,bb),body_attributes(dressed,db),strict=True):
        for a,b in zip(plain,clothed,strict=True):
            assert np.array_equal(a,b), 'Body changed by outfit'
    node=next(n for n in dressed['nodes'] if n.get('name')=='KiabouOutfit')
    assert 'skin' in node
    skin=dressed['skins'][node['skin']]
    body_index=next(i for i,n in enumerate(skin['joints']) if dressed['nodes'][n]['name']=='body')
    for p in dressed['meshes'][node['mesh']]['primitives']:
        joints=samples(dressed,db,p['attributes']['JOINTS_0'])
        weights=samples(dressed,db,p['attributes']['WEIGHTS_0'])
        assert np.all(joints[weights>0]==body_index), 'Outfit does not follow body'
        assert np.allclose(weights.sum(axis=1),1)
    print('CHECKED',item['id'],'body unchanged / outfit bound / 6s loop / textures / size',flush=True)
print('VERIFIED 15 GLB/USDZ pairs; 5 personas, 10 animated models, 5 resting models',flush=True)
