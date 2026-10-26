"""사용자가 부위별로 나눈 파츠 시트 → Skeleton2D 리그 (assets/sprites/rig_<id>/).

시트 한 장 = 왼쪽에 원본 전신 + 오른쪽에 부위 파츠(투명 배경, 원본과 같은 높이로 가로로 벌려 놓은 배치).
파츠는 덩어리(연결된 불투명 영역)로 자동 분리하고, 설정(CONFIGS)의 대략 위치로 이름을 붙인다.
조립: 관절끼리 잇는다 (아래팔 윗끝 → 위팔 아랫끝 등, 겹침 px 은 설정). 시트 좌표 그대로 → 끝에 키 760px 로 축소.
눈동자: 머리 파츠에서 홍채(원)를 따로 떼어 움직이게 한다 — 눈 테두리(소켓) 다각형 안에서만 보이게 셰이더로 자름,
       머리 그림의 홍채 자리는 흰자로 채움. 소켓·홍채 원은 설정에 손으로 잰 값(머리 파츠 좌표).

사용: python3 tools/rig_from_parts.py kira   (시트: assets/source/kira_parts_sheet.png)
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from gen_sprites import build_zone_mask, Z_UNLIT  # noqa: E402

FIGURE_PX = 760          # 정수리~발 화면 원화 픽셀 (다른 리그와 같은 기준)
CANVAS = (560, 800)

CONFIGS = {
    "kira": {
        "sheet": "assets/source/kira_parts_sheet.png",
        # 이름: 시트 위 대략 중심 (_l = 화면 왼쪽)
        "parts": {
            "original": (280, 540), "head": (779, 143), "hair_tail": (1244, 223), "hair_back": (1016, 142),
            "torso": (936, 394), "arm_upper_l": (697, 368), "arm_upper_r": (1197, 368),
            "arm_lower_l": (660, 534), "arm_lower_r": (1235, 534), "hand_l": (626, 679), "hand_r": (1270, 679),
            "hips": (938, 612), "thigh_l": (760, 652), "thigh_r": (1115, 652), "shin_l": (721, 837), "shin_r": (1154, 843),
            "foot_l": (665, 1003), "foot_r": (1206, 1001),
        },
        "flip": ["hair_tail"],               # 원본과 좌우가 반대로 그려진 파츠
        # 몸통 파츠의 소매를 잘라냄 (팔 파츠가 대신): y → 남길 x 범위 (시트 좌표, 사이는 선형)
        "torso_keep": {"left": [(0, -1), (288, 790), (322, 866), (455, 862), (472, 830), (9999, 830)],
                       "right": [(0, 9999), (288, 1082), (322, 1010), (455, 1013), (472, 1042), (9999, 1042)]},
        # 이음매의 원통 안쪽(아주 어두운 타원) 지우기: (파츠, 끝, 띠 px) — 겹쳐서 가려지는 쪽
        "openings": [("torso", "bottom", 30), ("arm_upper_l", "bottom", 28), ("arm_upper_r", "bottom", 28),
                     ("arm_lower_l", "top", 24), ("arm_lower_r", "top", 24), ("thigh_l", "top", 30), ("thigh_r", "top", 30),
                     ("thigh_l", "bottom", 34), ("thigh_r", "bottom", 34), ("foot_l", "top", 30), ("foot_r", "top", 30)],
        "crop_top": {"hips": 28},
        "stretch_y": {"thigh_l": 1.18, "thigh_r": 1.18, "shin_l": 1.12, "shin_r": 1.12},   # 원본 다리 길이에 맞춤            # 반바지 허리띠는 몸통 허리띠와 겹치므로 잘라냄
        # 조립 순서 (시트 좌표). put = 그 점에 앵커, chain = 부모 아랫끝에 자식 윗끝 (겹침 px, 다리는 반바지 왼/오른 구멍), rot = 윗끝 기준 회전(도, +=시계 반대)
        "steps": [
            ("put", "head", (932, 288), "bottom"),          # 목 아래 끝 → 깃 안쪽
            ("chain", "hips", "torso", 18, None),           # 반바지 윗단을 재킷 밑단 안으로
            ("put", "arm_upper_l", (812, 292), "top"), ("rot", "arm_upper_l", -5),
            ("put", "arm_upper_r", (1060, 292), "top"), ("rot", "arm_upper_r", 5),
            ("chain", "arm_lower_l", "arm_upper_l", 16, None), ("rot", "arm_lower_l", -4),
            ("chain", "arm_lower_r", "arm_upper_r", 16, None), ("rot", "arm_lower_r", 4),
            ("chain", "hand_l", "arm_lower_l", 14, None), ("rot", "hand_l", -4),
            ("chain", "hand_r", "arm_lower_r", 14, None), ("rot", "hand_r", 4),
            ("chain", "thigh_l", "hips", 26, "left"), ("rot", "thigh_l", -9),
            ("chain", "thigh_r", "hips", 26, "right"), ("rot", "thigh_r", 11),
            ("chain", "shin_l", "thigh_l", 10, None), ("rot", "shin_l", -7),
            ("chain", "shin_r", "thigh_r", 10, None), ("rot", "shin_r", 15),
            ("chain", "foot_l", "shin_l", 40, None),
            ("chain", "foot_r", "shin_r", 40, None),
        ],
        # 머리 기준 상대 위치 (머리 파츠 좌표)
        "hair": {"hair_back": (40, 46), "hair_tail": ("tie", (78, 114), (58, 208))},
        "z": ["hair_tail", "hair_back", "head", "foot_l", "foot_r", "shin_l", "shin_r", "thigh_l", "thigh_r", "hips", "torso",
              "hand_l", "hand_r", "arm_lower_l", "arm_lower_r", "arm_upper_l", "arm_upper_r"],
        "bones": {"hair_tail": "head", "hair_back": "head", "head": "head", "torso": "chest", "hips": "hip",
                  "arm_upper_l": "shoulder_l", "arm_upper_r": "shoulder_r", "arm_lower_l": "elbow_l", "arm_lower_r": "elbow_r",
                  "hand_l": "wrist_l", "hand_r": "wrist_r", "thigh_l": "hip_l", "thigh_r": "hip_r", "shin_l": "knee_l",
                  "shin_r": "knee_r", "foot_l": "ankle_l", "foot_r": "ankle_r"},
        # 눈 (머리 파츠 좌표): 소켓 = 속눈썹 아래 ~ 아래 눈꺼풀 위 다각형, 홍채 원 (중심, 반지름), 움직임 범위 px
        "eyes": [
            {"socket": [(57, 135), (65, 134.5), (72, 135.5), (80, 137), (88, 139.5), (95, 142.5), (100, 145.5), (104, 148.5),
                        (100, 150.5), (95, 153), (90, 155), (85, 156), (80, 156.5), (75, 156), (70, 155), (65, 152.5), (61, 148.5), (58, 142)],
             "iris": (78, 142.2, 13.5)},
            {"socket": [(134, 153), (137, 150), (140, 148.5), (145, 147), (150, 146), (160, 145.8), (167, 145.8), (172, 146.5),
                        (170, 152), (167, 157), (163, 160), (158, 162.5), (152, 163.5), (146, 163.5), (141, 162), (137, 159.5), (135, 156.5)],
             "iris": (146.5, 149.6, 12.5)},
        ],
        "eye_range": (4.5, 1.5),
    },
}


# ---------------------------------------------------------------- 시트 분리
def load_parts(cfg):
    sheet = Image.open(os.path.join(ROOT, cfg["sheet"])).convert("RGBA")
    A = np.array(sheet)
    lab, _n = ndimage.label(A[..., 3] > 20)
    comps = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if (lab[sl] == i + 1).sum() >= 300:
            comps.append((i + 1, (sl[1].start, sl[0].start, sl[1].stop, sl[0].stop)))
    parts = {}
    for name, (cx, cy) in cfg["parts"].items():
        cid, box = min(comps, key=lambda c: ((c[1][0] + c[1][2]) / 2 - cx) ** 2 + ((c[1][1] + c[1][3]) / 2 - cy) ** 2)
        x0, y0, x1, y1 = box
        p = A[y0:y1, x0:x1].copy()
        p[..., 3] = np.where(lab[y0:y1, x0:x1] == cid, p[..., 3], 0)
        parts[name] = {"img": p, "pos": [float(x0), float(y0)]}   # pos = 시트(조립) 좌표의 왼쪽 위
    for name in cfg.get("flip", []):
        parts[name]["img"] = parts[name]["img"][:, ::-1].copy()
    return parts


def band_center(img, where, frac=0.06, half=None):
    a = img[..., 3] > 100
    if half == "left":
        a = a.copy(); a[:, img.shape[1] // 2:] = False
    elif half == "right":
        a = a.copy(); a[:, :img.shape[1] // 2] = False
    ys = np.where(a.any(1))[0]
    h = ys[-1] - ys[0] + 1
    n = max(3, int(h * frac))
    rows = range(ys[0], ys[0] + n) if where == "top" else range(ys[-1] - n + 1, ys[-1] + 1)
    xs = np.concatenate([np.where(a[y])[0] for y in rows])
    return (float(xs.min() + xs.max()) / 2.0, float(ys[0] if where == "top" else ys[-1]))


def remove_opening(p, where, band):
    """원통 끝의 안쪽(아주 어두운 큰 덩어리)을 투명하게 — 끝에서 band px 안에서만"""
    img = p["img"]
    a = img[..., 3] > 100
    ys = np.where(a.any(1))[0]
    L = img[..., :3].astype(np.float32).mean(-1)
    zone = np.zeros(a.shape, bool)
    if where == "top":
        zone[ys[0]:ys[0] + band] = True
    else:
        zone[ys[-1] - band + 1:ys[-1] + 1] = True
    dark = a & zone & (L < 46)
    lab, n = ndimage.label(dark)
    for i in range(1, n + 1):
        m = lab == i
        if m.sum() >= 40:
            m = ndimage.binary_dilation(m, iterations=1) & zone & (L < 60)
            img[m, 3] = 0


def rotate_part(p, deg, pivot_local):
    """파츠 그림을 pivot(파츠 좌표) 기준으로 회전 (+ = 시계 반대), 위치 보정"""
    img = Image.fromarray(p["img"])
    pad = int(max(img.size) * 0.5) + 4
    big = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad))
    big.paste(img, (pad, pad))
    c = (pivot_local[0] + pad, pivot_local[1] + pad)
    rot = big.rotate(deg, resample=Image.BICUBIC, center=c)
    bb = rot.getbbox()
    rot = rot.crop(bb)
    p["img"] = np.array(rot)
    p["pos"] = [p["pos"][0] - pad + bb[0], p["pos"][1] - pad + bb[1]]


def trim_torso(p, keep):
    img = p["img"]
    x0, y0 = p["pos"]
    def lerp(pts, y):
        for (ya, xa), (yb, xb) in zip(pts, pts[1:]):
            if ya <= y <= yb:
                t = 0 if yb == ya else (y - ya) / (yb - ya)
                return xa + (xb - xa) * t
        return pts[-1][1]
    for yy in range(img.shape[0]):
        y = y0 + yy
        lx, rx = lerp(keep["left"], y), lerp(keep["right"], y)
        xs = x0 + np.arange(img.shape[1])
        img[yy, (xs < lx) | (xs > rx), 3] = 0


# ---------------------------------------------------------------- 눈
def split_eyes(head, eyes):
    """머리 그림에서 홍채를 떼어 냄 → (흰자로 채운 머리, [{iris RGBA, origin(머리 좌표), socket L 마스크(머리 크기)}])"""
    H = head.astype(np.float32)
    hh, ww = H.shape[:2]
    L = H[..., :3].mean(-1)
    out = H.copy()
    res = []
    for e in eyes:
        sock_img = Image.new("L", (ww * 4, hh * 4), 0)
        ImageDraw.Draw(sock_img).polygon([(x * 4, y * 4) for x, y in e["socket"]], fill=255)
        sock = np.array(sock_img.resize((ww, hh), Image.LANCZOS)).astype(np.float32) / 255.0
        S = sock > 0.5
        cx, cy, r = e["iris"]
        yy, xx = np.mgrid[0:hh, 0:ww]
        d = np.hypot(xx + 0.5 - cx, yy + 0.5 - cy)
        sclera = S & (L > 178)
        iris_vis = S & ~sclera & (d <= r + 0.5)
        # 흰자 채우기: 같은 줄 흰자 평균 (없으면 전체 평균)
        mean_all = H[sclera][:, :3].mean(0) if sclera.any() else np.array([235, 235, 235])
        hole = S & ~sclera
        for y in np.where(hole.any(1))[0]:
            row = sclera[y]
            col = H[y][row][:, :3].mean(0) if row.sum() >= 2 else mean_all
            out[y, hole[y], :3] = col * 0.7 + mean_all * 0.3
        # 경계 부드럽게
        blur = ndimage.uniform_filter(out[..., :3], size=(3, 3, 1))
        out[..., :3] = np.where(hole[..., None], blur, out[..., :3])
        # 홍채 원판: 보이는 홍채는 그대로, 가려진 곳은 같은 반지름의 가장 가까운 각도 색
        R = int(math.ceil(r)) + 2
        ox, oy = int(math.floor(cx)) - R, int(math.floor(cy)) - R
        disk = np.zeros((2 * R, 2 * R, 4), np.float32)
        vy, vx = np.where(iris_vis)
        vr = np.hypot(vx + 0.5 - cx, vy + 0.5 - cy)
        va = np.arctan2(vy + 0.5 - cy, vx + 0.5 - cx)
        for j in range(2 * R):
            for i in range(2 * R):
                px, py = ox + i + 0.5, oy + j + 0.5
                dd = math.hypot(px - cx, py - cy)
                cov = min(1.0, max(0.0, r + 0.5 - dd))
                if cov <= 0:
                    continue
                xi, yi = ox + i, oy + j
                if 0 <= xi < ww and 0 <= yi < hh and iris_vis[yi, xi]:
                    c = H[yi, xi, :3]
                else:
                    ang = math.atan2(py - cy, px - cx)
                    cost = np.abs(vr - dd) * 2.0 + np.abs(np.angle(np.exp(1j * (va - ang)))) * dd * 0.6
                    k = int(np.argmin(cost))
                    c = H[vy[k], vx[k], :3]
                disk[j, i, :3] = c
                disk[j, i, 3] = 255.0 * cov
        res.append({"iris": disk.astype(np.uint8), "origin": (ox, oy), "socket": (sock * 255).astype(np.uint8)})
    return np.clip(out, 0, 255).astype(np.uint8), res


# ---------------------------------------------------------------- 조립
def build(cid):
    cfg = CONFIGS[cid]
    parts = load_parts(cfg)
    orig = parts.pop("original")
    trim_torso(parts["torso"], cfg["torso_keep"])
    for name, n in cfg.get("crop_top", {}).items():
        img = parts[name]["img"]
        ys = np.where((img[..., 3] > 100).any(1))[0]
        img[:ys[0] + n, :, 3] = 0
    for name, k in cfg.get("stretch_y", {}).items():
        im = Image.fromarray(parts[name]["img"])
        parts[name]["img"] = np.array(im.resize((im.width, round(im.height * k)), Image.LANCZOS))
    for name, where, band in cfg.get("openings", []):
        remove_opening(parts[name], where, band)
    for p in parts.values():   # 잘라낸 뒤 떨어져 남은 작은 조각 지우기
        a = p["img"][..., 3] > 20
        lab, n = ndimage.label(a)
        if n > 1:
            sizes = ndimage.sum(a, lab, range(1, n + 1))
            for i, sz in enumerate(sizes):
                if sz < sizes.max() * 0.03:
                    p["img"][lab == i + 1, 3] = 0
    P = {k: v for k, v in parts.items()}
    def put(name, sheet_pt, local_pt):
        P[name]["pos"] = [sheet_pt[0] - local_pt[0], sheet_pt[1] - local_pt[1]]
    def anchor(name, where, half=None):
        if half is None and where in P[name]:
            return P[name][where]
        lx, ly = band_center(P[name]["img"], where, half=half)
        return (P[name]["pos"][0] + lx, P[name]["pos"][1] + ly)
    for st in cfg["steps"]:
        if st[0] == "put":
            lx, ly = band_center(P[st[1]]["img"], st[3])
            put(st[1], st[2], (lx, ly))
            P[st[1]][st[3]] = tuple(st[2])
        elif st[0] == "chain":
            _k, child, parent, ov, half = st
            px, py = anchor(parent, "bottom", half=half)
            lx, ly = band_center(P[child]["img"], "top")
            put(child, (px, py - ov), (lx, ly))
            P[child]["top"] = (px, py - ov)
        elif st[0] == "rot":
            q = P[st[1]]
            lx, ly = band_center(q["img"], "top")
            bx, by = band_center(q["img"], "bottom")
            piv = (q["pos"][0] + lx, q["pos"][1] + ly + 8)
            bot = (q["pos"][0] + bx, q["pos"][1] + by)
            rotate_part(q, st[2], (lx, ly + 8))
            t = math.radians(st[2])   # 화면 기준 시계 반대 (y 아래)
            dx, dy = bot[0] - piv[0], bot[1] - piv[1]
            q["bottom"] = (piv[0] + dx * math.cos(t) + dy * math.sin(t), piv[1] - dx * math.sin(t) + dy * math.cos(t))
            q.setdefault("top", (piv[0], piv[1] - 8))
    hx, hy = P["head"]["pos"]
    for name, rule in cfg["hair"].items():
        if rule[0] == "tie":
            put(name, (hx + rule[2][0], hy + rule[2][1]), rule[1])
        else:
            P[name]["pos"] = [hx + rule[0], hy + rule[1]]
    # 눈: 머리 그림 흰자로 채우고 홍채 파츠
    head_img, eyes = split_eyes(P["head"]["img"], cfg["eyes"])
    P["head"]["img"] = head_img
    # 전체 범위 → 캔버스 배율 (정수리~발 = FIGURE_PX)
    x0 = min(p["pos"][0] for p in P.values()); y0 = min(p["pos"][1] for p in P.values())
    x1 = max(p["pos"][0] + p["img"].shape[1] for p in P.values()); y1 = max(p["pos"][1] + p["img"].shape[0] for p in P.values())
    K = FIGURE_PX / (y1 - y0)
    W, Hc = CANVAS
    offx = W / 2 - ((x0 + x1) / 2) * K
    offy = (Hc - 6) - y1 * K
    def to_canvas(pt):
        return (pt[0] * K + offx, pt[1] * K + offy)
    out_dir = os.path.join(ROOT, "assets", "sprites", "rig_" + cid)
    os.makedirs(out_dir, exist_ok=True)
    for fn in os.listdir(out_dir):
        os.remove(os.path.join(out_dir, fn))
    # 파츠 축소·배치 + 휴식 자세 합성
    rest = Image.new("RGBA", (W, Hc))
    placed = {}
    for name in cfg["z"]:
        p = P[name]
        im = Image.fromarray(p["img"])
        cx0, cy0 = to_canvas(p["pos"])
        ox, oy = int(round(cx0)), int(round(cy0))
        sw, sh = max(1, round(im.width * K)), max(1, round(im.height * K))
        q = im.resize((sw, sh), Image.LANCZOS)
        bbox = q.split()[3].getbbox()
        q = q.crop(bbox)
        o = (ox + bbox[0], oy + bbox[1])
        placed[name] = (q, o)
        rest.alpha_composite(q, o)
    # 홍채 (머리 파츠 좌표 → 캔버스), 소켓 마스크
    hp = P["head"]["pos"]
    iris_parts = []
    for i, e in enumerate(eyes):
        side = "l" if i == 0 else "r"
        im = Image.fromarray(e["iris"])
        cx0, cy0 = to_canvas((hp[0] + e["origin"][0], hp[1] + e["origin"][1]))
        sw = max(1, round(im.width * K))
        q = im.resize((sw, sw), Image.LANCZOS)
        o = (int(round(cx0)), int(round(cy0)))
        sock = Image.fromarray(e["socket"])
        sc0 = to_canvas(hp)
        sq = sock.resize((max(1, round(sock.width * K)), max(1, round(sock.height * K))), Image.LANCZOS)
        sbox = sq.getbbox()
        sq = sq.crop(sbox)
        so = (int(round(sc0[0])) + sbox[0], int(round(sc0[1])) + sbox[1])
        iris_parts.append((side, q, o, sq, so))
        # 휴식 자세 합성에 홍채 (소켓으로 자름)
        layer = Image.new("RGBA", (W, Hc)); layer.alpha_composite(q, o)
        m = Image.new("L", (W, Hc), 0); m.paste(sq, so)
        la = np.array(layer); la[..., 3] = (la[..., 3].astype(np.float32) * np.array(m) / 255.0).astype(np.uint8)
        # 머리보다 앞, 몸통 앞쪽 파츠가 덮으면 그 아래 — 머리 영역에서만 보이므로 바로 합성
        rest.alpha_composite(Image.fromarray(la))
    # 조명 마스크 (휴식 자세 전신 기준) → 파츠별로 잘라 씀
    mask_r = build_zone_mask(rest, [], "right", rim=6, smooth=45)
    mask_l = build_zone_mask(rest, [], "left", rim=6, smooth=45)
    rig = {"image_size": [W, Hc], "scale": round(0.156 / 0.5, 4), "bones": [], "parts": [], "weapon_bone": "wrist_r", "head_bone": "head",
           "source": cfg["sheet"]}
    def save_part(name, q, o, z, bone, extra=None, zone=None):
        q.save(os.path.join(out_dir, name + ".png"))
        for suf, mk in (("_mask_r", mask_r), ("_mask_l", mask_l)):
            crop = mk.crop((o[0], o[1], o[0] + q.width, o[1] + q.height))
            if zone is not None:
                crop = Image.new("L", q.size, zone)
            crop.save(os.path.join(out_dir, name + suf + ".png"))
        d = {"name": name, "bone": bone, "tex": name + ".png", "origin": list(o), "size": [q.width, q.height], "z": z}
        if extra:
            d.update(extra)
        rig["parts"].append(d)
    for z, name in enumerate(cfg["z"]):
        q, o = placed[name]
        save_part(name, q, o, z, cfg["bones"][name])
    rng = cfg.get("eye_range", (4, 1.5))
    for side, q, o, sq, so in iris_parts:
        sq.save(os.path.join(out_dir, "eye_socket_%s.png" % side))
        save_part("iris_" + side, q, o, cfg["z"].index("head"), "head",
                  {"attach": "head", "clip_mask": "eye_socket_%s.png" % side, "clip_origin": list(so),
                   "eye_range": [round(rng[0] * K, 2), round(rng[1] * K, 2)]}, zone=Z_UNLIT)
    # 뼈: 관절 위치 (캔버스)
    def cpt(name, where, dy=0.0):
        if where in P[name]:
            x, y = to_canvas(P[name][where])
            return [round(x, 1), round(y + dy, 1)]
        q, o = placed[name]
        lx, ly = band_center(np.array(q), where)
        return [round(o[0] + lx, 1), round(o[1] + ly + dy, 1)]
    hipc = to_canvas((936, 465))
    neck = to_canvas(next(st[2] for st in cfg["steps"] if st[0] == "put" and st[1] == "head"))
    chest = [round((hipc[0] + neck[0]) / 2, 1), round(neck[1] + (hipc[1] - neck[1]) * 0.35, 1)]
    spine = [round((hipc[0] + chest[0]) / 2, 1), round((hipc[1] + chest[1]) / 2, 1)]
    bones = [("hip", "", [round(hipc[0], 1), round(hipc[1], 1)]), ("spine", "hip", spine), ("chest", "spine", chest),
             ("head", "chest", [round(neck[0], 1), round(neck[1], 1)])]
    for s in ("l", "r"):
        bones += [("shoulder_" + s, "chest", cpt("arm_upper_" + s, "top", 14 * K)),
                  ("elbow_" + s, "shoulder_" + s, cpt("arm_lower_" + s, "top", 10 * K)),
                  ("wrist_" + s, "elbow_" + s, cpt("hand_" + s, "top", 8 * K))]
    for s in ("l", "r"):
        bones += [("hip_" + s, "hip", cpt("thigh_" + s, "top", 24 * K)),
                  ("knee_" + s, "hip_" + s, cpt("shin_" + s, "top", 12 * K)),
                  ("ankle_" + s, "knee_" + s, cpt("foot_" + s, "top", 30 * K))]
    rig["bones"] = [{"name": n, "parent": p, "pos": pos} for n, p, pos in bones]
    a = rest.split()[3].point(lambda v: 255 if v > 40 else 0)
    bb = a.getbbox()
    rig["ground"] = [round(W / 2), bb[3]]
    rig["figure_px"] = bb[3] - bb[1]
    hq, ho = placed["head"]
    rig["head_rect"] = [ho[0], ho[1], hq.width, int(hq.height * 0.9)]
    rig["eyes"] = [[o[0] + q.width // 2, o[1] + q.height // 2] for _s, q, o, _sq, _so in iris_parts]
    # 실루엣 (3D 그림자), 초상화 (홍채 포함 머리), 디버그
    sil = Image.new("RGBA", (W, Hc), (255, 255, 255, 0))
    sil.putalpha(rest.split()[3].point(lambda v: 255 if v > 100 else 0))
    sil.resize((W // 2, Hc // 2), Image.LANCZOS).save(os.path.join(out_dir, "silhouette.png"))
    rig["silhouette"] = "silhouette.png"
    side = max(hq.width, hq.height)
    port = rest.crop((ho[0] + hq.width // 2 - side // 2, ho[1], ho[0] + hq.width // 2 + side // 2, ho[1] + side))
    port.save(os.path.join(out_dir, "portrait.png"))
    rig["portrait"] = "portrait.png"
    rest.save(os.path.join(out_dir, "_rest.png"))
    o_img = Image.fromarray(orig["img"])
    ok = FIGURE_PX / o_img.height
    o_img = o_img.resize((round(o_img.width * ok), FIGURE_PX), Image.LANCZOS)
    dbg = Image.new("RGBA", (W * 2, Hc), (60, 60, 70, 255))
    dbg.alpha_composite(o_img, ((W - o_img.width) // 2, Hc - 6 - FIGURE_PX))
    dbg.alpha_composite(rest, (W, 0))
    dd = ImageDraw.Draw(dbg)
    pos = {b["name"]: b["pos"] for b in rig["bones"]}
    for b in rig["bones"]:
        if b["parent"]:
            dd.line([(W + pos[b["parent"]][0], pos[b["parent"]][1]), (W + b["pos"][0], b["pos"][1])], fill=(255, 255, 0, 255), width=3)
        dd.ellipse([W + b["pos"][0] - 5, b["pos"][1] - 5, W + b["pos"][0] + 5, b["pos"][1] + 5], fill=(255, 0, 255, 255))
    dbg.save(os.path.join(out_dir, "_debug_parts.png"))
    with open(os.path.join(out_dir, "rig.json"), "w", encoding="utf-8") as f:
        json.dump(rig, f, ensure_ascii=False, indent=1)
    print(cid, "parts", len(rig["parts"]), "bones", len(rig["bones"]), "K", round(K, 3), "figure", rig["figure_px"])


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "kira")
