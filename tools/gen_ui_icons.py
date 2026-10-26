#!/usr/bin/env python3
"""하단 HUD 아이콘 (흰색 글리프, 투명 배경 128x128): 자리 이동·기본 공격·강공격·응급 처치·독려·필살기.
사용: python3 tools/gen_ui_icons.py → assets/textures/ui_<id>.png"""
import math, os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 512
W = (245, 245, 245, 255)


def save(img, name):
    # 글리프를 정가운데로 (위/아래·좌/우 여백 대칭)
    b = img.split()[3].getbbox()
    g = img.crop(b)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(g, ((S - g.width) // 2, (S - g.height) // 2))
    out.resize((128, 128), Image.LANCZOS).save(os.path.join(ROOT, "assets", "textures", f"ui_{name}.png"))


def canvas():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def arrow(d, a, b, w=34, head=70):
    d.line([a, b], fill=W, width=w)
    ang = math.atan2(b[1] - a[1], b[0] - a[0])
    p1 = (b[0] + head * 0.9 * math.cos(ang), b[1] + head * 0.9 * math.sin(ang))
    p2 = (b[0] + head * math.cos(ang + 2.4), b[1] + head * math.sin(ang + 2.4))
    p3 = (b[0] + head * math.cos(ang - 2.4), b[1] + head * math.sin(ang - 2.4))
    d.polygon([p1, p2, p3], fill=W)


# 자리 이동: 엇갈린 양방향 화살표
im, d = canvas()
arrow(d, (110, 190), (360, 190))
arrow(d, (402, 322), (152, 322))
save(im, "move")

# 기본 공격: 칼날 한 줄 베기
im, d = canvas()
d.polygon([(120, 400), (380, 112), (412, 100), (400, 132), (140, 420)], fill=W)
d.line([(96, 340), (180, 424)], fill=W, width=34)
d.line([(108, 412), (70, 450)], fill=W, width=30)
save(im, "basic_attack")

# 강공격: 세 줄 베기 자국
im, d = canvas()
for k in (-1, 0, 1):
    o = k * 92
    d.polygon([(130 + o, 430 + o * 0.0), (360 + o, 90), (392 + o, 98), (170 + o, 440)], fill=W)
save(im, "heavy_attack")

# 응급 처치: 십자
im, d = canvas()
d.rounded_rectangle([196, 80, 316, 432], radius=26, fill=W)
d.rounded_rectangle([80, 196, 432, 316], radius=26, fill=W)
save(im, "heal")

# 독려: 위로 겹친 갈매기 세 개
im, d = canvas()
for k, y in enumerate((150, 260, 370)):
    d.line([(110, y + 70), (256, y - 40), (402, y + 70)], fill=W, width=46, joint="curve")
save(im, "rally")

# 필살기: 여덟 갈래 별 폭발
im, d = canvas()
pts = []
for i in range(16):
    r = 220 if i % 2 == 0 else 86
    a = math.radians(-90 + i * 22.5)
    pts.append((256 + r * math.cos(a), 256 + r * math.sin(a)))
d.polygon(pts, fill=W)
save(im, "ultimate")
print("icons saved")
