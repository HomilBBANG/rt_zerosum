"""캐릭터 스프라이트(프레임 애니메이션) 에셋 도구.

assets/characters/<id>/
  character.json      기준 정보: image_size, ground(발 접지점), figure_px(정수리~발 픽셀), head_rect, hip_y, hand, fps
  base.png            기본 한 장 (애니메이션 프레임이 없을 때 쓰는 정지 그림)
  base_mask_l/_r.png  조명 구역 마스크 (셰이더용, 빛이 왼쪽/오른쪽에서 올 때)
  silhouette.png      3D 배경의 그림자용 실루엣
  portrait.png        초상화 (HUD)
  <애니메이션>/0001.png, 0002.png …   ← 사용자가 뽑은 프레임 (idle, walk, sit, sleep, work, attack, hit, heal, death …)
  <애니메이션>/anim.json  (선택) {"fps": 12, "loop": true, "durations": [초, 초, …], "ground": [x, y], "figure_px": 760, "hip_y": 400, "weapon": false}

사용:
  python3 tools/char_sprites.py masks            프레임·시트마다 조명 마스크(<프레임>_mask_l/_r.png, <시트>_mask_l/_r.png)가 없으면 만든다
  python3 tools/char_sprites.py masks dan        한 캐릭터만
  python3 tools/char_sprites.py new <캐릭터 id> <전신 그림.png>   새 캐릭터 폴더 (투명 배경 전신 한 장 → base.png·조명 마스크·초상화·그림자·character.json)
      키 760px 로 맞추고 발 = 그림 맨 아래 가운데, 머리·골반·손 위치는 그림에서 추정 (character.json 에서 고칠 수 있음)
  python3 tools/char_sprites.py lines [캐릭터]    선화 마스크(<그림>_line.png) — 게임이 선은 원화 그대로, 면에만 조명 (new 는 자동)
  python3 tools/char_sprites.py eyes <캐릭터> [x0,y0,x1,y1 …]   눈 마스크(base_eye.png) — 게임이 눈(흰자·눈동자)은 원화 색 그대로 (new 는 자동)
      상자를 안 주면 머리 영역에서 흰자·푸르스름한 눈동자 덩어리 2개를 자동으로 찾음, 상자를 주면 그 안에서만
  python3 tools/char_sprites.py breathe <캐릭터> [칸 수=16]   기본 그림(base.png)으로 숨쉬기 idle 시트를 만든다 (idle_4x4.png)
      그림을 다시 그리지 않고 원화 픽셀만 살짝 늘이고 흔듦: 골반 위 상체가 숨 쉬듯 오르내리고 좌우로 조금, 발은 고정
  python3 tools/char_sprites.py import <캐릭터> <동작> <파일…> [--grid 4x2] [--fps 12] [--hold 0.35]
      움직이는 GIF·WebP(APNG) → 프레임마다, 스프라이트 시트 → --grid 열x행 칸마다, PNG 여러 장 → 그 순서대로
      첫 프레임의 발·키를 base.png 에 맞추는 같은 이동·배율을 모든 프레임에 적용 (프레임 사이 움직임은 그대로)
      → assets/characters/<캐릭터>/<동작>/0001.png … + anim.json(움직이는 파일의 프레임 시간) + 조명 마스크
(지금 base.png·마스크·character.json 은 예전 Skeleton2D 리그를 쉬는 자세로 합쳐 만든 것 — 리그는 제거됨)
"""
import json
import os
import re
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from gen_sprites import build_zone_mask  # noqa: E402

CHAR_DIR = os.path.join(ROOT, "assets", "characters")


def line_mask(im, size=7, lo=18.0, hi=55.0):
    """원화 선화 마스크 (L, 255 = 선): 주변보다 가늘게 어두운 획(블랙 탑햇). 흰 바탕에 올려 바깥 외곽선도 잡고,
    넓게 어두운 면(검은 옷)은 선으로 치지 않는다. 셰이더가 이 픽셀은 조명 없이 원화 색 그대로 그림."""
    import numpy as np
    from scipy import ndimage
    a = np.array(im.convert("RGBA")).astype(np.float32)
    al = a[..., 3:4] / 255.0
    gray = (a[..., :3] * al + 255.0 * (1.0 - al)).mean(-1)
    th = ndimage.grey_closing(gray, size=(size, size)) - gray
    m = np.clip((th - lo) / (hi - lo), 0.0, 1.0)
    m *= (a[..., 3] > 10)
    return Image.fromarray((m * 255).astype(np.uint8), "L")


def cmd_lines(only=None):
    """기본 그림·프레임·시트마다 선화 마스크(<이름>_line.png). 시트는 칸마다 (선이 칸 경계를 넘지 않게)"""
    n = 0
    for cid in sorted(os.listdir(CHAR_DIR)):
        cdir = os.path.join(CHAR_DIR, cid)
        if not os.path.isdir(cdir) or (only and cid != only):
            continue
        for fn in sorted(os.listdir(cdir)):
            path = os.path.join(cdir, fn)
            if not fn.endswith(".png") or "_mask_" in fn or fn.endswith(("_line.png", "_eye.png")) or fn in ("silhouette.png", "portrait.png"):
                continue
            m = SHEET_RE.match(fn)
            im = Image.open(path).convert("RGBA")
            if m:
                cols, rows = int(m.group(2)), int(m.group(3) or 1)
                cw, ch = im.width // cols, im.height // rows
                out = Image.new("L", im.size, 0)
                for r in range(rows):
                    for c in range(cols):
                        box = (c * cw, r * ch, (c + 1) * cw, (r + 1) * ch)
                        out.paste(line_mask(im.crop(box)), box[:2])
            else:
                out = line_mask(im)
            out.save(path[:-4] + "_line.png")
            n += 1
        for anim in sorted(os.listdir(cdir)):
            adir = os.path.join(cdir, anim)
            if not os.path.isdir(adir):
                continue
            for fn in sorted(os.listdir(adir)):
                if fn.endswith(".png") and "_mask_" not in fn and not fn.endswith(("_line.png", "_eye.png")):
                    line_mask(Image.open(os.path.join(adir, fn))).save(os.path.join(adir, fn[:-4] + "_line.png"))
                    n += 1
    print("선화 마스크:", n)


def eye_mask(im, head=None, boxes=None):
    """눈(흰자·홍채·동공) 마스크 L: 흰자 덩어리 → 그 볼록 껍질 안의 홍채(피부와 다른 색)·검은 눈동자 → 구멍(동공) 메움 → 1px 부드럽게.
    boxes: [(x0,y0,x1,y1)…] 그 안에서만. 없으면 head(x,y,w,h) 의 세로 30~85% 띠에서 큰 덩어리 2개."""
    import numpy as np
    from scipy import ndimage
    from PIL import ImageFilter
    a = np.asarray(im.convert("RGBA")).astype(int)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    # 씨앗 = 흰자 (밝고 채도 낮음). 회색 옷·짧게 깎은 머리처럼 '푸르스름하지만 어두운' 면은 제외 — 홍채는 아래에서 흰자 껍질로 넓힘
    cand = (al > 200) & ((r + g + b) / 3 > 185) & (mx - mn < 24)
    keep = np.zeros(cand.shape, bool)
    if boxes:
        for x0, y0, x1, y1 in boxes:
            keep[y0:y1, x0:x1] = True
    elif head:
        hx, hy, hw, hh = head
        keep[int(hy + hh * 0.30):int(hy + hh * 0.85), int(hx):int(hx + hw)] = True
    cand &= keep
    # 흰 피부(니키타 등)는 흰자보다 덜 희고 붉은 기가 있음 → 머리 띠의 대표 피부색과 가까우면 제외
    band = keep & (al > 200) & ((r + g + b) / 3 > 90)
    if band.sum() > 50:
        skin0 = np.median(a[..., :3][band], 0)
        cand &= np.abs(a[..., :3] - skin0).sum(-1) > 30
    cand = ndimage.binary_closing(cand, iterations=2)
    lab, n = ndimage.label(cand)
    if n == 0:
        return Image.new("L", im.size, 0)
    sizes = ndimage.sum(cand, lab, range(1, n + 1))
    order = [i + 1 for i in np.argsort(sizes)[::-1] if sizes[i] >= 4]
    pick = order
    if not boxes and order:   # 가장 큰 흰자 + 높이가 비슷한(±30px) 다음 흰자 하나 — 목걸이 등 다른 흰 점 제외
        cy = ndimage.center_of_mass(cand, lab, order)
        pick = [order[0]] + [o for k, o in enumerate(order[1:], 1) if abs(cy[k][0] - cy[0][0]) <= 30][:1]
    m = np.isin(lab, pick)   # 흰자·밝은 홍채
    dark = (al > 200) & ((r + g + b) / 3 <= 70)
    # 눈마다 흰자의 볼록 껍질 (+여유) 안에서만 넓힘 → 옆 머리카락·눈썹으로 번지지 않게
    from PIL import ImageDraw
    from scipy.spatial import ConvexHull
    lab2, n2 = ndimage.label(m)
    hulls = np.zeros_like(m)
    for k in range(1, n2 + 1):
        ys, xs = np.nonzero(lab2 == k)
        if len(xs) < 8:
            continue
        try:
            hull = ConvexHull(np.stack([xs, ys], 1))
        except Exception:
            continue
        poly = Image.new("L", im.size, 0)
        ImageDraw.Draw(poly).polygon([(int(xs[v]), int(ys[v])) for v in hull.vertices], fill=255)
        inside = ndimage.binary_dilation(np.asarray(poly) > 0, iterations=3)
        hulls |= inside
        # 홍채 색이 노랑·갈색·초록이어도: 껍질 안에서 주변 피부색과 다른 픽셀은 눈
        ring = ndimage.binary_dilation(inside, iterations=5) & ~ndimage.binary_dilation(inside, iterations=1) & (al > 200) & ~dark
        if ring.sum() >= 10:
            skin = np.median(a[..., :3][ring], 0)
            m |= inside & (al > 200) & (np.abs(a[..., :3] - skin).sum(-1) > 70)
    # 검은 눈동자·동공·눈 테두리: 흰자에 붙은 어두운 덩어리 중 껍질(+5px) 안 부분만
    near = ndimage.binary_dilation(m, iterations=2)
    dl, _dn = ndimage.label(dark & ndimage.binary_dilation(hulls, iterations=5))
    m |= np.isin(dl, np.unique(dl[near & (dl > 0)])) & (dl > 0)
    m = ndimage.binary_fill_holes(m)
    out = Image.fromarray((m * 255).astype(np.uint8))
    return out.filter(ImageFilter.GaussianBlur(0.7))


def cmd_eyes(cid, boxes=None):
    cdir = os.path.join(CHAR_DIR, cid)
    info = json.load(open(os.path.join(cdir, "character.json"), encoding="utf-8"))
    base = Image.open(os.path.join(cdir, "base.png")).convert("RGBA")
    m = eye_mask(base, info.get("head_rect"), boxes)
    m.save(os.path.join(cdir, "base_eye.png"))
    print(cid, "눈 마스크 픽셀", int((__import__("numpy").asarray(m) > 127).sum()), "bbox", m.getbbox())


def make_masks(im, k=0.5):
    """원화(RGBA)에서 빛 오른쪽/왼쪽 구역 마스크 (리그 도구와 같은 규칙: 림 두께·경계 부드럽게, 원화 0.5배 기준)"""
    rim = max(2, round(11 * k))
    smooth = round(90 * k)
    return (build_zone_mask(im, [], "right", rim=rim, smooth=smooth),
            build_zone_mask(im, [], "left", rim=rim, smooth=smooth))


SHEET_RE = re.compile(r"^([a-z]+)_(\d+)(?:x(\d+))?\.png$")


def sheet_masks(path, cols, rows):
    """스프라이트 시트 → 칸마다 조명 마스크를 만들어 같은 배치의 <시트>_mask_r/_l.png"""
    im = Image.open(path).convert("RGBA")
    cw, ch = im.width // cols, im.height // rows
    k = ch / 1536.0 * 2.2   # 원화 키에 비례한 림 두께·경계 부드럽기 (칸 높이 기준)
    out_r = Image.new("L", im.size, 85)
    out_l = Image.new("L", im.size, 85)
    for r in range(rows):
        for c in range(cols):
            box = (c * cw, r * ch, (c + 1) * cw, (r + 1) * ch)
            cell = im.crop(box)
            if cell.split()[3].getbbox() is None:
                continue
            mr, ml = make_masks(cell, k)
            out_r.paste(mr, box[:2])
            out_l.paste(ml, box[:2])
    base = path[:-4]
    out_r.save(base + "_mask_r.png")
    out_l.save(base + "_mask_l.png")


def cmd_masks(only=None):
    n = 0
    for cid in sorted(os.listdir(CHAR_DIR)):
        cdir = os.path.join(CHAR_DIR, cid)
        if not os.path.isdir(cdir) or (only and cid != only):
            continue
        for fn in sorted(os.listdir(cdir)):
            m = SHEET_RE.match(fn)
            if not m or os.path.exists(os.path.join(cdir, fn[:-4] + "_mask_r.png")):
                continue
            cols, rows = int(m.group(2)), int(m.group(3) or 1)
            sheet_masks(os.path.join(cdir, fn), cols, rows)
            n += 1
            print("mask sheet", cid, fn)
        for anim in sorted(os.listdir(cdir)):
            adir = os.path.join(cdir, anim)
            if not os.path.isdir(adir):
                continue
            for fn in sorted(os.listdir(adir)):
                if not fn.endswith(".png") or "_mask_" in fn or fn.endswith(("_line.png", "_eye.png")):
                    continue
                stem = fn[:-4]
                r_path = os.path.join(adir, stem + "_mask_r.png")
                l_path = os.path.join(adir, stem + "_mask_l.png")
                if os.path.exists(r_path) and os.path.exists(l_path):
                    continue
                im = Image.open(os.path.join(adir, fn)).convert("RGBA")
                mr, ml = make_masks(im)
                mr.save(r_path)
                ml.save(l_path)
                n += 1
                print("mask", cid, anim, fn)
    print("만든 마스크:", n)


def _feet(im):
    """알파 기준 (bbox, 발 가운데 x) — 아래 6% 줄의 좌우 끝 가운데"""
    a = im.split()[3].point(lambda v: 255 if v > 40 else 0)
    bb = a.getbbox()
    if bb is None:
        return None, 0
    h = bb[3] - bb[1]
    band = a.crop((0, bb[3] - max(1, int(h * 0.06)), im.width, bb[3]))
    cols = [x for x in range(band.width) if band.crop((x, 0, x + 1, band.height)).getbbox()]
    return bb, (cols[0] + cols[-1]) / 2


def _read_frames(paths, grid):
    """[(RGBA 이미지, 표시 ms 또는 None)]"""
    out = []
    for p in paths:
        im = Image.open(p)
        n = getattr(im, "n_frames", 1)
        if n > 1:
            for i in range(n):
                im.seek(i)
                out.append((im.convert("RGBA").copy(), im.info.get("duration")))
        elif grid:
            cols, rows = grid
            sheet = im.convert("RGBA")
            cw, ch = sheet.width // cols, sheet.height // rows
            for r in range(rows):
                for c in range(cols):
                    cell = sheet.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
                    if cell.split()[3].getbbox():   # 빈 칸은 건너뜀
                        out.append((cell, None))
        else:
            out.append((im.convert("RGBA"), None))
    return out


def cmd_import(cid, anim, paths, grid=None, fps=None, hold=None):
    cdir = os.path.join(CHAR_DIR, cid)
    info = json.load(open(os.path.join(cdir, "character.json"), encoding="utf-8"))
    w, h = info["image_size"]
    base = Image.open(os.path.join(cdir, "base.png")).convert("RGBA")
    _bb, gx = _feet(base)
    gy = info["ground"][1]
    fig = info.get("figure_px", h)
    frames = _read_frames(paths, grid)
    if not frames:
        sys.exit("프레임이 없습니다")
    bb, cx = _feet(frames[0][0])
    s = fig / (bb[3] - bb[1])
    ox, oy = gx - cx * s, gy - bb[3] * s
    adir = os.path.join(cdir, anim)
    os.makedirs(adir, exist_ok=True)
    for fn in os.listdir(adir):   # 예전 프레임 지우기
        if fn.endswith(".png"):
            os.remove(os.path.join(adir, fn))
    pad = max(w, h)
    durs = []
    for i, (im, ms) in enumerate(frames):
        im2 = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
        big = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
        big.alpha_composite(im2, (round(ox) + pad, round(oy) + pad))
        big.crop((pad, pad, pad + w, pad + h)).save(os.path.join(adir, "%04d.png" % (i + 1)))
        durs.append(round((ms or 0) / 1000.0, 3))
    meta = {}
    if fps:
        meta["fps"] = fps
    elif all(d > 0 for d in durs) and len(set(durs)) > 1:
        meta["durations"] = durs
    elif durs and durs[0] > 0:
        meta["fps"] = round(1.0 / durs[0], 2)
    if hold and len(frames) == 1:
        meta["durations"] = [hold]
    if meta:
        json.dump(meta, open(os.path.join(adir, "anim.json"), "w", encoding="utf-8"), ensure_ascii=False)
    elif os.path.exists(os.path.join(adir, "anim.json")):
        os.remove(os.path.join(adir, "anim.json"))
    print(cid, anim, "프레임", len(frames), "배율", round(s, 3), meta)
    cmd_masks(cid)


def cmd_breathe(cid, frames=16):
    import math
    import numpy as np
    from scipy.ndimage import map_coordinates
    cdir = os.path.join(CHAR_DIR, cid)
    info = json.load(open(os.path.join(cdir, "character.json"), encoding="utf-8"))
    im = np.array(Image.open(os.path.join(cdir, "base.png")).convert("RGBA")).astype(np.float32)
    h, w = im.shape[:2]
    fig = float(info.get("figure_px", h))
    ground_y = float(info["ground"][1])
    hip = float(info.get("hip_y", ground_y - fig * 0.55))
    hr = info.get("head_rect") or [0, 0, 0, fig * 0.18]
    shoulder = hr[1] + hr[3] * 1.05            # 목·어깨 쯤
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # 무게: 골반 아래 0 → 어깨 위 1 (부드럽게)
    t = np.clip((hip - yy) / max(1.0, hip - shoulder), 0.0, 1.0)
    wgt = t * t * (3 - 2 * t)
    amp_y = fig * 0.0055                        # 숨 들이쉴 때 상체가 오르는 정도 (키 760px 이면 약 4px)
    amp_x = fig * 0.0028                        # 좌우 흔들림 (약 2px)
    cols = 4
    rows = int(math.ceil(frames / cols))
    sheet = Image.new("RGBA", (w * cols, h * rows), (0, 0, 0, 0))
    masks = {}
    for suf in ("_mask_r", "_mask_l", "_line", "_eye"):   # 조명 마스크·선화·눈 마스크도 같은 움직임으로
        mp = os.path.join(cdir, "base" + suf + ".png")
        if os.path.exists(mp):
            masks[suf] = (np.array(Image.open(mp).convert("L")).astype(np.float32), Image.new("L", (w * cols, h * rows), 85 if "_mask_" in suf else 0))
    for i in range(frames):
        ph = 2 * math.pi * i / frames
        dy = -amp_y * (0.5 - 0.5 * math.cos(ph))          # 0 → 위로 → 0
        dx = amp_x * math.sin(ph)
        sy = yy - dy * wgt                                   # 출력 픽셀이 읽어 올 원본 위치
        sx = xx - dx * wgt * (1.0 - 0.3 * t)
        out = np.zeros_like(im)
        for c in range(4):
            out[..., c] = map_coordinates(im[..., c], [sy, sx], order=1, mode="constant", cval=0.0)
        sheet.paste(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)), ((i % cols) * w, (i // cols) * h))
        for suf, (m, ms) in masks.items():   # 기본 그림 조명 마스크도 같은 움직임으로 (눈동자 구역 등 그대로)
            mw = map_coordinates(m, [sy, sx], order=0 if "_mask_" in suf else 1, mode="nearest")
            ms.paste(Image.fromarray(np.clip(mw, 0, 255).astype(np.uint8)), ((i % cols) * w, (i // cols) * h))
    name = "idle_%dx%d.png" % (cols, rows)
    sheet.save(os.path.join(cdir, name), optimize=True)
    json.dump({"fps": 8, "ground": info["ground"], "figure_px": fig, "hip_y": hip},
              open(os.path.join(cdir, "idle.json"), "w", encoding="utf-8"))
    for suf, (_m, ms) in masks.items():
        ms.save(os.path.join(cdir, name[:-4] + suf + ".png"))
    print(cid, name, frames, "프레임 (숨쉬기)")


def remove_white_bg(im):
    """흰 배경(불투명) 제거: 그림 가장자리에서 이어진 거의 흰 픽셀만 투명 (외곽선 안쪽의 흰 옷은 그대로) + 경계 부드럽게"""
    import numpy as np
    from scipy import ndimage
    a = np.array(im.convert("RGBA")).astype(np.float32)
    rgb = a[..., :3]
    near = (rgb.min(-1) >= 248) & ((rgb.max(-1) - rgb.min(-1)) <= 6)
    lab, _n = ndimage.label(near)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(edge))
    ring = ndimage.binary_dilation(bg, iterations=2) & ~bg
    alpha = np.where(bg, 0.0, 255.0)
    lum = rgb.mean(-1)
    ra = np.clip((255.0 - lum) / 255.0 * 1.6, 0.0, 1.0)            # 흰 바탕과 섞인 외곽선 → 반투명
    alpha = np.where(ring, np.maximum(ra * 255.0, np.where(lum < 200, 255.0, 0.0)), alpha)
    k = np.clip(alpha / 255.0, 1e-3, 1.0)[..., None]
    un = np.clip((rgb - (1.0 - k) * 255.0) / k, 0, 255)            # 흰색 섞임 빼기
    rgb = np.where(ring[..., None], un, rgb)
    solid = alpha > 20
    lab2, n2 = ndimage.label(solid)
    if n2 > 1:   # 떨어져 남은 작은 점 지우기
        sizes = ndimage.sum(solid, lab2, range(1, n2 + 1))
        small = np.isin(lab2, [i + 1 for i, v in enumerate(sizes) if v < max(60, sizes.max() * 0.0005)])
        alpha = np.where(small, 0.0, alpha)
    out = np.dstack([rgb, alpha]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def cmd_new(cid, src, fig_px=760):
    import numpy as np
    im = Image.open(src).convert("RGBA")
    if np.array(im)[..., 3].min() > 250:   # 투명 배경이 아니면 흰 배경 제거
        im = remove_white_bg(im)
        print("흰 배경 제거")
    a = np.array(im)[..., 3]
    ys, xs = np.where(a > 40)
    if len(ys) == 0:
        sys.exit("그림이 비어 있습니다 (투명 배경 전신 그림이어야 함)")
    im = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    k = fig_px / im.height
    im = im.resize((max(1, round(im.width * k)), fig_px), Image.LANCZOS)
    w = max(512, im.width + 24)
    h = fig_px + 8
    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ox = (w - im.width) // 2
    base.alpha_composite(im, (ox, 2))
    A = np.array(base)[..., 3] > 40
    ys, xs = np.where(A)
    top, bot = int(ys.min()), int(ys.max())
    fig = bot - top
    band = A[bot - max(3, int(fig * 0.04)):bot + 1]
    fx = np.where(band.any(0))[0]
    gx = int((fx.min() + fx.max()) / 2)
    hrows = A[top:top + int(fig * 0.18)]
    hx = np.where(hrows.any(0))[0]
    head = [int(hx.min()), top, int(hx.max() - hx.min()), int(fig * 0.2)]
    # 손: 화면 오른쪽 몸 끝 (골반~허벅지 높이에서 가장 오른쪽 불투명 점)
    y0, y1 = top + int(fig * 0.42), top + int(fig * 0.62)
    best = (0, y0)
    for y in range(y0, y1):
        r = np.where(A[y])[0]
        if len(r) and r.max() > best[0]:
            best = (int(r.max()), y)
    info = {"image_size": [w, h], "ground": [gx, bot], "figure_px": fig, "head_rect": head,
            "hip_y": top + int(fig * 0.47), "hand": [best[0] - 12, best[1] + 8, 70], "eyes": [], "fps": 12,
            "silhouette": "silhouette.png"}
    cdir = os.path.join(CHAR_DIR, cid)
    os.makedirs(cdir, exist_ok=True)
    base.save(os.path.join(cdir, "base.png"))
    mr, ml = make_masks(base)
    mr.save(os.path.join(cdir, "base_mask_r.png"))
    ml.save(os.path.join(cdir, "base_mask_l.png"))
    sil = Image.new("RGBA", base.size, (255, 255, 255, 0))
    sil.putalpha(base.split()[3].point(lambda v: 255 if v > 100 else 0))
    sil.resize((w // 2, h // 2), Image.LANCZOS).save(os.path.join(cdir, "silhouette.png"))
    side = int(max(head[2], head[3]) * 1.15)
    cx = head[0] + head[2] // 2
    base.crop((cx - side // 2, max(0, top - 4), cx + side // 2, max(0, top - 4) + side)).save(os.path.join(cdir, "portrait.png"))
    old = os.path.join(cdir, "character.json")
    if os.path.exists(old):   # 다시 만들 때 칠 방식 설정은 유지
        prev = json.load(open(old, encoding="utf-8"))
        for k in ("style", "neon_gradient"):
            if k in prev:
                info[k] = prev[k]
    json.dump(info, open(old, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    line_mask(base).save(os.path.join(cdir, "base_line.png"))
    eye_mask(base, head).save(os.path.join(cdir, "base_eye.png"))
    print(cid, "base", (w, h), "ground", info["ground"], "head", head, "hand", info["hand"])


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["masks"]:
        cmd_masks(args[1] if len(args) > 1 else None)
    elif args[:1] == ["lines"]:
        cmd_lines(args[1] if len(args) > 1 else None)
    elif args[:1] == ["eyes"] and len(args) >= 2:
        cmd_eyes(args[1], [tuple(int(v) for v in b.split(",")) for b in args[2:]] or None)
    elif args[:1] == ["new"] and len(args) >= 3:
        cmd_new(args[1], args[2])
    elif args[:1] == ["breathe"] and len(args) >= 2:
        cmd_breathe(args[1], int(args[2]) if len(args) > 2 else 16)
    elif args[:1] == ["import"] and len(args) >= 4:
        opts = {}
        rest = []
        it = iter(args[3:])
        for a in it:
            if a in ("--grid", "--fps", "--hold"):
                opts[a[2:]] = next(it)
            else:
                rest.append(a)
        grid = tuple(int(v) for v in opts["grid"].lower().split("x")) if "grid" in opts else None
        cmd_import(args[1], args[2], rest, grid, float(opts["fps"]) if "fps" in opts else None,
                   float(opts["hold"]) if "hold" in opts else None)
    else:
        print(__doc__)
        sys.exit(1)
