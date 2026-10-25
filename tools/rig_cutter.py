#!/usr/bin/env python3
"""레퍼런스 원화 1장 → Skeleton2D 컷아웃 파츠 + 관절 정의(rig.json) + 구역 마스크.

입력: assets/source/<원화>.png (투명 배경). 캐릭터별 정의는 CHARACTERS 참고.
출력: assets/sprites/rig_<id>/<part>.png, <part>_mask_r/_l.png, rig.json, _debug_parts.png
사용: python3 tools/rig_cutter.py [id ...]   (생략하면 전부)

절차(제작 비용 산정용으로 단계 수를 셉니다):
 1) 색 분류 (머리카락 / 피부 / 어두운 의상)        — 자동
 2) 부위 폴리곤 14개 + 관절 피벗 15개 좌표 지정     — 수동 (이 파일의 PARTS/BONES)
 3) 폴리곤 ∩ 색분류로 파츠 추출, 이음새 1px 팽창   — 자동
 4) 전신 구역 마스크 → 파츠별 크롭                 — 자동 (gen_sprites.build_zone_mask 와 같은 규칙)
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from gen_sprites import build_zone_mask, Z_UNLIT  # noqa

SRC = ""
OUT = ""
CLASSIFY = "warm"

# ---- 2) 관절(본) : name, parent, 이미지 좌표 (rest 회전 0, 위치만)
BONES = [
    ("hip", "", (585, 700)),
    ("spine", "hip", (585, 600)),
    ("chest", "spine", (585, 470)),
    ("head", "chest", (535, 325)),
    ("shoulder_l", "chest", (400, 375)),
    ("elbow_l", "shoulder_l", (378, 612)),
    ("wrist_l", "elbow_l", (330, 815)),
    ("shoulder_r", "chest", (672, 375)),
    ("elbow_r", "shoulder_r", (700, 612)),
    ("wrist_r", "elbow_r", (758, 815)),
    ("hip_l", "hip", (500, 780)),
    ("knee_l", "hip_l", (430, 1100)),
    ("ankle_l", "knee_l", (360, 1435)),
    ("hip_r", "hip", (670, 780)),
    ("knee_r", "hip_r", (690, 1100)),
    ("ankle_r", "knee_r", (700, 1435)),
]
# ---- 2) 파츠: name, bone, class, polygon, z (뒤→앞)
HEAD_POLY = [(380, 10), (700, 10), (730, 330), (600, 330), (570, 352), (500, 352), (470, 330), (360, 330)]
PARTS = [
    ("hair_back", "head", "hair", [(230, 0), (800, 0), (800, 900), (230, 900)], 0),
    ("shin_l", "knee_l", "dark", [(240, 1090), (592, 1090), (602, 1445), (225, 1445)], 1),
    ("shin_r", "knee_r", "dark", [(582, 1090), (800, 1090), (835, 1445), (592, 1445)], 1),
    ("foot_l", "ankle_l", "any", [(225, 1412), (440, 1412), (440, 1515), (225, 1515)], 2),
    ("foot_r", "ankle_r", "any", [(560, 1412), (840, 1412), (840, 1515), (560, 1515)], 2),
    ("thigh_l", "hip_l", "dark", [(300, 775), (590, 775), (592, 1120), (255, 1120)], 3),
    ("thigh_r", "hip_r", "dark", [(582, 775), (770, 775), (805, 1120), (590, 1120)], 3),
    ("hips", "hip", "dark", [(440, 582), (710, 582), (722, 800), (430, 800)], 4),
    ("torso", "chest", "nothair", [(395, 300), (680, 300), (690, 420), (642, 430), (642, 622), (468, 622), (448, 430), (388, 420)], 5),
    ("arm_upper_l", "shoulder_l", "dark", [(350, 350), (452, 372), (446, 600), (430, 640), (322, 640), (335, 520)], 6),
    ("arm_upper_r", "shoulder_r", "dark", [(620, 372), (712, 350), (736, 520), (748, 640), (640, 640), (626, 600)], 6),
    ("arm_lower_l", "elbow_l", "skindark", [(326, 590), (436, 590), (410, 760), (378, 822), (296, 818), (312, 700)], 7),
    ("arm_lower_r", "elbow_r", "skindark", [(632, 590), (746, 590), (770, 700), (790, 818), (708, 822), (676, 760)], 7),
    ("hand_l", "wrist_l", "skin", [(280, 800), (380, 800), (376, 905), (272, 905)], 8),
    ("hand_r", "wrist_r", "skin", [(700, 800), (812, 800), (820, 905), (706, 905)], 8),
    ("head", "head", "any", HEAD_POLY, 9),
    ("hair_front", "head", "hair", [(588, 280), (662, 280), (662, 440), (588, 440)], 10),
]
EYES = [(492, 206), (596, 206)]
GROUND = (585, 1505)
HEAD_RECT = (360, 20, 380, 340)

# ---- hero2 (하나): 갈색 곱슬 롱헤어(허리까지), 짙은 회색 전투복(소매 걷음)·탱크톱·타투, 부츠 (원화 1024x1535)
HERO2 = {
    "src": "char_ref2.png", "classify": "neutral", "head_rect": (420, 0, 300, 300),
    "irises": [(522, 164, 14), (597, 186, 12)], "iris_rule": "amber",   # 호박색 홍채 → 파랑 성분이 적은 픽셀
    "eyes": [(522, 164), (597, 186)], "ground": (575, 1515),
    "bones": [
        ("hip", "", (575, 610)), ("spine", "hip", (575, 520)), ("chest", "spine", (565, 420)),
        ("head", "chest", (555, 285)),
        ("shoulder_l", "chest", (375, 335)), ("elbow_l", "shoulder_l", (365, 600)), ("wrist_l", "elbow_l", (335, 775)),
        ("shoulder_r", "chest", (650, 345)), ("elbow_r", "shoulder_r", (705, 600)), ("wrist_r", "elbow_r", (765, 770)),
        ("hip_l", "hip", (510, 660)), ("knee_l", "hip_l", (430, 1050)), ("ankle_l", "knee_l", (310, 1375)),
        ("hip_r", "hip", (640, 660)), ("knee_r", "hip_r", (680, 1050)), ("ankle_r", "knee_r", (735, 1390)),
    ],
    "parts": [
        ("hair_back", "head", "notdark", [(290, 0), (730, 0), (730, 690), (290, 690)], 0),
        ("foot_l", "ankle_l", "any", [(225, 1355), (402, 1355), (402, 1522), (225, 1522)], 1),
        ("foot_r", "ankle_r", "any", [(640, 1370), (860, 1370), (860, 1522), (640, 1522)], 1),
        ("shin_l", "knee_l", "dark", [(225, 1040), (577, 1040), (562, 1405), (228, 1405)], 2),
        ("shin_r", "knee_r", "dark", [(565, 1040), (802, 1040), (802, 1462), (560, 1462)], 2),
        ("thigh_l", "hip_l", "dark", [(420, 650), (588, 650), (572, 1062), (258, 1062)], 3),
        ("thigh_r", "hip_r", "dark", [(575, 650), (722, 650), (792, 1062), (565, 1062)], 3),
        ("hips", "hip", "dark", [(435, 540), (712, 540), (716, 702), (430, 702)], 4),
        ("torso", "chest", "skindark", [(430, 280), (690, 280), (702, 400), (692, 562), (440, 562), (425, 400)], 5),
        ("arm_upper_l", "shoulder_l", "dark", [(288, 298), (452, 298), (456, 562), (432, 626), (288, 626), (272, 550)], 6),
        ("arm_upper_r", "shoulder_r", "dark", [(618, 318), (702, 328), (748, 520), (748, 616), (680, 616), (664, 450)], 6),
        ("arm_lower_l", "elbow_l", "any", [(288, 580), (442, 580), (412, 700), (382, 792), (294, 792), (298, 680)], 7),
        ("arm_lower_r", "elbow_r", "any", [(668, 578), (752, 578), (782, 700), (792, 792), (724, 792), (700, 680)], 7),
        ("hand_l", "wrist_l", "notdark", [(278, 758), (382, 758), (382, 892), (278, 892)], 8),
        ("hand_r", "wrist_r", "notdark", [(733, 748), (818, 748), (818, 892), (733, 892)], 8),
        ("head", "head", "any", [(420, 0), (722, 0), (722, 282), (642, 300), (600, 290), (530, 296), (470, 302), (420, 272)], 9),
    ],
}


# ---- nikita_army (니키타): 군모, 붉은 곱슬 올림머리, 열린 롱코트(의무 완장)·전투복·와이드 팬츠·부츠 (원화 1024x1536)
# 롱코트 자락은 다리와 같은 색이라 색으로 분리할 수 없어, 좌/우 자락을 같은 쪽 다리 파츠에 포함한다(다리가 움직이면 자락도 함께).
NIKITA_ARMY = {
    "src": "nikita_army.png", "classify": "warm", "head_rect": (330, 0, 360, 330),
    "irises": [(522, 161, 19), (601, 185, 15)], "iris_rule": "neutral",   # 청회색 홍채
    "eyes": [(522, 161), (601, 185)], "ground": (540, 1520),
    "bones": [
        ("hip", "", (505, 575)), ("spine", "hip", (500, 500)), ("chest", "spine", (495, 400)),
        ("head", "chest", (500, 270)),
        ("shoulder_l", "chest", (355, 325)), ("elbow_l", "shoulder_l", (305, 590)), ("wrist_l", "elbow_l", (330, 790)),
        ("shoulder_r", "chest", (640, 350)), ("elbow_r", "shoulder_r", (725, 590)), ("wrist_r", "elbow_r", (800, 770)),
        ("hip_l", "hip", (450, 610)), ("knee_l", "hip_l", (380, 995)), ("ankle_l", "knee_l", (300, 1345)),
        ("hip_r", "hip", (585, 610)), ("knee_r", "hip_r", (640, 995)), ("ankle_r", "knee_r", (705, 1335)),
    ],
    "parts": [
        ("hair_back", "head", "hair", [(250, 0), (720, 0), (720, 330), (250, 330)], 0),
        ("foot_l", "ankle_l", "any", [(218, 1318), (395, 1318), (395, 1530), (218, 1530)], 1),
        ("foot_r", "ankle_r", "any", [(636, 1298), (862, 1298), (862, 1530), (636, 1530)], 1),
        ("shin_l", "knee_l", "dark", [(128, 985), (545, 985), (545, 1345), (128, 1345)], 2),
        ("shin_r", "knee_r", "dark", [(535, 985), (950, 985), (950, 1372), (535, 1372)], 2),
        ("thigh_l", "hip_l", "dark", [(150, 560), (545, 560), (545, 1000), (128, 1000)], 3),
        ("thigh_r", "hip_r", "dark", [(535, 560), (900, 560), (950, 1000), (535, 1000)], 3),
        ("hips", "hip", "dark", [(398, 515), (645, 515), (652, 622), (392, 622)], 4),
        ("torso", "chest", "nothair", [(398, 255), (565, 255), (612, 335), (606, 565), (392, 565), (382, 335)], 5),
        ("arm_upper_l", "shoulder_l", "any", [(252, 298), (392, 298), (396, 562), (338, 612), (198, 604), (212, 480)], 6),
        ("arm_upper_r", "shoulder_r", "dark", [(598, 330), (672, 342), (722, 480), (765, 562), (700, 602), (640, 562), (618, 450)], 6),
        ("arm_lower_l", "elbow_l", "skindark", [(198, 560), (348, 560), (338, 640), (362, 800), (296, 800), (252, 640)], 7),
        ("arm_lower_r", "elbow_r", "skindark", [(690, 560), (772, 560), (778, 640), (832, 780), (782, 800), (720, 640)], 7),
        ("hand_l", "wrist_l", "notdark", [(280, 772), (372, 772), (372, 878), (280, 878)], 8),
        ("hand_r", "wrist_r", "notdark", [(766, 698), (848, 698), (848, 882), (766, 882)], 8),
        ("head", "head", "any", [(258, 0), (700, 0), (700, 250), (615, 302), (540, 276), (470, 270), (392, 312), (258, 312)], 9),
    ],
}


CHARACTERS = {"nikita_army": lambda: NIKITA_ARMY, "hero2": lambda: HERO2}


def classify(im, mode="warm"):
    """returns dict of L masks: hair, skin, dark, any
    mode warm   : 붉은 머리 + 밝은 피부 + 검정 의상 (hero)
    mode neutral: 갈색 머리 + 짙은 피부 + 무채색(회흑) 의상 (hero2) — 빨강-파랑 차이로 분리"""
    w, h = im.size
    px = im.load()
    hair = Image.new("L", (w, h), 0); skin = Image.new("L", (w, h), 0); dark = Image.new("L", (w, h), 0); anym = Image.new("L", (w, h), 0)
    hp, sp, dp, ap = hair.load(), skin.load(), dark.load(), anym.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 30:
                continue
            ap[x, y] = 255
            if mode == "neutral":
                rb = r - b
                if rb < 20 and (g - b) < 7:   # 무채색 의상: 밝은 회색 후드부터 검정 바지까지 밝기와 무관
                    dp[x, y] = 255
                elif rb >= 52:
                    sp[x, y] = 255
                else:
                    hp[x, y] = 255
                continue
            sat = (r - b) / max(r, 1)
            if sat > 0.45 and r > 60 and r > g + 15:
                hp[x, y] = 255
            elif r > 150 and g > 100 and b > 80:
                sp[x, y] = 255
            elif max(r, g, b) < 120:
                dp[x, y] = 255
            else:
                dp[x, y] = 255  # 기타(회색/하이라이트)는 의상으로
    return {"hair": hair, "skin": skin, "dark": dark, "any": anym,
            "nothair": ImageChops.subtract(anym, hair),
            "notdark": ImageChops.subtract(anym, dark),
            "skindark": ImageChops.lighter(skin, dark)}


# 원화를 QHD 화면 표시 키(약 300px)의 약 2.5배로 미리 줄여 쓴다 (밉맵과 함께 선명도 확보). 원본 그대로는 5배 축소라 계단 현상.
K = 0.5


def _scale_defs(k):
    global BONES, PARTS, EYES, GROUND
    sp = lambda pt: (round(pt[0] * k), round(pt[1] * k))
    BONES = [(n, p, sp(pos)) for n, p, pos in BONES]
    PARTS = [(n, b, kind, [sp(q) for q in poly], z) for n, b, kind, poly, z in PARTS]
    EYES = [sp(e) for e in EYES]
    GROUND = sp(GROUND)


def build(cid):
    global BONES, PARTS, EYES, GROUND, OUT
    d = CHARACTERS[cid]()
    BONES, PARTS, EYES, GROUND = list(d["bones"]), list(d["parts"]), list(d["eyes"]), d["ground"]
    OUT = os.path.join(ROOT, "assets", "sprites", f"rig_{cid}")
    os.makedirs(OUT, exist_ok=True)
    im = Image.open(os.path.join(ROOT, "assets", "source", d["src"])).convert("RGBA")
    im = im.resize((round(im.width * K), round(im.height * K)), Image.LANCZOS)
    _scale_defs(K)
    w, h = im.size
    cls = classify(im, d["classify"])
    mask_r = build_zone_mask(im, [], "right", rim=max(2, round(11 * K)), smooth=round(90 * K))
    mask_l = build_zone_mask(im, [], "left", rim=max(2, round(11 * K)), smooth=round(90 * K))
    # 눈동자 구역(Z_UNLIT=128): 홍채 원 안에서 흰자·피부를 뺀 홍채·동공 픽셀만. 셰이더가 캐릭터 눈 색을 칠한다.
    # (예전의 눈 주변 큰 타원은 피부까지 덮어 얼굴에서 튀었으므로 쓰지 않음)
    px = im.load()
    for (ix, iy, ir) in d.get("irises", []):
        cx, cy, rr = ix * K, iy * K, ir * K + 0.5
        for y in range(int(cy - rr) - 1, int(cy + rr) + 2):
            for x in range(int(cx - rr) - 1, int(cx + rr) + 2):
                if not (0 <= x < w and 0 <= y < h) or (x - cx) ** 2 + (y - cy) ** 2 > rr * rr:
                    continue
                r, g, b, a = px[x, y]
                if a < 100 or min(r, g, b) > 185:          # 흰자·하이라이트 제외
                    continue
                dark = max(r, g, b) < 75                    # 동공·속눈썹
                if d.get("iris_rule") == "amber":
                    iris = (b < 0.47 * r and r > 60) or (g - b) > 42   # 호박색: 파랑이 적거나(어두운 쪽) 초록-파랑 차이 큼(밝은 쪽). 피부는 b≈0.58r, g-b≈31
                else:
                    iris = (r - b) < 40   # 회색·청색 홍채 (피부는 r-b ≈ 90 이상)
                if dark or iris:
                    mask_r.putpixel((x, y), Z_UNLIT)
                    mask_l.putpixel((x, y), Z_UNLIT)
        # 한 겹 넓히기: 원 안에서 이미 잡힌 픽셀과 맞닿은 '흰자 아닌' 픽셀도 홍채로 (축소 원화의 경계 빈틈 메움)
        for _ in range(2):
            add = []
            for y in range(int(cy - rr) - 1, int(cy + rr) + 2):
                for x in range(int(cx - rr) - 1, int(cx + rr) + 2):
                    if not (1 <= x < w - 1 and 1 <= y < h - 1) or (x - cx) ** 2 + (y - cy) ** 2 > rr * rr:
                        continue
                    if mask_r.getpixel((x, y)) == Z_UNLIT:
                        continue
                    r, g, b, a = px[x, y]
                    if a < 100 or min(r, g, b) > 170:
                        continue
                    if any(mask_r.getpixel((x + dx, y + dy)) == Z_UNLIT for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                        add.append((x, y))
            for q in add:
                mask_r.putpixel(q, Z_UNLIT)
                mask_l.putpixel(q, Z_UNLIT)
    # 정수리(알파 기준)~발바닥 픽셀 높이: 게임이 캐릭터 키(cm)에 맞춰 배율을 정하는 기준
    abox = im.split()[3].point(lambda v: 255 if v > 40 else 0).getbbox()
    figure_px = GROUND[1] - abox[1]
    rig = {"image_size": [w, h], "ground": list(GROUND), "scale": round(0.156 / K, 4), "figure_px": figure_px,
           "bones": [{"name": n, "parent": p, "pos": list(pos)} for n, p, pos in BONES],
           "parts": [], "weapon_bone": "wrist_r", "head_bone": "head",
           "eyes": EYES, "head_rect": [round(v * K) for v in d["head_rect"]]}
    debug = Image.new("RGBA", (w * 2, h), (60, 60, 70, 255))
    debug.alpha_composite(im, (0, 0))
    dd = ImageDraw.Draw(debug)
    palette = [(255, 80, 80), (80, 200, 255), (120, 255, 120), (255, 200, 60), (220, 120, 255), (255, 140, 200), (120, 220, 220)]
    for i, (name, bone, kind, poly, z) in enumerate(PARTS):
        pm = Image.new("L", (w, h), 0)
        ImageDraw.Draw(pm).polygon(poly, fill=255)
        pm = ImageChops.multiply(pm, cls[kind])
        pm = pm.filter(ImageFilter.MaxFilter(3))          # 이음새 1px 팽창 (축소 원화 기준)
        pm = ImageChops.multiply(pm, cls["any"])
        part = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        part.paste(im, (0, 0), pm)
        bbox = pm.getbbox()
        if bbox is None:
            print("EMPTY", name); continue
        crop = part.crop(bbox)
        crop.save(os.path.join(OUT, f"{name}.png"))
        mask_r.crop(bbox).save(os.path.join(OUT, f"{name}_mask_r.png"))
        mask_l.crop(bbox).save(os.path.join(OUT, f"{name}_mask_l.png"))
        rig["parts"].append({"name": name, "bone": bone, "tex": f"{name}.png", "origin": [bbox[0], bbox[1]], "size": [crop.width, crop.height], "z": z})
        col = palette[i % len(palette)]
        dd.polygon(poly, outline=col + (255,), width=3)
        # exploded view on right half
        debug.alpha_composite(crop, (w + bbox[0] + (i % 2) * 40, bbox[1]))
        dd.text((bbox[0] + 4, bbox[1] + 4), name, fill=col + (255,))
    # bones overlay
    bpos = {n: pos for n, p, pos in BONES}
    for n, p, pos in BONES:
        if p:
            dd.line([bpos[p], pos], fill=(255, 255, 0, 255), width=5)
        dd.ellipse([pos[0] - 9, pos[1] - 9, pos[0] + 9, pos[1] + 9], fill=(255, 0, 255, 255))
    debug.save(os.path.join(OUT, "_debug_parts.png"))
    mask_r.save(os.path.join(OUT, "_debug_mask_r.png"))
    with open(os.path.join(OUT, "rig.json"), "w", encoding="utf-8") as f:
        json.dump(rig, f, ensure_ascii=False, indent=1)
    total = sum(os.path.getsize(os.path.join(OUT, fn)) for fn in os.listdir(OUT) if not fn.startswith("_"))
    print(cid, "parts", len(rig["parts"]), "bones", len(BONES), "bytes", total)


def main():
    ids = sys.argv[1:] or list(CHARACTERS)
    snapshot = (BONES, PARTS, EYES, GROUND)
    for cid in ids:
        build(cid)
        globals().update(dict(zip(("BONES", "PARTS", "EYES", "GROUND"), snapshot)))


if __name__ == "__main__":
    main()
