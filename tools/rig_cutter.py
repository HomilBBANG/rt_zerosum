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

SRC = os.path.join(ROOT, "assets", "source", "char_ref.png")
OUT = os.path.join(ROOT, "assets", "sprites", "rig_hero")
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

# ---- hero2 (하나): 갈색 곱슬 포니테일, 밝은 회색 후드 + 검정 탱크톱·와이드 팬츠, 흰 운동화 (원화 1024x1536)
HERO2 = {
    "src": "char_ref2.png", "classify": "neutral", "head_rect": (400, 0, 310, 290),
    "eyes": [(545, 160), (635, 170)], "ground": (580, 1515),
    "bones": [
        ("hip", "", (575, 640)), ("spine", "hip", (575, 540)), ("chest", "spine", (565, 420)),
        ("head", "chest", (555, 275)),
        ("shoulder_l", "chest", (385, 330)), ("elbow_l", "shoulder_l", (335, 620)), ("wrist_l", "elbow_l", (335, 820)),
        ("shoulder_r", "chest", (655, 330)), ("elbow_r", "shoulder_r", (745, 630)), ("wrist_r", "elbow_r", (770, 830)),
        ("hip_l", "hip", (510, 690)), ("knee_l", "hip_l", (420, 1090)), ("ankle_l", "knee_l", (310, 1440)),
        ("hip_r", "hip", (640, 690)), ("knee_r", "hip_r", (680, 1090)), ("ankle_r", "knee_r", (720, 1450)),
    ],
    "parts": [
        ("hair_back", "head", "notdark", [(290, 0), (720, 0), (720, 470), (290, 470)], 0),
        ("foot_l", "ankle_l", "any", [(230, 1420), (400, 1420), (400, 1526), (230, 1526)], 1),
        ("foot_r", "ankle_r", "any", [(620, 1425), (822, 1425), (822, 1526), (620, 1526)], 1),
        ("shin_l", "knee_l", "dark", [(225, 1080), (575, 1080), (560, 1445), (225, 1445)], 2),
        ("shin_r", "knee_r", "dark", [(572, 1080), (792, 1080), (802, 1452), (560, 1452)], 2),
        ("thigh_l", "hip_l", "dark", [(410, 640), (585, 640), (575, 1100), (250, 1100)], 3),
        ("thigh_r", "hip_r", "dark", [(578, 640), (722, 640), (792, 1100), (570, 1100)], 3),
        ("hips", "hip", "dark", [(430, 560), (710, 560), (715, 700), (425, 700)], 4),
        ("torso", "chest", "skindark", [(440, 280), (690, 280), (702, 400), (702, 722), (470, 748), (440, 420)], 5),
        ("arm_upper_l", "shoulder_l", "dark", [(300, 295), (472, 295), (476, 748), (420, 748), (420, 628), (275, 628), (258, 560)], 6),
        ("arm_upper_r", "shoulder_r", "dark", [(618, 295), (722, 318), (772, 520), (782, 628), (700, 628), (690, 450)], 6),
        ("arm_lower_l", "elbow_l", "any", [(282, 598), (420, 598), (400, 700), (382, 815), (292, 815), (282, 700)], 7),
        ("arm_lower_r", "elbow_r", "any", [(700, 600), (792, 600), (798, 825), (728, 825), (712, 700)], 7),
        ("hand_l", "wrist_l", "notdark", [(288, 800), (385, 800), (385, 918), (288, 918)], 8),
        ("hand_r", "wrist_r", "notdark", [(738, 808), (828, 808), (828, 918), (738, 918)], 8),
        ("head", "head", "any", [(400, 0), (712, 0), (712, 282), (642, 300), (600, 286), (530, 292), (470, 300), (400, 262)], 9),
    ],
}


def _hero_def():
    return {"src": "char_ref.png", "classify": "warm", "head_rect": HEAD_RECT, "eyes": EYES, "ground": GROUND,
            "bones": BONES, "parts": PARTS}


CHARACTERS = {"hero": _hero_def, "hero2": lambda: HERO2}


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


# 원화를 화면 표시 크기의 약 2배(레티나 대응)로 미리 줄여 쓴다. 1475px 키를 그대로 쓰면 10배 축소로 계단 현상이 난다.
K = 0.36


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
    # (예전: 눈 주변 '조명 무시' 타원 → 얼굴에서 눈 주변만 원래 색으로 튀어 제거. 셰이더가 원화 명암을 유지하므로 불필요)
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
