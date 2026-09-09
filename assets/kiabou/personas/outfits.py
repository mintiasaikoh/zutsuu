# /Users/mymac/zutsuu/assets/kiabou/personas/outfits.py
# ぎゃる・ぱんく・喫茶店員・魔法使い・らっぱーの衣装を定義する。
# 色だけの差ではなく、小物の形からもキャラクターが分かるようにするため。
# 関連: shapes.py, build_personas.py, ../variations/materials.py, README.md
from math import sin, cos, pi
import numpy as np
from shapes import Outfit
from materials import solid_material, paint

PROFILES = {
    'gyaru': dict(label='ぎゃる', back=(.37,.09,.16), middle=(.74,.40,.49),
                  fin=(.50,.18,.28), tail=(.71,.44,.51)),
    'punk': dict(label='ぱんく', back=(.075,.055,.13), middle=(.34,.27,.45),
                 fin=(.16,.10,.23), tail=(.42,.33,.50)),
    'cafe': dict(label='喫茶店員', back=(.16,.095,.055), middle=(.55,.40,.27),
                 fin=(.25,.14,.09), tail=(.59,.46,.34)),
    'mage': dict(label='魔法使い', back=(.035,.055,.14), middle=(.23,.31,.52),
                 fin=(.055,.09,.25), tail=(.30,.39,.59)),
    'rapper': dict(label='らっぱー', back=(.045,.065,.065), middle=(.27,.35,.33),
                   fin=(.065,.105,.10), tail=(.35,.44,.40)),
}


def gyaru(outfit, directory):
    petal = solid_material('Outfit.Flower', (.97,.65,.72))
    gold = solid_material('Outfit.Honey', (.85,.58,.23))
    pink = solid_material('Outfit.Rose', (.65,.18,.33))
    for i in range(5):
        t = 2*pi*i/5
        outfit.oval('Flower petal', (-.05+.105*sin(t), -.18, 2.02+.105*cos(t)),
                         (.079,.034,.079), petal)
    outfit.oval('Flower center', (-.05,-.222,2.02), (.06,.035,.06), gold)
    frame = solid_material('Outfit.SunglassesFrame', (.92,.86,.72))
    lens = solid_material('Outfit.SunglassesLens', (.045,.052,.068))
    for x,z in [(-.48,1.855),(-.26,1.885)]:
        outfit.oval('Sunglasses frame', (x,-.215,z), (.105,.025,.060), frame)
        outfit.oval('Matte lens', (x,-.241,z), (.078,.012,.038), lens)
    outfit.line('Sunglasses bridge', [(-.385,-.22,1.86),(-.37,-.235,1.88),(-.355,-.22,1.88)], .013, frame)
    outfit.badge('Heart pouch', (.095,-.33,1.16), .18, .085, pink, heart=True)
    outfit.line('Pouch strap', [(-.12,-.15,1.96),(-.20,-.255,1.73),(-.11,-.30,1.46),(.09,-.32,1.29)], .017, gold)


def punk(outfit, directory):
    silver = solid_material('Outfit.Pewter', (.52,.56,.63))
    plum = solid_material('Outfit.Plum', (.24,.13,.30))
    outfit.badge('Star pin', (-.20,-.19,2.015), .135, .04, silver)
    check = solid_material('Outfit.Check', (.22,.12,.29))
    y, x = np.indices((128,128))
    light = ((x//32+y//32)%2).astype(float)
    rgb = np.array((.15,.08,.19))*(1-light[:,:,None]) + np.array((.38,.25,.43))*light[:,:,None]
    paint(check, 'check', rgb, directory)
    outfit.box('Check pouch', (.10,-.33,1.17), (.18,.055,.125), check)
    outfit.line('Soft belt', [(-.41,-.19,1.14),(-.17,-.27,1.18),(.10,-.30,1.28),(.37,-.20,1.37)], .021, plum)
    for x in [-.015,.08,.175]:
        outfit.oval('Rounded stud', (x,-.393,1.25), (.019,.014,.019), silver)


def cafe(outfit, directory):
    cocoa = solid_material('Outfit.Cocoa', (.16,.075,.035))
    linen = solid_material('Outfit.Linen', (.74,.65,.48))
    cream = solid_material('Outfit.Cream', (.93,.85,.67))
    outfit.oval('Beret', (-.28,0,2.055), (.30,.255,.12), cocoa)
    outfit.oval('Beret tip', (-.32,.025,2.178), (.022,.022,.035), cocoa)
    outfit.cloth('Apron', -.35,.32,.91,1.27, linen)
    outfit.line('Apron neck loop', [(-.34,-.22,1.27),(-.14,-.27,1.49),(.08,-.30,1.52),(.30,-.23,1.27)], .016, linen)
    outfit.oval('Apron badge', (-.12,-.292,1.18), (.065,.016,.065), cream)
    outfit.oval('Coffee bean', (-.12,-.312,1.18), (.024,.012,.040), cocoa)


def mage(outfit, directory):
    night = solid_material('Outfit.Night', (.09,.07,.25))
    silver = solid_material('Outfit.Moonlight', (.64,.68,.81))
    cape = solid_material('Outfit.Cape', (.19,.16,.37))
    outfit.oval('Hat brim', (-.31,0,2.055), (.33,.28,.042), night)
    vertices, faces = [], []
    # 曲がった先端。上下ヒレを帽子へ取り替えず、前頭部に小さく載せる。
    for j in range(13):
        t = j/12
        r = max(.006,.255*(1-t))
        for i in range(48):
            theta = 2*pi*i/48
            vertices.append((-.31-.20*t*t+r*cos(theta), r*.82*sin(theta), 2.075+.60*t))
            if j<12:
                a=j*48+i; b=j*48+(i+1)%48
                faces.append((a,b,b+48,a+48))
    faces += [tuple(reversed(range(48))), tuple(range(12*48,13*48))]
    outfit.mesh('Bent hat', vertices, faces, night)
    outfit.badge('Hat star', (-.38,-.174,2.27), .071, .018, silver)
    for side in [-1,1]:
        outfit.cloth('Short cape', .30,.73,1.04,1.80,cape,side)
    outfit.oval('Cape clasp', (.30,-.225,1.76), (.045,.021,.045), silver)


def create_outfit(family, rig, directory):
    outfit = Outfit()
    {'gyaru': gyaru, 'punk': punk, 'cafe': cafe, 'mage': mage, 'rapper': rapper}[family](outfit, directory)
    return outfit.bind(rig)


def rapper(outfit, directory):
    from geometry import side_surface
    charcoal = solid_material('Outfit.Charcoal', (.045,.060,.060))
    gold = solid_material('Outfit.Brass', (.59,.38,.13))
    record = solid_material('Outfit.Record', (.022,.030,.032))
    label = solid_material('Outfit.RecordLabel', (.57,.67,.55))
    outfit.oval('Cap crown', (-.28,0,2.055), (.29,.25,.16), charcoal)
    outfit.oval('Sideways cap brim', (-.34,-.235,2.03), (.31,.205,.024), charcoal)
    outfit.oval('Cap button', (-.28,0,2.22), (.026,.026,.015), gold)
    for i in range(17):
        x = -.40 + .78*i/16
        z = 1.23 + .96*(x+.015)**2
        y = -side_surface(x,z)-.058
        outfit.ring('Chain link', (x,y,z), .033,.012,gold)
    outfit.oval('Record pendant', (-.02,-.335,1.095), (.099,.026,.099), record)
    outfit.ring('Record rim', (-.02,-.353,1.095), .096,.009,gold)
    outfit.oval('Record label', (-.02,-.365,1.095), (.042,.009,.042), label)
