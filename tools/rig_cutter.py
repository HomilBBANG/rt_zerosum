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


# ---- nikita_army (니키타): 군모, 붉은 곱슬 올림머리, 밝은 회색 롱코트(의무 완장)·짙은 전투복·와이드 팬츠·부츠 (원화 1024x1536)
# 롱코트 자락은 다리와 같은 색이라 색으로 분리할 수 없어, 좌/우 자락을 같은 쪽 다리 파츠에 포함한다(다리가 움직이면 자락도 함께).
NIKITA_ARMY = {
    "src": "nikita_army.png", "classify": "warm_gray", "head_rect": (340, 0, 380, 340),
    "irises": [(510, 183, 19), (600, 205, 16)], "iris_rule": "neutral",   # 청회색 홍채
    "eyes": [(510, 183), (600, 205)], "ground": (540, 1525),
    "bones": [
        ("hip", "", (540, 600)), ("spine", "hip", (540, 520)), ("chest", "spine", (540, 420)),
        ("head", "chest", (540, 292)),
        ("shoulder_l", "chest", (392, 372)), ("elbow_l", "shoulder_l", (352, 605)), ("wrist_l", "elbow_l", (330, 800)),
        ("shoulder_r", "chest", (662, 390)), ("elbow_r", "shoulder_r", (715, 605)), ("wrist_r", "elbow_r", (772, 792)),
        ("hip_l", "hip", (480, 632)), ("knee_l", "hip_l", (420, 1020)), ("ankle_l", "knee_l", (322, 1322)),
        ("hip_r", "hip", (610, 632)), ("knee_r", "hip_r", (660, 1020)), ("ankle_r", "knee_r", (712, 1322)),
    ],
    "parts": [
        ("hair_back", "head", "hair", [(250, 0), (760, 0), (760, 400), (250, 400)], 0),
        ("foot_l", "ankle_l", "any", [(222, 1292), (412, 1292), (412, 1530), (222, 1530)], 1),
        ("foot_r", "ankle_r", "any", [(628, 1292), (832, 1292), (832, 1530), (628, 1530)], 1),
        ("shin_l", "knee_l", "dark", [(112, 1000), (548, 1000), (548, 1380), (112, 1380)], 2),
        ("shin_r", "knee_r", "dark", [(538, 1000), (985, 1000), (985, 1410), (538, 1410)], 2),
        ("thigh_l", "hip_l", "dark", [(112, 600), (548, 600), (548, 1012), (112, 1012)], 3),
        ("thigh_r", "hip_r", "dark", [(538, 600), (985, 600), (985, 1012), (538, 1012)], 3),
        ("hips", "hip", "dark", [(428, 558), (652, 558), (662, 652), (424, 652)], 4),
        ("torso", "chest", "nothair", [(430, 288), (602, 288), (652, 380), (652, 592), (430, 592), (418, 380)], 5),
        ("arm_upper_l", "shoulder_l", "any", [(298, 348), (432, 348), (442, 580), (402, 648), (308, 648), (306, 470)], 6),
        ("arm_upper_r", "shoulder_r", "dark", [(628, 368), (692, 388), (732, 500), (752, 590), (692, 648), (650, 560)], 6),
        ("arm_lower_l", "elbow_l", "skindark", [(300, 580), (412, 580), (402, 700), (372, 808), (308, 808), (320, 700)], 7),
        ("arm_lower_r", "elbow_r", "skindark", [(668, 580), (754, 580), (762, 650), (792, 792), (745, 802), (700, 650)], 7),
        ("hand_l", "wrist_l", "notdark", [(278, 780), (378, 780), (378, 908), (278, 908)], 8),
        ("hand_r", "wrist_r", "notdark", [(735, 768), (822, 768), (822, 902), (735, 902)], 8),
        ("head", "head", "any", [(300, 0), (722, 0), (722, 282), (642, 302), (582, 306), (530, 300), (470, 302), (402, 332), (300, 332)], 9),
    ],
}


# ---- kira (키라): 짙은 군모, 갈색 낮은 포니테일, 짙은 회갈색 긴팔 전투복(왼손 주머니), 와이드 카고 팬츠, 검정 부츠 (원화 1024x1536)
# 의상이 무채색(r-b≈15)이고 머리는 갈색(r-b≈30), 피부는 r-b≈80 이라 neutral 분류가 그대로 맞는다.
# 화면 왼쪽 팔은 주머니에 손을 넣은 자세라 아래팔이 안쪽(골반)으로 꺾인다.
KIRA = {
    "src": "kira.png", "classify": "neutral", "head_rect": (400, 0, 320, 300),
    "irises": [(507, 184, 17), (595, 209, 14)], "iris_rule": "neutral",   # 회색 홍채
    "eyes": [(507, 184), (595, 209)], "ground": (545, 1525),
    "bones": [
        ("hip", "", (550, 610)), ("spine", "hip", (550, 520)), ("chest", "spine", (545, 420)),
        ("head", "chest", (545, 295)),
        ("shoulder_l", "chest", (400, 385)), ("elbow_l", "shoulder_l", (320, 610)), ("wrist_l", "elbow_l", (440, 700)),
        ("shoulder_r", "chest", (640, 395)), ("elbow_r", "shoulder_r", (705, 615)), ("wrist_r", "elbow_r", (755, 810)),
        ("hip_l", "hip", (490, 640)), ("knee_l", "hip_l", (410, 1000)), ("ankle_l", "knee_l", (340, 1370)),
        ("hip_r", "hip", (610, 640)), ("knee_r", "hip_r", (650, 1000)), ("ankle_r", "knee_r", (740, 1380)),
    ],
    "parts": [
        ("hair_back", "head", "hair", [(360, 150), (520, 150), (520, 650), (360, 650)], 0),
        ("foot_l", "ankle_l", "any", [(215, 1335), (465, 1335), (465, 1532), (215, 1532)], 1),
        ("foot_r", "ankle_r", "any", [(635, 1335), (875, 1335), (875, 1532), (635, 1532)], 1),
        ("shin_l", "knee_l", "dark", [(245, 990), (560, 990), (515, 1405), (225, 1405)], 2),
        ("shin_r", "knee_r", "dark", [(560, 990), (795, 990), (825, 1425), (575, 1425)], 2),
        ("thigh_l", "hip_l", "dark", [(400, 610), (570, 610), (562, 1010), (255, 1010), (330, 800)], 3),
        ("thigh_r", "hip_r", "dark", [(560, 610), (690, 610), (725, 780), (775, 1010), (560, 1010)], 3),
        ("hips", "hip", "dark", [(428, 565), (665, 565), (670, 662), (424, 662)], 4),
        ("torso", "chest", "skindark", [(425, 290), (640, 290), (665, 400), (655, 600), (440, 600), (432, 400)], 5),
        ("arm_upper_l", "shoulder_l", "dark", [(295, 350), (455, 350), (445, 450), (410, 600), (365, 645), (288, 625), (295, 500)], 6),
        ("arm_upper_r", "shoulder_r", "dark", [(615, 370), (680, 380), (722, 520), (742, 630), (670, 640), (640, 500)], 6),
        ("arm_lower_l", "elbow_l", "skindark", [(288, 590), (392, 590), (432, 668), (456, 746), (374, 746), (288, 662)], 7),
        ("arm_lower_r", "elbow_r", "skindark", [(660, 600), (745, 600), (772, 720), (778, 822), (708, 822), (690, 700)], 7),
        ("hand_l", "wrist_l", "notdark", [(412, 642), (482, 642), (482, 732), (412, 732)], 8),
        ("hand_r", "wrist_r", "notdark", [(718, 788), (812, 788), (812, 948), (718, 948)], 8),
        ("head", "head", "any", [(398, 0), (716, 0), (716, 192), (652, 252), (602, 286), (555, 300), (500, 282), (470, 262), (398, 245)], 9),
    ],
}


# ---- alma (앨마): 금갈색 올림머리, 밝은 회색 롱코트(적십자 완장)·짙은 전투복·카고 팬츠·부츠 (원화 1024x1536)
# 니키타처럼 코트 자락은 다리 파츠에 포함. 머리색과 피부색의 색상이 거의 같아(r-b 56~77 vs 87) 머리 전용 파츠 없이 머리(번 포함)를 head 하나로.
ALMA = {
    "src": "alma.png", "classify": "warm_gray", "head_rect": (360, 0, 330, 300),
    "irises": [(535, 161, 12), (602, 192, 9)], "iris_rule": "neutral",   # 회녹색 홍채
    "eyes": [(535, 161), (602, 192)], "ground": (548, 1526),
    "bones": [
        ("hip", "", (575, 590)), ("spine", "hip", (570, 500)), ("chest", "spine", (560, 410)),
        ("head", "chest", (520, 295)),
        ("shoulder_l", "chest", (388, 335)), ("elbow_l", "shoulder_l", (358, 600)), ("wrist_l", "elbow_l", (380, 795)),
        ("shoulder_r", "chest", (628, 365)), ("elbow_r", "shoulder_r", (708, 610)), ("wrist_r", "elbow_r", (775, 795)),
        ("hip_l", "hip", (520, 620)), ("knee_l", "hip_l", (438, 1016)), ("ankle_l", "knee_l", (318, 1376)),
        ("hip_r", "hip", (630, 620)), ("knee_r", "hip_r", (698, 1016)), ("ankle_r", "knee_r", (768, 1386)),
    ],
    "parts": [
        ("foot_l", "ankle_l", "any", [(200, 1330), (425, 1330), (425, 1532), (200, 1532)], 1),
        ("foot_r", "ankle_r", "any", [(640, 1335), (905, 1335), (905, 1532), (640, 1532)], 1),
        ("shin_l", "knee_l", "dark", [(150, 1010), (578, 1010), (560, 1392), (150, 1392)], 2),
        ("shin_r", "knee_r", "dark", [(578, 1010), (925, 1010), (925, 1400), (575, 1400)], 2),
        ("thigh_l", "hip_l", "dark", [(150, 590), (578, 590), (578, 1018), (150, 1018)], 3),
        ("thigh_r", "hip_r", "dark", [(578, 590), (925, 590), (925, 1018), (578, 1018)], 3),
        ("hips", "hip", "dark", [(470, 540), (680, 540), (690, 640), (465, 640)], 4),
        ("torso", "chest", "any", [(410, 280), (640, 280), (660, 400), (655, 590), (430, 590), (405, 400)], 5),
        ("arm_upper_l", "shoulder_l", "any", [(298, 322), (425, 315), (435, 420), (420, 610), (300, 620), (296, 470)], 6),
        ("arm_lower_l", "elbow_l", "dark", [(296, 588), (428, 588), (428, 805), (296, 805)], 7),
        ("arm_upper_r", "shoulder_r", "dark", [(618, 352), (692, 368), (735, 520), (742, 622), (680, 627), (650, 480)], 6),
        ("arm_lower_r", "elbow_r", "dark", [(668, 595), (748, 595), (802, 720), (808, 808), (738, 808), (698, 700)], 7),
        ("hand_l", "wrist_l", "notdark", [(328, 778), (432, 778), (432, 942), (328, 942)], 8),
        ("hand_r", "wrist_r", "notdark", [(732, 778), (832, 778), (832, 935), (732, 935)], 8),
        ("head", "head", "any", [(355, 8), (695, 8), (695, 232), (625, 252), (585, 282), (548, 288), (500, 302), (465, 292), (355, 292)], 9),
    ],
}


# ---- ethan (이선): 짙은 갈색 짧은 머리, 짙은 회갈색 오버 재킷·검정 티·카고 팬츠·부츠, 양손 주머니 (원화 1024x1536)
ETHAN = {
    "src": "ethan.png", "classify": "neutral", "head_rect": (370, 0, 280, 280),
    "irises": [(445, 172, 8), (510, 147, 10)], "iris_rule": "neutral",   # 검정 홍채
    "eyes": [(445, 172), (510, 147)], "ground": (560, 1526),
    "bones": [
        ("hip", "", (560, 600)), ("spine", "hip", (560, 500)), ("chest", "spine", (545, 400)),
        ("head", "chest", (515, 262)),
        ("shoulder_l", "chest", (405, 315)), ("elbow_l", "shoulder_l", (335, 560)), ("wrist_l", "elbow_l", (485, 670)),
        ("shoulder_r", "chest", (680, 345)), ("elbow_r", "shoulder_r", (785, 560)), ("wrist_r", "elbow_r", (775, 685)),
        ("hip_l", "hip", (500, 630)), ("knee_l", "hip_l", (430, 1000)), ("ankle_l", "knee_l", (405, 1350)),
        ("hip_r", "hip", (630, 630)), ("knee_r", "hip_r", (650, 1000)), ("ankle_r", "knee_r", (700, 1420)),
    ],
    "parts": [
        ("foot_l", "ankle_l", "any", [(305, 1318), (505, 1318), (505, 1532), (305, 1532)], 1),
        ("foot_r", "ankle_r", "any", [(545, 1368), (865, 1368), (865, 1532), (545, 1532)], 1),
        ("shin_l", "knee_l", "dark", [(295, 990), (568, 990), (520, 1338), (300, 1338)], 2),
        ("shin_r", "knee_r", "dark", [(568, 990), (812, 990), (825, 1432), (535, 1432)], 2),
        ("thigh_l", "hip_l", "dark", [(330, 600), (570, 600), (568, 1000), (295, 1000)], 3),
        ("thigh_r", "hip_r", "dark", [(570, 600), (832, 600), (832, 1000), (568, 1000)], 3),
        ("hips", "hip", "dark", [(448, 558), (702, 558), (706, 652), (444, 652)], 4),
        ("torso", "chest", "skindark", [(400, 228), (645, 228), (702, 340), (706, 600), (400, 600), (394, 340)], 5),
        ("arm_upper_l", "shoulder_l", "dark", [(298, 288), (452, 288), (442, 420), (402, 560), (372, 602), (298, 602), (292, 450)], 6),
        ("arm_lower_l", "elbow_l", "dark", [(296, 540), (402, 540), (472, 628), (502, 722), (418, 732), (328, 662), (296, 602)], 7),
        ("arm_upper_r", "shoulder_r", "dark", [(648, 318), (732, 338), (792, 478), (822, 582), (762, 602), (690, 470)], 6),
        ("arm_lower_r", "elbow_r", "dark", [(738, 538), (828, 538), (834, 702), (802, 724), (758, 702), (733, 620)], 7),
        ("hand_l", "wrist_l", "notdark", [(452, 628), (522, 628), (522, 722), (452, 722)], 8),
        ("hand_r", "wrist_r", "notdark", [(742, 638), (812, 638), (812, 732), (742, 732)], 8),
        ("head", "head", "any", [(368, 0), (642, 0), (642, 202), (602, 232), (562, 252), (492, 258), (440, 248), (368, 192)], 9),
    ],
}


# ---- dan (단): 민머리, 짙은 회갈색 오버 재킷(소매 걷음)·남색 티·카고 팬츠·부츠, 양손 주머니, 큰 체격 (원화 1024x1536)
DAN = {
    "src": "dan.png", "classify": "neutral", "head_rect": (470, 0, 260, 230),
    "irises": [(612, 97, 8), (675, 126, 7)], "iris_rule": "neutral",   # 청회색 홍채
    "eyes": [(612, 97), (675, 126)], "ground": (570, 1530),
    "bones": [
        ("hip", "", (600, 690)), ("spine", "hip", (590, 560)), ("chest", "spine", (570, 420)),
        ("head", "chest", (560, 235)),
        ("shoulder_l", "chest", (300, 270)), ("elbow_l", "shoulder_l", (245, 560)), ("wrist_l", "elbow_l", (420, 770)),
        ("shoulder_r", "chest", (620, 310)), ("elbow_r", "shoulder_r", (790, 560)), ("wrist_r", "elbow_r", (785, 770)),
        ("hip_l", "hip", (520, 720)), ("knee_l", "hip_l", (430, 1050)), ("ankle_l", "knee_l", (360, 1420)),
        ("hip_r", "hip", (680, 720)), ("knee_r", "hip_r", (700, 1050)), ("ankle_r", "knee_r", (760, 1430)),
    ],
    "parts": [
        ("foot_l", "ankle_l", "any", [(245, 1368), (455, 1368), (455, 1536), (245, 1536)], 1),
        ("foot_r", "ankle_r", "any", [(610, 1378), (930, 1378), (930, 1536), (610, 1536)], 1),
        ("shin_l", "knee_l", "dark", [(235, 1040), (602, 1040), (520, 1432), (245, 1432)], 2),
        ("shin_r", "knee_r", "dark", [(602, 1040), (895, 1040), (895, 1432), (580, 1432)], 2),
        ("thigh_l", "hip_l", "dark", [(275, 690), (622, 690), (602, 1050), (235, 1050)], 3),
        ("thigh_r", "hip_r", "dark", [(622, 690), (905, 690), (895, 1050), (602, 1050)], 3),
        ("hips", "hip", "dark", [(468, 628), (742, 628), (748, 722), (462, 722)], 4),
        ("torso", "chest", "skindark", [(318, 175), (665, 175), (705, 300), (722, 560), (702, 662), (440, 702), (330, 702), (298, 560), (298, 300)], 5),
        ("arm_upper_l", "shoulder_l", "dark", [(178, 218), (342, 198), (402, 330), (402, 482), (182, 482), (178, 400)], 6),
        ("arm_lower_l", "elbow_l", "skindark", [(182, 445), (402, 445), (405, 560), (472, 700), (474, 812), (382, 812), (258, 652), (186, 622)], 7),
        ("arm_upper_r", "shoulder_r", "dark", [(608, 288), (702, 298), (772, 438), (802, 528), (742, 558), (690, 450)], 6),
        ("arm_lower_r", "elbow_r", "skindark", [(728, 518), (842, 518), (842, 652), (822, 802), (742, 802), (733, 640)], 7),
        ("hand_l", "wrist_l", "notdark", [(392, 712), (482, 712), (482, 822), (392, 822)], 8),
        ("hand_r", "wrist_r", "notdark", [(738, 702), (832, 702), (832, 802), (738, 802)], 8),
        ("head", "head", "any", [(478, 0), (722, 0), (722, 172), (662, 216), (630, 220), (560, 192), (520, 162), (478, 152)], 9),
    ],
}


# ---- ghoul (구울, 괴물): 붉은 가시 살점에 찢긴 정장, 크게 벌린 입이 왼쪽을 향함 (원화 1024x1536). 키 2m, 적 전용.
# 색이 아니라 영역으로만 나눈다(kind "any"). 오른팔 아래 갈퀴 손과 오른다리가 얽혀 있어 경계는 근사.
GHOUL = {
    "src": "ghoul.png", "classify": "warm", "head_rect": (40, 0, 580, 620),
    "irises": [], "eyes": [], "ground": (500, 1505),
    "bones": [
        ("hip", "", (560, 640)), ("spine", "hip", (530, 520)), ("chest", "spine", (500, 400)),
        ("head", "chest", (380, 330)),
        ("shoulder_l", "chest", (440, 560)), ("elbow_l", "shoulder_l", (300, 660)), ("wrist_l", "elbow_l", (200, 740)),
        ("shoulder_r", "chest", (620, 300)), ("elbow_r", "shoulder_r", (860, 620)), ("wrist_r", "elbow_r", (920, 1000)),
        ("hip_l", "hip", (500, 660)), ("knee_l", "hip_l", (330, 1000)), ("ankle_l", "knee_l", (220, 1290)),
        ("hip_r", "hip", (620, 660)), ("knee_r", "hip_r", (760, 920)), ("ankle_r", "knee_r", (760, 1250)),
    ],
    "parts": [
        ("foot_l", "ankle_l", "any", [(0, 1240), (500, 1240), (500, 1536), (0, 1536)], 1),
        ("shin_l", "knee_l", "any", [(140, 980), (430, 980), (410, 1292), (140, 1292)], 2),
        ("shin_r", "knee_r", "any", [(620, 900), (830, 940), (870, 1120), (840, 1470), (620, 1470)], 2),
        ("thigh_l", "hip_l", "any", [(330, 640), (565, 640), (490, 900), (420, 1010), (300, 1010), (330, 800)], 3),
        ("thigh_r", "hip_r", "any", [(560, 600), (780, 600), (820, 960), (700, 980), (560, 760)], 3),
        ("hips", "hip", "any", [(420, 580), (700, 580), (700, 720), (420, 720)], 4),
        ("torso", "chest", "any", [(400, 170), (720, 170), (740, 420), (700, 640), (430, 640), (400, 450)], 5),
        ("arm_upper_l", "shoulder_l", "any", [(270, 540), (500, 520), (500, 650), (310, 720), (250, 640)], 6),
        ("arm_upper_r", "shoulder_r", "any", [(560, 150), (970, 150), (970, 560), (870, 700), (760, 640), (620, 420)], 6),
        ("arm_lower_l", "elbow_l", "any", [(0, 580), (320, 600), (320, 990), (0, 990)], 7),
        ("arm_lower_r", "elbow_r", "any", [(760, 560), (1024, 560), (1024, 1470), (845, 1470), (870, 1120), (820, 960), (760, 900)], 7),
        ("head", "head", "any", [(30, 0), (620, 0), (470, 170), (420, 330), (330, 470), (300, 560), (260, 600), (130, 600), (30, 560)], 9),
    ],
}


# ---- slime (슬라임, 괴물): 남청색 점액 덩어리, 입·눈이 오른쪽 (원화 1536x1024, 가로로 큼). 키 2m, 적 전용.
# 팔다리가 없어 사람 뼈대를 그대로 두고 파츠는 몸통(엉덩이 본)과 앞쪽 입 덩어리(머리 본) 둘만 —
# 대기 숨쉬기·피격·공격 시 머리 본 회전으로 입 쪽이 움찔/덮침. 이음새가 벌어지지 않게 두 파츠를 겹치게 자름.
SLIME = {
    "src": "slime.png", "classify": "warm", "head_rect": (900, 0, 636, 700),
    "irises": [], "eyes": [], "ground": (760, 990),
    "bones": [
        ("hip", "", (700, 820)), ("spine", "hip", (720, 620)), ("chest", "spine", (760, 420)),
        ("head", "chest", (980, 420)),
        ("shoulder_l", "chest", (560, 450)), ("elbow_l", "shoulder_l", (480, 600)), ("wrist_l", "elbow_l", (420, 760)),
        ("shoulder_r", "chest", (900, 450)), ("elbow_r", "shoulder_r", (1000, 600)), ("wrist_r", "elbow_r", (1060, 760)),
        ("hip_l", "hip", (600, 850)), ("knee_l", "hip_l", (560, 920)), ("ankle_l", "knee_l", (540, 980)),
        ("hip_r", "hip", (820, 850)), ("knee_r", "hip_r", (860, 920)), ("ankle_r", "knee_r", (880, 980)),
    ],
    "parts": [
        ("body", "hip", "any", [(0, 0), (1060, 0), (1060, 1024), (0, 1024)], 1),
        ("head", "head", "any", [(960, 0), (1536, 0), (1536, 1024), (960, 1024)], 9),
    ],
}


CHARACTERS = {"nikita_army": lambda: NIKITA_ARMY, "hero2": lambda: HERO2, "kira": lambda: KIRA,
              "alma": lambda: ALMA, "ethan": lambda: ETHAN, "dan": lambda: DAN,
              "ghoul": lambda: GHOUL, "slime": lambda: SLIME}


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
            if mode == "warm_gray":
                # 붉은 머리 + 밝은 피부 + 무채색 의상(밝은 회색 코트~검정 부츠, 밝기 무관)
                if (r - b) / max(r, 1) > 0.45 and r > 60 and r > g + 15:
                    hp[x, y] = 255
                elif (r - b) < 32 and (g - b) < 10:
                    dp[x, y] = 255
                else:
                    sp[x, y] = 255
                continue
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
    # 3D 배경의 그림자용 실루엣(원화 알파, 절반 해상도): 캡슐 대신 캐릭터 모양 그림자를 드리운다
    sil = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    sil.putalpha(im.split()[3].point(lambda v: 255 if v > 100 else 0))
    sil.resize((w // 2, h // 2), Image.LANCZOS).save(os.path.join(OUT, "silhouette.png"))
    rig = {"image_size": [w, h], "ground": list(GROUND), "scale": round(0.156 / K, 4), "figure_px": figure_px,
           "bones": [{"name": n, "parent": p, "pos": list(pos)} for n, p, pos in BONES],
           "parts": [], "weapon_bone": "wrist_r", "head_bone": "head",
           "eyes": EYES, "head_rect": [round(v * K) for v in d["head_rect"]],
           "silhouette": "silhouette.png"}
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
