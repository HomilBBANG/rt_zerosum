#!/usr/bin/env python3
"""2D 카툰 캐릭터/무기/배경 스프라이트 + 4(5)단계 광역 마스크 생성기.

사용: python3 tools/gen_sprites.py  (출력: assets/sprites, assets/textures)

마스크 코드 (cel_zoned_lighting.gdshader v0.3):
  0 = 그림자, 85 = 주변광, 128 = 고유색 유지(눈 등), 170 = 주조명(key), 255 = 보조광/림(accent)
"""
import json
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_SPR = os.path.join(ROOT, "assets", "sprites")
OUT_TEX = os.path.join(ROOT, "assets", "textures")
os.makedirs(OUT_SPR, exist_ok=True)
os.makedirs(OUT_TEX, exist_ok=True)

S = 4                     # supersample
PX = 1                    # 선 굵기 배율 (배경을 2배 해상도로 그릴 때 2)
W, H = 256, 512           # 1x canvas
LINE = (24, 18, 26, 255)  # outline color
LW = 3                    # outline width at 1x

Z_SHADOW, Z_AMBIENT, Z_UNLIT, Z_KEY, Z_ACCENT = 0, 85, 128, 170, 255


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(c, f):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))), max(0, min(255, int(c[2] * f))), c[3])


def sc(p):
    """scale point/sequence to supersampled coords"""
    if isinstance(p, (int, float)):
        return p * S
    return [(x * S, y * S) for x, y in p]


class Canvas:
    def __init__(self, w=W, h=H):
        self.img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)
        self.body_alpha = None  # body-only silhouette for mask splitting

    def poly(self, pts, fill, outline=LINE, lw=LW):
        self.d.polygon(sc(pts), fill=fill, outline=outline if lw > 0 else None, width=int(lw * S * PX) if lw > 0 else 0)

    def ellipse(self, box, fill, outline=LINE, lw=LW):
        x0, y0, x1, y1 = box
        self.d.ellipse([x0 * S, y0 * S, x1 * S, y1 * S], fill=fill, outline=outline if lw > 0 else None, width=int(lw * S * PX) if lw > 0 else 0)

    def rrect(self, box, r, fill, outline=LINE, lw=LW):
        x0, y0, x1, y1 = box
        self.d.rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=r * S, fill=fill, outline=outline if lw > 0 else None, width=int(lw * S * PX) if lw > 0 else 0)

    def line(self, pts, fill, w):
        self.d.line(sc(pts), fill=fill, width=int(w * S * PX), joint="curve")

    def thick_limb(self, pts, w, fill, outline=LINE, lw=LW):
        """rounded polyline with outline: draw outline pass then fill pass with round caps"""
        for color, width in ((outline, w + lw * 2), (fill, w)):
            self.d.line(sc(pts), fill=color, width=int(width * S), joint="curve")
            for (x, y) in pts:
                r = width / 2
                self.d.ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=color)

    def arc(self, box, start, end, fill, w):
        x0, y0, x1, y1 = box
        self.d.arc([x0 * S, y0 * S, x1 * S, y1 * S], start, end, fill=fill, width=int(w * S))

    def multiply_region(self, mask_draw_fn, factor=0.78):
        """darken region defined by drawing into a mask (baked cel self-shadow)"""
        m = Image.new("L", self.img.size, 0)
        md = ImageDraw.Draw(m)
        mask_draw_fn(md)
        m = ImageChops.multiply(m, self.img.split()[3])
        dark = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        r, g, b, a = self.img.split()
        darkened = Image.merge("RGBA", (r.point(lambda v: int(v * factor)), g.point(lambda v: int(v * factor)), b.point(lambda v: int(v * factor)), a))
        self.img = Image.composite(darkened, self.img, m)
        self.d = ImageDraw.Draw(self.img)

    def snapshot_alpha(self):
        self.body_alpha = self.img.split()[3].copy()

    def down(self):
        return self.img.resize((self.img.width // S, self.img.height // S), Image.LANCZOS)


# ------------------------------------------------------------------ character parts
def egg_points(cx, cy, rx, ry, n=64, chin=0.22):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        s = math.sin(t)
        f = 1.0 - chin * (max(0.0, s) ** 1.3)
        pts.append((cx + rx * math.cos(t) * f, cy + ry * s))
    return pts


def draw_hair_back(c, style, hair, cx, head_top, head_cy, rx, ry):
    dark = shade(hair, 0.82)
    if style == "bald":
        return
    if style == "long":
        c.poly([(cx - rx - 8, head_cy - 10), (cx + rx + 8, head_cy - 10), (cx + rx + 16, head_cy + 120), (cx + rx - 4, head_cy + 128),
                (cx - rx + 4, head_cy + 128), (cx - rx - 16, head_cy + 120)], dark)
    elif style == "bob":
        c.poly([(cx - rx - 8, head_cy - 20), (cx + rx + 8, head_cy - 20), (cx + rx + 10, head_cy + 52), (cx - rx - 10, head_cy + 52)], dark)
    elif style == "ponytail":
        c.poly([(cx + rx - 10, head_cy - 30), (cx + rx + 14, head_cy - 34), (cx + rx + 26, head_cy + 40), (cx + rx + 30, head_cy + 110),
                (cx + rx + 12, head_cy + 112), (cx + rx + 2, head_cy + 50)], dark)
    # back cap behind head (slightly larger than head)
    c.ellipse((cx - rx - 6, head_top - 8, cx + rx + 6, head_cy + 20), dark)


def draw_hair_front(c, style, hair, cx, head_top, head_cy, rx, ry):
    top = head_top - 2
    if style == "bald":
        # helmet
        c.poly([(cx - rx - 10, head_cy - 4), (cx - rx - 8, head_cy - 40), (cx - rx + 10, top - 14), (cx, top - 22), (cx + rx - 10, top - 14),
                (cx + rx + 8, head_cy - 40), (cx + rx + 10, head_cy - 4)], hexc("#4b5a3c"))
        c.poly([(cx - rx - 12, head_cy - 4), (cx + rx + 12, head_cy - 4), (cx + rx + 12, head_cy + 6), (cx - rx - 12, head_cy + 6)], hexc("#36412c"))
        return
    if style == "spiky":
        base = [(cx - rx - 4, head_cy - 2)]
        spikes = [(-44, -30), (-36, -62), (-22, -40), (-10, -74), (4, -44), (16, -78), (30, -42), (40, -66), (48, -30)]
        for dx, dy in spikes:
            base.append((cx + dx, top + dy + 30))
        base.append((cx + rx + 4, head_cy - 2))
        # bangs bottom edge
        base += [(cx + rx - 6, head_cy - 18), (cx + 22, head_cy - 30), (cx + 8, head_cy - 14), (cx - 10, head_cy - 32), (cx - 26, head_cy - 16), (cx - rx + 6, head_cy - 26)]
        c.poly(base, hair)
        return
    if style == "curly":
        # bumpy cap made of circles
        for i in range(9):
            a = math.pi * (0.05 + 0.9 * i / 8)
            px = cx - math.cos(a) * (rx + 4)
            py = head_cy - 6 - math.sin(a) * (ry - 4)
            c.ellipse((px - 17, py - 17, px + 17, py + 17), hair)
        c.poly([(cx - rx - 4, head_cy - 10), (cx - rx + 6, head_cy - 40), (cx, head_cy - 50), (cx + rx - 6, head_cy - 40), (cx + rx + 4, head_cy - 10),
                (cx + 24, head_cy - 24), (cx + 4, head_cy - 32), (cx - 18, head_cy - 22)], hair, lw=0)
        c.poly([(cx - rx - 4, head_cy - 10), (cx - rx + 6, head_cy - 40), (cx, head_cy - 50), (cx + rx - 6, head_cy - 40), (cx + rx + 4, head_cy - 10),
                (cx + 24, head_cy - 24), (cx + 4, head_cy - 32), (cx - 18, head_cy - 22)], hair)
        return
    # generic cap with bangs (short / bob / ponytail / long)
    pts = [(cx - rx - 5, head_cy - 6), (cx - rx - 2, head_cy - 40), (cx - rx + 14, top - 2), (cx, top - 8), (cx + rx - 14, top - 2),
           (cx + rx + 2, head_cy - 40), (cx + rx + 5, head_cy - 6)]
    if style == "short":
        pts += [(cx + rx - 4, head_cy - 24), (cx + 18, head_cy - 36), (cx - 4, head_cy - 26), (cx - 24, head_cy - 38), (cx - rx + 4, head_cy - 22)]
    elif style == "bob":
        pts += [(cx + rx - 2, head_cy - 20), (cx + 26, head_cy - 34), (cx + 10, head_cy - 22), (cx - 8, head_cy - 36), (cx - 28, head_cy - 24), (cx - rx + 2, head_cy - 30)]
    elif style == "ponytail":
        pts += [(cx + rx - 2, head_cy - 30), (cx + 20, head_cy - 40), (cx - 2, head_cy - 24), (cx - 20, head_cy - 42), (cx - rx + 2, head_cy - 26)]
    else:  # long
        pts += [(cx + rx - 2, head_cy - 26), (cx + 30, head_cy - 44), (cx + 6, head_cy - 28), (cx - 14, head_cy - 46), (cx - 30, head_cy - 30), (cx - rx + 2, head_cy - 24)]
    c.poly(pts, hair)


def draw_face(c, cx, eye_y, eyes, skin, hair, mood, mask_draw=None):
    """eyes/brows/nose/mouth. mask_draw: callable(draw) to register unlit regions"""
    dark = LINE
    for side in (-1, 1):
        ex = cx + side * 21
        # sclera (almond)
        c.ellipse((ex - 15, eye_y - 10, ex + 15, eye_y + 10), (250, 248, 246, 255), lw=2)
        # iris / pupil / highlights
        ix = ex + side * 1
        c.ellipse((ix - 9, eye_y - 9, ix + 9, eye_y + 9), eyes, outline=shade(eyes, 0.55), lw=1.5)
        c.ellipse((ix - 4.5, eye_y - 4.5, ix + 4.5, eye_y + 4.5), (20, 16, 22, 255), lw=0)
        c.ellipse((ix - 6, eye_y - 7, ix - 1, eye_y - 2), (255, 255, 255, 255), lw=0)
        c.ellipse((ix + 2, eye_y + 2, ix + 4.5, eye_y + 4.5), (255, 255, 255, 230), lw=0)
        # upper lid (thick) + lashes
        c.arc((ex - 16, eye_y - 12, ex + 16, eye_y + 10), 195, 345, dark, 3.2)
        # brow
        if mood == "angry":
            inner_y, outer_y = eye_y - 20, eye_y - 28
        elif mood == "calm":
            inner_y, outer_y = eye_y - 25, eye_y - 23
        else:
            inner_y, outer_y = eye_y - 27, eye_y - 23
        bx0, bx1 = ex - side * 14, ex + side * 14
        c.poly([(bx0, inner_y), (bx1, outer_y), (bx1, outer_y + 4.5), (bx0, inner_y + 5.5)], shade(hair, 0.6), lw=0)
        if mask_draw:
            mask_draw(ex, eye_y)
    # nose
    c.line([(cx + 2, eye_y + 14), (cx + 5, eye_y + 23), (cx - 1, eye_y + 24)], (90, 60, 60, 255), 1.8)
    # mouth
    my = eye_y + 33
    if mood == "angry":
        c.line([(cx - 9, my + 2), (cx, my - 1), (cx + 9, my + 2)], dark, 2.4)
    elif mood == "calm":
        c.line([(cx - 8, my), (cx + 8, my)], dark, 2.4)
    else:
        c.arc((cx - 10, my - 8, cx + 10, my + 4), 15, 165, dark, 2.4)


def draw_character(spec):
    """returns (rgba 1x image, mask 1x image, meta)"""
    c = Canvas()
    skin = hexc(spec["skin"]); hair = hexc(spec["hair"]); jacket = hexc(spec["jacket"])
    pants = hexc(spec["pants"]); accent = hexc(spec["accent"]); eyes = hexc(spec["eyes"])
    style = spec.get("hair_style", "short")
    team = spec["team"]
    mood = spec.get("mood", "angry" if team == "enemy" else "smile")
    cx = 128
    boots = hexc("#1e1c22")
    jacket_dark = shade(jacket, 0.72)

    # proportions
    head_cy, rx, ry = 122, 46, 56
    head_top = head_cy - ry
    chin = head_cy + ry
    neck_top, shoulder_y, waist_y, hip_y, ankle_y, ground = chin - 6, 206, 296, 304, 452, 492

    # --- back layers
    draw_hair_back(c, style, hair, cx, head_top, head_cy, rx, ry)
    # back arm (screen-left)
    c.thick_limb([(cx - 48, shoulder_y + 10), (cx - 62, shoulder_y + 70), (cx - 56, shoulder_y + 132)], 28, jacket)
    c.ellipse((cx - 56 - 14, shoulder_y + 132 - 14, cx - 56 + 14, shoulder_y + 132 + 14), skin)
    # legs
    c.poly([(cx - 28, hip_y - 10), (cx - 2, hip_y - 10), (cx - 4, ankle_y), (cx - 30, ankle_y)], pants)
    c.poly([(cx + 2, hip_y - 10), (cx + 28, hip_y - 10), (cx + 32, ankle_y), (cx + 6, ankle_y)], pants)
    # boots
    c.rrect((cx - 36, ankle_y - 6, cx - 2, ground), 8, boots)
    c.rrect((cx + 4, ankle_y - 6, cx + 40, ground), 8, boots)
    c.rrect((cx - 36, ankle_y - 6, cx - 2, ankle_y + 6), 3, shade(boots, 1.6), lw=0)
    c.rrect((cx + 4, ankle_y - 6, cx + 40, ankle_y + 6), 3, shade(boots, 1.6), lw=0)
    # neck
    c.poly([(cx - 14, neck_top), (cx + 14, neck_top), (cx + 15, shoulder_y + 6), (cx - 15, shoulder_y + 6)], skin)
    # torso (jacket)
    c.poly([(cx - 56, shoulder_y), (cx + 56, shoulder_y), (cx + 52, shoulder_y + 40), (cx + 44, waist_y), (cx - 44, waist_y), (cx - 52, shoulder_y + 40)], jacket)
    # collar
    c.poly([(cx - 20, shoulder_y - 2), (cx, shoulder_y + 28), (cx + 20, shoulder_y - 2), (cx + 30, shoulder_y + 6), (cx, shoulder_y + 44), (cx - 30, shoulder_y + 6)], jacket_dark)
    c.poly([(cx - 14, shoulder_y + 2), (cx, shoulder_y + 24), (cx + 14, shoulder_y + 2)], skin, lw=0)
    # placket line + pockets
    c.line([(cx, shoulder_y + 44), (cx, waist_y - 4)], LINE, 2.2)
    for side in (-1, 1):
        c.rrect((cx + side * 36 - 11, shoulder_y + 46, cx + side * 36 + 11, shoulder_y + 68), 3, jacket_dark, lw=2)
        # epaulette
        c.rrect((cx + side * 44 - 12, shoulder_y - 3, cx + side * 44 + 12, shoulder_y + 7), 3, accent, lw=2)
    # team emblem
    if team == "enemy":
        c.poly([(cx + 36, shoulder_y + 78), (cx + 44, shoulder_y + 86), (cx + 36, shoulder_y + 94), (cx + 28, shoulder_y + 86)], accent, lw=1.5)
    else:
        c.rrect((cx + 29, shoulder_y + 78, cx + 43, shoulder_y + 92), 2, accent, lw=1.5)
    # belt
    c.poly([(cx - 45, waist_y - 8), (cx + 45, waist_y - 8), (cx + 45, waist_y + 8), (cx - 45, waist_y + 8)], (40, 36, 44, 255))
    c.rrect((cx - 9, waist_y - 7, cx + 9, waist_y + 7), 2, accent, lw=1.5)
    # front arm (screen-right), bent, hand at weapon grip
    hand = (cx + 44, shoulder_y + 92)
    c.thick_limb([(cx + 48, shoulder_y + 10), (cx + 70, shoulder_y + 56), hand], 28, jacket)
    c.ellipse((hand[0] - 14, hand[1] - 14, hand[0] + 14, hand[1] + 14), skin)
    # head
    c.poly(egg_points(cx, head_cy, rx, ry), skin)
    # ears
    for side in (-1, 1):
        c.ellipse((cx + side * (rx - 1) - 9, head_cy + 2, cx + side * (rx - 1) + 9, head_cy + 20), skin, lw=2)
    # face
    eye_y = head_cy + 14
    unlit_marks = []
    draw_face(c, cx, eye_y, eyes, skin, hair, mood, mask_draw=lambda ex, ey: unlit_marks.append((ex, ey)))
    # hair front
    draw_hair_front(c, style, hair, cx, head_top, head_cy, rx, ry)
    # baked self shadow (큰 덩어리 셀 그림자): under chin, under bangs, under belt, under sleeves
    def selfshadow(md):
        md.polygon(sc([(cx - 16, neck_top - 4), (cx + 16, neck_top - 4), (cx + 16, shoulder_y + 8), (cx - 16, shoulder_y + 8)]), fill=255)
        md.polygon(sc([(cx - rx, head_cy - 8), (cx + rx, head_cy - 8), (cx + rx, head_cy - 36), (cx - rx, head_cy - 36)]), fill=255)
        md.polygon(sc([(cx - 46, waist_y + 8), (cx + 46, waist_y + 8), (cx + 46, waist_y + 22), (cx - 46, waist_y + 22)]), fill=255)
        md.polygon(sc([(cx - 30, ankle_y - 22), (cx + 34, ankle_y - 22), (cx + 34, ankle_y - 6), (cx - 30, ankle_y - 6)]), fill=255)
    # only darken skin/hair/cloth, keep face features: apply before? (features drawn already) -> apply to neck/forehead/belt/ankles only
    c.multiply_region(selfshadow, 0.8)

    img1 = c.down()
    mask = build_zone_mask(img1, unlit_marks, light_from="right")
    mask_l = build_zone_mask(img1, unlit_marks, light_from="left")
    meta = {"hand": [hand[0], hand[1]], "head_rect": [cx - 72, head_top - 26, 144, 152], "ground": ground, "height": ground - (head_top - 30)}
    return img1, mask, mask_l, meta


def build_zone_mask(img1, unlit_marks, light_from="right", rim=5, smooth=0):
    """per-row silhouette split: key side (toward light) / ambient band / shadow side, rim accent on shadow edge.
    smooth>0: 행별 실루엣 좌/우 경계를 세로 이동평균으로 부드럽게 해 터미네이터의 계단을 줄인다."""
    w, h = img1.size
    a = img1.split()[3]
    px = a.load()
    mask = Image.new("L", (w, h), Z_AMBIENT)
    mp = mask.load()
    rows = []
    for y in range(h):
        xs = [x for x in range(w) if px[x, y] > 40]
        rows.append((xs[0], xs[-1], xs) if xs else None)
    edges = {}
    for y in range(h):
        if rows[y] is None:
            continue
        if smooth > 0:
            lo = max(0, y - smooth); hi = min(h, y + smooth + 1)
            ys = [rows[k] for k in range(lo, hi) if rows[k] is not None]
            edges[y] = (sum(r[0] for r in ys) / len(ys), sum(r[1] for r in ys) / len(ys))
        else:
            edges[y] = (rows[y][0], rows[y][1])
    for y in range(h):
        if rows[y] is None:
            continue
        xs = rows[y][2]
        x0, x1 = edges[y]
        width = max(1.0, x1 - x0)
        # slight diagonal: terminator shifts with height
        yn = y / h
        # 빛 받는 면을 60% 안팎으로: 얼굴이 절반으로 갈리지 않고 '큰 덩어리 그림자' 가 반대쪽에 남도록
        key_t = 0.38 - 0.12 * (yn - 0.5)
        amb_t = key_t - 0.17
        for x in xs:
            t = (x - x0) / width
            if light_from == "left":
                t = 1.0 - t
            if t >= key_t:
                v = Z_KEY
            elif t >= amb_t:
                v = Z_AMBIENT
            else:
                v = Z_SHADOW
            # rim on the shadow-side silhouette edge (실제 경계 기준)
            d_edge = (x - rows[y][0]) if light_from == "right" else (rows[y][1] - x)
            if d_edge < rim:
                v = Z_ACCENT
            mp[x, y] = v
    md = ImageDraw.Draw(mask)
    for (ex, ey) in unlit_marks:
        md.ellipse([ex - 15, ey - 10, ex + 15, ey + 10], fill=Z_UNLIT)
    return mask


# ------------------------------------------------------------------ weapons
METAL = hexc("#3a3f47"); METAL_D = hexc("#262a30"); WOOD = hexc("#6b4428"); STEEL = hexc("#c9d2dc")


def weapon_shapes(wid, accent):
    """list of (kind, pts/box, color) in local coords; origin = grip, +x = muzzle direction; rotation applied later"""
    sh = []
    if wid in ("rifle", "sniper", "smg", "shotgun", "mg", "launcher"):
        L = {"rifle": 72, "sniper": 104, "smg": 44, "shotgun": 76, "mg": 84, "launcher": 54}[wid]
        thick = 9 if wid in ("mg", "launcher") else 5
        sh.append(("poly", [(-30, -6), (-58, -1), (-60, 12), (-32, 9)], WOOD if wid in ("shotgun", "rifle") else METAL_D))  # stock
        sh.append(("rect", (-32, -thick, L, thick), METAL))  # receiver+barrel
        sh.append(("rect", (-8, thick - 1, 2, thick + 13), METAL_D))  # grip
        if wid != "shotgun":
            sh.append(("rect", (8, thick - 1, 20 if wid != "mg" else 30, thick + 18), METAL_D))  # magazine
        if wid == "sniper":
            sh.append(("rect", (4, -16, 40, -7), METAL_D))  # scope
            sh.append(("rect", (56, 6, 60, 26), METAL_D))  # bipod
        if wid == "mg":
            sh.append(("rect", (10, -16, 30, -9), METAL_D))
            sh.append(("rect", (60, 9, 64, 28), METAL_D))
        if wid == "launcher":
            sh.append(("rect", (34, -11, L + 6, 11), shade(METAL, 1.2)))
        if wid == "shotgun":
            sh.append(("rect", (24, 5, 46, 11), WOOD))
        sh.append(("rect", (L - 6, -2, L + 4, 2), METAL_D))  # muzzle
        sh.append(("rect", (-14, -thick - 4, -4, -thick), accent))  # accent band
    elif wid == "pistol":
        sh.append(("rect", (-8, -7, 30, 1), METAL))
        sh.append(("poly", [(-8, 1), (6, 1), (2, 22), (-10, 22)], METAL_D))
        sh.append(("rect", (24, -9, 28, -7), accent))
    elif wid in ("axe", "mace", "club", "baton"):
        sh.append(("rect", (-5, -78, 5, 22), WOOD if wid in ("axe", "club", "mace") else METAL_D))
        if wid == "axe":
            sh.append(("poly", [(4, -78), (44, -96), (50, -60), (46, -30), (4, -44)], STEEL))
            sh.append(("poly", [(-4, -78), (-34, -92), (-40, -60), (-36, -34), (-4, -44)], STEEL))
        elif wid == "mace":
            sh.append(("ellipse", (-22, -110, 22, -66), METAL))
            for a in range(0, 360, 45):
                r = math.radians(a)
                sh.append(("poly", [(math.cos(r) * 20 - math.sin(r) * 4, -88 + math.sin(r) * 20 + math.cos(r) * 4),
                                    (math.cos(r) * 32, -88 + math.sin(r) * 32),
                                    (math.cos(r) * 20 + math.sin(r) * 4, -88 + math.sin(r) * 20 - math.cos(r) * 4)], METAL_D))
        elif wid == "club":
            sh.append(("poly", [(-6, -40), (6, -40), (14, -100), (-14, -100)], WOOD))
        elif wid == "baton":
            sh.append(("rect", (4, -10, 22, -4), METAL_D))
            sh.append(("rect", (-6, -30, 6, -22), accent))
    elif wid in ("blade", "bayonet", "knife", "syringe"):
        L = {"blade": 96, "bayonet": 52, "knife": 38, "syringe": 44}[wid]
        if wid == "syringe":
            sh.append(("rect", (-6, -8, 30, 8), (240, 240, 245, 255)))
            sh.append(("rect", (-2, -5, 20, 5), accent))
            sh.append(("rect", (30, -1.5, 52, 1.5), STEEL))
            sh.append(("rect", (-22, -3, -6, 3), STEEL))
            sh.append(("rect", (-26, -9, -20, 9), (240, 240, 245, 255)))
        else:
            sh.append(("rect", (-18, -5, 2, 5), METAL_D))  # grip
            sh.append(("rect", (0, -11, 6, 11), accent))   # guard
            sh.append(("poly", [(6, -6), (L - 12, -7), (L, 0), (L - 12, 5), (6, 5)], STEEL))
            sh.append(("rect", (-24, -5, -18, 5), METAL))
    return sh


def draw_weapon(wid, accent_hex, angle_deg):
    accent = hexc(accent_hex)
    size = 320
    c = Canvas(size, size)
    ox, oy = size / 2, size / 2
    ang = math.radians(angle_deg)

    def tr(p):
        x, y = p
        return (ox + x * math.cos(ang) - y * math.sin(ang), oy + x * math.sin(ang) + y * math.cos(ang))

    for kind, g, col in weapon_shapes(wid, accent):
        if kind == "rect":
            x0, y0, x1, y1 = g
            pts = [tr((x0, y0)), tr((x1, y0)), tr((x1, y1)), tr((x0, y1))]
            c.poly(pts, col, lw=2.2)
        elif kind == "poly":
            c.poly([tr(p) for p in g], col, lw=2.2)
        elif kind == "ellipse":
            x0, y0, x1, y1 = g
            cxx, cyy = (x0 + x1) / 2, (y0 + y1) / 2
            r = (x1 - x0) / 2
            pts = [tr((cxx + r * math.cos(t), cyy + r * math.sin(t))) for t in [2 * math.pi * i / 40 for i in range(40)]]
            c.poly(pts, col, lw=2.2)
    img = c.down()
    bbox = img.getbbox()
    if bbox is None:
        bbox = (0, 0, 1, 1)
    pad = 2
    bbox = (max(0, bbox[0] - pad), max(0, bbox[1] - pad), min(size, bbox[2] + pad), min(size, bbox[3] + pad))
    img = img.crop(bbox)
    pivot = (ox - bbox[0], oy - bbox[1])
    mask_r = build_zone_mask(img, [], "right", rim=3)
    mask_l = build_zone_mask(img, [], "left", rim=3)
    return img, mask_r, mask_l, pivot


# ------------------------------------------------------------------ 3D face decal
def draw_face_texture(spec):
    """256x128 transparent decal: eyes, brows, nose, mouth"""
    c = Canvas(256, 128)
    eyes = hexc(spec["eyes"]); hair = hexc(spec["hair"]); skin = hexc(spec["skin"])
    mood = spec.get("mood", "angry" if spec["team"] == "enemy" else "smile")
    draw_face(c, 128, 52, eyes, skin, hair, mood)
    return c.down()


# ------------------------------------------------------------------ background plate (40° 내려다보는 원근 카메라)
# 2D 전투의 가상 카메라. Godot battle_view_2d.gd 가 manifest.json 의 같은 값으로 슬롯 위치·크기를 투영한다.
# 좌표: x 오른쪽, y 위, z 카메라 쪽(m). 뒷벽 z=-3.6, 바닥 y=0.
CAMERA = {"pitch_deg": 40.0, "dist": 15.0, "target": [0.0, 0.0, 0.6], "vfov_deg": 32.0,
          "cx": 640.0, "cy": 430.0, "screen": [1280, 720], "unit_height_m": 1.75, "sprite_px": 230.0,
          "slot": {"row_x": [1.3, 3.0, 4.7], "index_z": [0.0, 1.8], "index_dx": 0.4}}
WALL_Z = -3.6


class Cam:
    def __init__(self, c):
        p = math.radians(c["pitch_deg"])
        self.f = (c["screen"][1] / 2) / math.tan(math.radians(c["vfov_deg"] / 2))
        t = c["target"]
        self.C = (t[0], t[1] + c["dist"] * math.sin(p), t[2] + c["dist"] * math.cos(p))
        self.F = (0.0, -math.sin(p), -math.cos(p))
        self.U = (0.0, math.cos(p), -math.sin(p))
        self.cx, self.cy = c["cx"], c["cy"]

    def p(self, x, y, z):
        v = (x - self.C[0], y - self.C[1], z - self.C[2])
        zc = v[1] * self.F[1] + v[2] * self.F[2]
        yc = v[1] * self.U[1] + v[2] * self.U[2]
        return (self.cx + self.f * v[0] / zc, self.cy - self.f * yc / zc)

    def poly(self, pts3):
        return [self.p(*q) for q in pts3]


BG_RES = 2   # 배경은 1280×720 의 2배로 생성 (레티나·전체화면에서 흐려지지 않게). Godot 에서 0.5배로 표시


def draw_background():
    BW, BH = 1280 * BG_RES, 720 * BG_RES
    global S, PX
    S_prev, PX_prev = S, PX
    S, PX = 2, BG_RES
    cam = Cam(dict(CAMERA, screen=[BW, BH], cx=CAMERA["cx"] * BG_RES, cy=CAMERA["cy"] * BG_RES))
    c = Canvas(BW, BH)
    m = Image.new("L", (BW * S, BH * S), Z_AMBIENT)   # 마스크도 같은 배율로 그린 뒤 축소
    md = ImageDraw.Draw(m)

    def mpoly(pts3, code):
        md.polygon(sc(cam.poly(pts3)), fill=code)

    wall = hexc("#cbc4b8"); wall_line = hexc("#aaa296"); floor_c = hexc("#b9b1a3"); base_c = hexc("#9d968c")
    frame = hexc("#5e5650"); open_c = hexc("#f4f0e8"); prop = hexc("#8f8880"); wood = hexc("#7d6a56")
    crate_c = hexc("#a08c72")
    X0, X1 = -12.0, 12.0
    # 바닥 + 타일
    c.poly(cam.poly([(X0, 0, WALL_Z), (X1, 0, WALL_Z), (X1, 0, 12), (X0, 0, 12)]), floor_c, lw=0)
    for gx in range(-12, 13):
        c.line(cam.poly([(gx, 0, WALL_Z), (gx, 0, 12)]), shade(floor_c, 0.84), 2)
    for gz in range(-3, 12):
        c.line(cam.poly([(X0, 0, gz + 0.4), (X1, 0, gz + 0.4)]), shade(floor_c, 0.84), 2)
    # 뒷벽 + 패널선 + 걸레받이
    c.poly(cam.poly([(X0, 0, WALL_Z), (X1, 0, WALL_Z), (X1, 6, WALL_Z), (X0, 6, WALL_Z)]), wall, lw=0)
    for y in (0.8, 1.6, 2.4, 3.2, 4.0):
        c.line(cam.poly([(X0, y, WALL_Z), (X1, y, WALL_Z)]), wall_line, 2)
    c.poly(cam.poly([(X0, 0, WALL_Z + 0.05), (X1, 0, WALL_Z + 0.05), (X1, 0.16, WALL_Z + 0.05), (X0, 0.16, WALL_Z + 0.05)]), base_c, lw=2.5)
    c.line(cam.poly([(X0, 0, WALL_Z + 0.05), (X1, 0, WALL_Z + 0.05)]), LINE, 3)
    # 창 (왼쪽)
    wx0, wx1, wy0, wy1 = -5.4, -3.2, 1.0, 2.5
    c.poly(cam.poly([(wx0 - 0.12, wy0 - 0.12, WALL_Z), (wx1 + 0.12, wy0 - 0.12, WALL_Z), (wx1 + 0.12, wy1 + 0.12, WALL_Z), (wx0 - 0.12, wy1 + 0.12, WALL_Z)]), frame, lw=3)
    c.poly(cam.poly([(wx0, wy0, WALL_Z), (wx1, wy0, WALL_Z), (wx1, wy1, WALL_Z), (wx0, wy1, WALL_Z)]), open_c, lw=0)
    c.line(cam.poly([((wx0 + wx1) / 2, wy0, WALL_Z), ((wx0 + wx1) / 2, wy1, WALL_Z)]), frame, 8)
    c.line(cam.poly([(wx0, (wy0 + wy1) / 2, WALL_Z), (wx1, (wy0 + wy1) / 2, WALL_Z)]), frame, 8)
    # 게시판
    c.poly(cam.poly([(-0.9, 1.1, WALL_Z), (0.9, 1.1, WALL_Z), (0.9, 2.2, WALL_Z), (-0.9, 2.2, WALL_Z)]), hexc("#7b6b5a"), lw=3)
    c.poly(cam.poly([(-0.78, 1.2, WALL_Z), (0.78, 1.2, WALL_Z), (0.78, 2.1, WALL_Z), (-0.78, 2.1, WALL_Z)]), hexc("#d8cfbf"), lw=2)
    for (a, b, y0, y1, col) in [(-0.68, -0.2, 1.55, 2.0, "#e9e2d4"), (-0.1, 0.65, 1.7, 2.0, "#c8d7d2"), (-0.68, 0.65, 1.28, 1.45, "#efe7d6")]:
        c.poly(cam.poly([(a, y0, WALL_Z), (b, y0, WALL_Z), (b, y1, WALL_Z), (a, y1, WALL_Z)]), hexc(col), lw=1.5)
    # 문 (오른쪽) + 바깥 + 열린 문짝
    dx0, dx1, dh = 3.0, 4.4, 2.6
    c.poly(cam.poly([(dx0 - 0.14, 0, WALL_Z), (dx1 + 0.14, 0, WALL_Z), (dx1 + 0.14, dh + 0.14, WALL_Z), (dx0 - 0.14, dh + 0.14, WALL_Z)]), frame, lw=3)
    c.poly(cam.poly([(dx0, 0, WALL_Z), (dx1, 0, WALL_Z), (dx1, dh, WALL_Z), (dx0, dh, WALL_Z)]), open_c, lw=0)
    c.poly(cam.poly([(dx0 + 0.3, 0, WALL_Z), (dx1, 0, WALL_Z), (dx1, 0.9, WALL_Z), (dx0 + 0.3, 0.9, WALL_Z)]), hexc("#e6e0d6"), lw=0)
    ang = math.radians(55)
    lx, lz = dx0 + 1.3 * math.cos(ang) * 0.0, WALL_Z
    leaf_end = (dx0 + 1.3 * math.cos(ang), WALL_Z + 1.3 * math.sin(ang))
    leaf = [(dx0, 0, WALL_Z), (leaf_end[0], 0, leaf_end[1]), (leaf_end[0], dh - 0.05, leaf_end[1]), (dx0, dh - 0.05, WALL_Z)]
    # 기둥 (오른쪽 끝)
    def box(x0, x1, z0, z1, h, col, top=None, side=None, y0=0.0):
        """painter's box (y0~h): 윗면 + 앞면(+z) + 카메라 쪽 옆면"""
        top = top or shade(col, 1.12); side = side or shade(col, 0.82)
        camx = cam.C[0]
        if x1 < camx:
            c.poly(cam.poly([(x1, y0, z0), (x1, y0, z1), (x1, h, z1), (x1, h, z0)]), side)
        elif x0 > camx:
            c.poly(cam.poly([(x0, y0, z0), (x0, y0, z1), (x0, h, z1), (x0, h, z0)]), side)
        c.poly(cam.poly([(x0, y0, z1), (x1, y0, z1), (x1, h, z1), (x0, h, z1)]), col)
        c.poly(cam.poly([(x0, h, z0), (x1, h, z0), (x1, h, z1), (x0, h, z1)]), top)
    # 소품 (뒤에서 앞으로)
    box(6.0, 6.6, WALL_Z, WALL_Z + 0.5, 6.0, hexc("#b4ada1"))
    for i, (a, b) in enumerate([(-2.4, -1.8), (-1.8, -1.2)]):
        box(a, b, WALL_Z, WALL_Z + 0.55, 2.0, prop if i == 0 else shade(prop, 0.95))
        fz = WALL_Z + 0.55
        c.line(cam.poly([(a + 0.1, 1.75, fz), (b - 0.1, 1.75, fz)]), shade(prop, 0.7), 3)
        c.line(cam.poly([(a + 0.1, 1.65, fz), (b - 0.1, 1.65, fz)]), shade(prop, 0.7), 3)
        c.poly(cam.poly([(b - 0.14, 0.95, fz), (b - 0.08, 0.95, fz), (b - 0.08, 1.15, fz), (b - 0.14, 1.15, fz)]), shade(prop, 0.6), lw=1.5)
    box(-6.4, -5.0, WALL_Z + 0.1, WALL_Z + 1.1, 0.9, crate_c)
    box(-6.1, -5.3, WALL_Z + 0.2, WALL_Z + 0.95, 0.65 + 0.9, crate_c, y0=0.9)
    # 탁자: 다리 → 상판 → 무전기
    for lx_ in (0.95, 2.65):
        for lz_ in (WALL_Z + 0.25, WALL_Z + 1.05):
            box(lx_ - 0.05, lx_ + 0.05, lz_ - 0.05, lz_ + 0.05, 0.8, hexc("#5d4e3f"))
    box(0.8, 2.8, WALL_Z + 0.15, WALL_Z + 1.15, 0.86, wood, y0=0.78)
    box(1.5, 2.1, WALL_Z + 0.45, WALL_Z + 0.8, 1.06, hexc("#5f7f86"), y0=0.86)
    c.poly(cam.poly(leaf), hexc("#8a7b6e"), lw=3)
    c.poly(cam.poly([(leaf_end[0] - 0.12, 1.05, leaf_end[1] - 0.1), (leaf_end[0] - 0.05, 1.05, leaf_end[1] - 0.02), (leaf_end[0] - 0.05, 1.25, leaf_end[1] - 0.02), (leaf_end[0] - 0.12, 1.25, leaf_end[1] - 0.1)]), hexc("#d8b24a"), lw=1.5)

    # ------- 구역 마스크 (월드 좌표 다각형 → 같은 카메라로 투영)
    sl = CAMERA["slot"]
    # 그림자: 왼쪽 벽 구석, 사물함/탁자/상자가 문빛(오른쪽)에서 왼쪽으로 드리운 그림자
    mpoly([(X0, 0, WALL_Z), (-7.6, 0, WALL_Z), (-7.6, 6, WALL_Z), (X0, 6, WALL_Z)], Z_SHADOW)
    mpoly([(X0, 0, WALL_Z), (-7.6, 0, WALL_Z), (-9.5, 0, 12), (X0, 0, 12)], Z_SHADOW)
    mpoly([(-2.4, 0, WALL_Z), (-1.2, 0, WALL_Z), (-1.2, 0, WALL_Z + 0.55), (-3.6, 0, WALL_Z + 1.9), (-3.9, 0, WALL_Z)], Z_SHADOW)
    mpoly([(-2.4, 0, WALL_Z), (-1.2, 0, WALL_Z), (-1.2, 2.0, WALL_Z), (-2.4, 2.0, WALL_Z)], Z_SHADOW)
    mpoly([(-1.2, 0, WALL_Z), (-1.2, 0, WALL_Z + 0.55), (-1.2, 2.0, WALL_Z + 0.55), (-1.2, 2.0, WALL_Z)], Z_SHADOW)
    mpoly([(0.8, 0, WALL_Z + 0.15), (2.8, 0, WALL_Z + 0.15), (2.8, 0, WALL_Z + 1.15), (0.2, 0, WALL_Z + 1.5), (0.4, 0, WALL_Z + 0.15)], Z_SHADOW)
    mpoly([(-6.4, 0, WALL_Z + 0.1), (-5.0, 0, WALL_Z + 0.1), (-5.0, 0, WALL_Z + 1.1), (-6.8, 0, WALL_Z + 1.6)], Z_SHADOW)
    # 창빛(보조광): 유리 + 아래 벽 + 아군 후열을 덮는 바닥 빔
    mpoly([(wx0, wy0, WALL_Z), (wx1, wy0, WALL_Z), (wx1, wy1, WALL_Z), (wx0, wy1, WALL_Z)], Z_ACCENT)
    mpoly([(wx0, 0.2, WALL_Z), (wx1, 0.2, WALL_Z), (wx1, wy0 - 0.12, WALL_Z), (wx0, wy0 - 0.12, WALL_Z)], Z_ACCENT)
    bx_r = -sl["row_x"][2] + 0.65   # 아군 후열 오른쪽 끝 바로 바깥 (중열은 빔 밖)
    mpoly([(wx0 - 0.6, 0, WALL_Z), (wx1 + 0.2, 0, WALL_Z), (bx_r, 0, 3.4), (-6.6, 0, 3.4)], Z_ACCENT)
    # 문빛(주조명): 개구부 + 오른쪽 벽 조각 + 적 진영을 덮는 바닥 쐐기 + 문짝 그림자 띠
    mpoly([(dx0, 0, WALL_Z), (dx1, 0, WALL_Z), (dx1, dh, WALL_Z), (dx0, dh, WALL_Z)], Z_KEY)
    mpoly([(dx1 + 0.14, 0, WALL_Z), (6.0, 0, WALL_Z), (6.0, 3.6, WALL_Z), (dx1 + 0.14, 3.0, WALL_Z)], Z_KEY)
    mpoly([(6.0, 0, WALL_Z + 0.5), (6.6, 0, WALL_Z + 0.5), (6.6, 6, WALL_Z + 0.5), (6.0, 6, WALL_Z + 0.5)], Z_KEY)
    mpoly([(dx0, 0, WALL_Z), (dx1 + 0.4, 0, WALL_Z), (X1, 0, 2.0), (X1, 0, 12), (-1.0, 0, 12), (-0.6, 0, 3.4)], Z_KEY)
    mpoly([(dx0 + 0.05, 0, WALL_Z), (dx0 + 0.32, 0, WALL_Z), (2.75, 0, -0.8), (2.45, 0, -0.8)], Z_SHADOW)   # 문짝 그림자: 캐릭터 뒤에서 끝남
    mpoly(leaf, Z_AMBIENT)
    mpoly([(1.5, 1.06, WALL_Z + 0.8), (2.1, 1.06, WALL_Z + 0.8), (2.1, 0.9, WALL_Z + 0.8), (1.5, 0.9, WALL_Z + 0.8)], Z_UNLIT)
    img = c.down()
    mask = m.resize((BW, BH), Image.NEAREST)
    S, PX = S_prev, PX_prev
    return img, mask


# ------------------------------------------------------------------ main
UNITS = {
    "a_jiho": {"team": "ally", "skin": "#f4c9a4", "hair": "#2b1d16", "jacket": "#3b5d4a", "pants": "#2a3340", "accent": "#ffb347", "eyes": "#4a86c8", "hair_style": "spiky", "weapon_angle": 20},
    "a_sera": {"team": "ally", "skin": "#f8d6c2", "hair": "#e8c178", "jacket": "#4e6b8a", "pants": "#2d2f3a", "accent": "#ff5e8a", "eyes": "#3aa66e", "hair_style": "bob", "mood": "calm"},
    "a_minu": {"team": "ally", "skin": "#e9b68f", "hair": "#141414", "jacket": "#5b6652", "pants": "#30353a", "accent": "#62d3ff", "eyes": "#7a4b2a", "hair_style": "short", "mood": "calm"},
    "a_haneul": {"team": "ally", "skin": "#fbe3d0", "hair": "#c4553a", "jacket": "#e9e4d6", "pants": "#3a4652", "accent": "#ff3b5c", "eyes": "#2f7fd3", "hair_style": "ponytail"},
    "a_raon": {"team": "ally", "skin": "#f1c7ad", "hair": "#6e5cc9", "jacket": "#2e3d5c", "pants": "#1e222c", "accent": "#b8ff5e", "eyes": "#e0b84a", "hair_style": "long", "mood": "calm"},
    "a_doyun": {"team": "ally", "skin": "#f3cdb3", "hair": "#8a5a2b", "jacket": "#6b5f8e", "pants": "#2c2a3a", "accent": "#ffe45e", "eyes": "#4c4c4c", "hair_style": "curly"},
    "e_captain": {"team": "enemy", "skin": "#d9b08c", "hair": "#111111", "jacket": "#7a1f2b", "pants": "#1f1f24", "accent": "#ffd23f", "eyes": "#d8463c", "hair_style": "short"},
    "e_grenadier": {"team": "enemy", "skin": "#c99a76", "hair": "#4a2d1b", "jacket": "#6a2230", "pants": "#26242b", "accent": "#ff8c42", "eyes": "#5a3b2e", "hair_style": "bald"},
    "e_rifle": {"team": "enemy", "skin": "#e4b393", "hair": "#2a1a12", "jacket": "#8a2634", "pants": "#2b2630", "accent": "#ff5c5c", "eyes": "#3b2f2f", "hair_style": "short", "mood": "calm"},
    "e_gunner": {"team": "enemy", "skin": "#bf8e6e", "hair": "#1a1a1a", "jacket": "#5e1e2a", "pants": "#22212a", "accent": "#ffb86b", "eyes": "#2a2a2a", "hair_style": "spiky"},
    "e_sniper": {"team": "enemy", "skin": "#f0cdb4", "hair": "#d6d6e0", "jacket": "#4a1b2c", "pants": "#1d1c26", "accent": "#ff2e7a", "eyes": "#b23a9e", "hair_style": "long", "mood": "calm"},
    "e_commander": {"team": "enemy", "skin": "#e8c4a8", "hair": "#6b4a2b", "jacket": "#9a2b3f", "pants": "#2b2230", "accent": "#ffd700", "eyes": "#2f4f8f", "hair_style": "bob"},
}
WEAPONS = {  # id: default angle (deg, +cw) when held
    "rifle": -28, "sniper": -24, "smg": -30, "shotgun": -28, "mg": -22, "launcher": -20, "pistol": -30,
    "axe": 14, "mace": 12, "club": 14, "baton": 18, "blade": -40, "bayonet": -36, "knife": -36, "syringe": -40,
}


def main():
    manifest = {"units": {}, "weapons": {}, "zones": {"shadow": 0, "ambient": 85, "unlit": 128, "key": 170, "accent": 255},
                "camera": CAMERA}
    for uid, spec in UNITS.items():
        img, mask_r, mask_l, meta = draw_character(spec)
        img.save(os.path.join(OUT_SPR, f"{uid}.png"))
        mask_r.save(os.path.join(OUT_SPR, f"{uid}_mask_r.png"))
        mask_l.save(os.path.join(OUT_SPR, f"{uid}_mask_l.png"))
        draw_face_texture(spec).save(os.path.join(OUT_TEX, f"face_{uid}.png"))
        meta["palette"] = {k: spec[k] for k in ("skin", "hair", "jacket", "pants", "accent", "eyes")}
        meta["hair_style"] = spec["hair_style"]
        manifest["units"][uid] = meta
        print("unit", uid, meta["hand"])
    for wid, ang in WEAPONS.items():
        img, mr, ml, pivot = draw_weapon(wid, "#ffd23f", ang)
        img.save(os.path.join(OUT_SPR, f"w_{wid}.png"))
        mr.save(os.path.join(OUT_SPR, f"w_{wid}_mask_r.png"))
        ml.save(os.path.join(OUT_SPR, f"w_{wid}_mask_l.png"))
        manifest["weapons"][wid] = {"pivot": [pivot[0], pivot[1]], "size": [img.width, img.height]}
    bg, bgm = draw_background()
    bg.save(os.path.join(OUT_TEX, "bg_barracks.png"))
    bgm.save(os.path.join(OUT_TEX, "bg_barracks_mask.png"))
    with open(os.path.join(OUT_SPR, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    # contact sheet for review
    sheet = Image.new("RGBA", (256 * 6, 512 * 2 + 300), (70, 70, 80, 255))
    for i, uid in enumerate(UNITS):
        im = Image.open(os.path.join(OUT_SPR, f"{uid}.png"))
        sheet.alpha_composite(im, ((i % 6) * 256, (i // 6) * 512))
    x = 0
    for wid in WEAPONS:
        im = Image.open(os.path.join(OUT_SPR, f"w_{wid}.png"))
        sheet.alpha_composite(im, (x, 1040))
        x += im.width + 10
    sheet.save(os.path.join(OUT_TEX, "_contact_sheet.png"))
    print("done")


if __name__ == "__main__":
    main()
