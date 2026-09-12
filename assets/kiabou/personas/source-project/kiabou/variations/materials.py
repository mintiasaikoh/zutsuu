# /Users/mymac/zutsuu/assets/kiabou/variations/materials.py
# 共通UVと、着せ替え用の色・模様・布のマテリアルを生成する。
# 原型の形と顔を変えず、色だけ・模様入りを同じ骨格で扱うため。
# 関連: build_variations.py, props.py, ../geometry.py, ASSETS.md
from pathlib import Path
import bpy
import numpy as np

PALETTES = {
    'kasumi': dict(label='かすみ', back=(.08, .15, .23), middle=(.35, .47, .58),
                   fin=(.08, .16, .26), tail=(.33, .45, .56),
                   pillow=(.78, .81, .84), blanket=(.28, .40, .53)),
    'shizuku': dict(label='しずく', back=(.055, .14, .15), middle=(.29, .46, .44),
                    fin=(.06, .17, .18), tail=(.27, .44, .44),
                    pillow=(.49, .67, .64), blanket=(.24, .40, .38)),
    'komorebi': dict(label='こもれび', back=(.15, .19, .20), middle=(.47, .51, .46),
                     fin=(.15, .21, .26), tail=(.40, .47, .46),
                     pillow=(.79, .70, .55), blanket=(.39, .42, .43)),
}


def smooth(value):
    t = np.clip(value, 0, 1)
    return t * t * (3 - 2 * t)


def shader(mat):
    return next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')


def solid_material(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    shader(mat).inputs['Base Color'].default_value = (*color, 1)
    shader(mat).inputs['Roughness'].default_value = .88
    return mat


def paint(mat, name, linear, directory):
    """3D用の模様をUVへ描く。sRGB PNGとパック画像の両方を残す。"""
    height, width = linear.shape[:2]
    rgba = np.ones((height, width, 4), dtype=np.float32)
    rgb = np.clip(linear, 0, 1)
    rgba[:, :, :3] = np.where(rgb <= .0031308, rgb * 12.92, 1.055 * rgb ** (1 / 2.4) - .055)
    image = bpy.data.images.new(name, width=width, height=height, alpha=True)
    image.colorspace_settings.name = 'sRGB'
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = str(directory / (name + '.png'))
    image.file_format = 'PNG'
    image.save()
    image.pack()
    for node in list(mat.node_tree.nodes):
        if node.type == 'TEX_IMAGE':
            mat.node_tree.nodes.remove(node)
    node = mat.node_tree.nodes.new('ShaderNodeTexImage')
    node.image, node.extension = image, 'EXTEND'
    mat.node_tree.links.new(node.outputs['Color'], shader(mat).inputs['Base Color'])
    shader(mat).inputs['Roughness'].default_value = .88


def mix(base, color, amount):
    return base * (1 - amount[..., None]) + np.array(color) * amount[..., None]


def body_texture(family, patterned):
    p = PALETTES[family]
    u, v = np.meshgrid(np.linspace(0, 1, 512), np.linspace(0, 1, 512))
    x, z = -.78 + 1.41 * u, .73 + 1.34 * v
    first, second = smooth((v - .35) / .33), smooth((v - .64) / .27)
    base = mix(mix(np.full((*v.shape, 3), (.92, .95, .97)), p['middle'], first), p['back'], second)
    if not patterned:
        return base
    # 模様は上半身と後方へ。顔の付近には細かな線や色面を足さない。
    if family == 'kasumi':
        edge = 1.81 - .12 * np.sin(2.9 * x + .9)
        band = smooth((z - edge) / .025) * (1 - smooth((z - edge - .095) / .035))
        upper = smooth((z - edge - .18) / .025) * (1 - smooth((z - edge - .265) / .035))
        base = mix(base, (.49, .59, .67), band * .66)
        return mix(base, (.36, .48, .58), upper * .72)
    if family == 'shizuku':
        for cx, cz, rx, rz in [(.21, 1.84, .14, .20), (.47, 1.55, .08, .115)]:
            dy = (z - cz) / rz
            dx = (x - cx + .035 * dy) / rx
            distance = (dx / np.clip(.79 - .28 * dy, .3, 1.4)) ** 2 + dy ** 2
            base = mix(base, (.56, .73, .69), (1 - smooth((distance - .82) / .22)) * .87)
        return base
    sand = ((x + .02) / .48) ** 2 + ((z - 1.985) / .20) ** 2
    leaf = ((x - .37) / .34) ** 2 + ((z - 1.865) / .18) ** 2
    base = mix(base, (.74, .69, .54), (1 - smooth((sand - .65) / .55)) * .85)
    return mix(base, (.47, .59, .47), (1 - smooth((leaf - .60) / .65)) * .82)


def apply_appearance(fish, family, patterned, directory):
    """材質順と頂点を維持し、全バリエーション共通の側面投影UVへ揃える。"""
    palette = PALETTES[family]
    body, fins, tail, face = list(fish.data.materials)
    for mat, name in zip((body, fins, tail, face), ('Body', 'Fins', 'Tail', 'Face')):
        mat.name = 'Kiabou.' + name
    paint(body, 'body', body_texture(family, patterned), directory)
    for mat, key in [(fins, 'fin'), (tail, 'tail')]:
        mat.diffuse_color = (*palette[key], 1)
        shader(mat).inputs['Base Color'].default_value = (*palette[key], 1)
        shader(mat).inputs['Roughness'].default_value = .88
    # 上ヒレの広い帯も画像へ焼き、USDZとGLBで同じ模様にする。
    height = np.linspace(.10, 2.71, 512)[:, None]
    fin_rgb = np.empty((512, 8, 3)); fin_rgb[:] = palette['fin']
    if family == 'kasumi' and patterned:
        band = smooth((height - 2.45) / .018) * (1 - smooth((height - 2.55) / .025))
        fin_rgb = mix(fin_rgb, (.30, .43, .55), np.broadcast_to(band * .72, (512, 8)))
    paint(fins, 'fins', fin_rgb, directory)
    uv = fish.data.uv_layers.active.data
    for poly in fish.data.polygons:
        for index in poly.loop_indices:
            co = fish.data.vertices[fish.data.loops[index].vertex_index].co
            if poly.material_index == 0:
                uv[index].uv = ((co.x + .78) / 1.41, (co.z - .73) / 1.34)
            elif poly.material_index == 1:
                uv[index].uv = (.5, (co.z - .10) / 2.61)


def blanket_material(family, directory):
    palette = PALETTES[family]
    mat = solid_material('Kiabou.Blanket', palette['blanket'])
    u, v = np.meshgrid(np.linspace(0, 1, 256), np.linspace(0, 1, 256))
    rgb = np.empty((256, 256, 3)); rgb[:] = palette['blanket']
    if family == 'kasumi':
        band = smooth((v - .25 - .24 * u) / .018) * (1 - smooth((v - .43 - .24 * u) / .018))
        rgb = mix(rgb, (.56, .64, .70), band)
    elif family == 'komorebi':
        rgb = mix(rgb, (.51, .59, .47), smooth((u - .84) / .016))
    paint(mat, 'blanket', rgb, directory)
    return mat
