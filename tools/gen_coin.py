#!/usr/bin/env python3
"""선공 동전 앞면 텍스처: 금화 위에 새긴 고양이 얼굴 (투명 배경 512x512). 뒷면은 텍스처 없이 매끈한 금속.
사용: python3 tools/gen_coin.py → assets/textures/coin_cat.png"""
import math, os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 4 * 512   # 4배로 그린 뒤 축소 (안티앨리어싱)
C = S // 2
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
ink = (92, 58, 10, 255)        # 새김 선 (짙은 금)
hi = (255, 236, 160, 255)      # 새김 가장자리 빛
w = 34

def pt(x, y):
    return (C + x * S / 2, C + y * S / 2)

# 바깥 테두리 고리
for r, col, width in ((0.94, ink, 30), (0.86, ink, 14)):
    d.ellipse([C - r * C, C - r * C, C + r * C, C + r * C], outline=col, width=width)

def cat(dx, dy, col, width):
    off = lambda p: (p[0] + dx, p[1] + dy)
    # 머리 + 귀 (한 붓 외곽선)
    outline = [pt(-0.55, -0.05), pt(-0.52, -0.62), pt(-0.22, -0.36), pt(0.22, -0.36), pt(0.52, -0.62), pt(0.55, -0.05)]
    for i in range(0, 41):
        a = math.radians(i * 180 / 40)
        outline.append(pt(0.55 * math.cos(a), -0.05 + 0.5 * math.sin(a)))
    d.line([off(p) for p in outline] + [off(outline[0])], fill=col, width=width, joint="curve")
    # 귀 안쪽
    for sx in (-1, 1):
        d.line([off(pt(sx * 0.44, -0.30)), off(pt(sx * 0.46, -0.50)), off(pt(sx * 0.28, -0.34))], fill=col, width=width // 2, joint="curve")
    # 눈 (아몬드) + 세로 동공
    for sx in (-1, 1):
        ex, ey = sx * 0.22, -0.02
        box = [off(pt(ex - 0.13, ey - 0.07)), off(pt(ex + 0.13, ey + 0.07))]
        d.ellipse([box[0][0], box[0][1], box[1][0], box[1][1]], outline=col, width=width // 2)
        d.line([off(pt(ex, ey - 0.06)), off(pt(ex, ey + 0.06))], fill=col, width=width)
    # 코 (삼각) + 입
    d.polygon([off(pt(-0.06, 0.16)), off(pt(0.06, 0.16)), off(pt(0, 0.22))], fill=col)
    d.line([off(pt(0, 0.22)), off(pt(0, 0.27))], fill=col, width=width // 2)
    for sx in (-1, 1):
        d.arc([off(pt(sx * 0.11 - 0.11, 0.18))[0], off(pt(0, 0.18))[1], off(pt(sx * 0.11 + 0.11, 0.36))[0], off(pt(0, 0.36))[1]],
              0 if sx > 0 else 0, 180, fill=col, width=width // 2)
    # 수염
    for sx in (-1, 1):
        for k, yy in enumerate((0.16, 0.22, 0.28)):
            d.line([off(pt(sx * 0.16, 0.20 + k * 0.025)), off(pt(sx * 0.62, yy - 0.04 + k * 0.03))], fill=col, width=width // 3)

cat(6, 6, hi, w)      # 빛 받은 새김 가장자리 (오른쪽 아래로 살짝)
cat(0, 0, ink, w)     # 새김 선
img = img.resize((512, 512), Image.LANCZOS)
out = os.path.join(ROOT, "assets", "textures", "coin_cat.png")
img.save(out)
print("saved", out)
