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
  python3 tools/char_sprites.py hat <캐릭터> <모자 아래 y>   모자 쓴 캐릭터: 키를 '모자 절반 높이 ~ 발'로 (0 이면 해제). 그다음 breathe 다시
  python3 tools/char_sprites.py breathe <캐릭터> [칸 수=16]   기본 그림(base.png)으로 숨쉬기 idle 시트를 만든다 (idle_4x4.png)
      그림을 다시 그리지 않고 원화 픽셀만 살짝 늘이고 흔듦: 골반 위 상체가 숨 쉬듯 오르내리고 좌우로 조금, 발은 고정
  python3 tools/char_sprites.py import <캐릭터> <동작> <파일…> [--grid 4x2] [--fps 12] [--hold 0.35]
      움직이는 GIF·WebP(APNG) → 프레임마다, 스프라이트 시트 → --grid 열x행 칸마다, PNG 여러 장 → 그 순서대로
      첫 프레임의 발·키를 base.png 에 맞추는 같은 이동·배율을 모든 프레임에 적용 (프레임 사이 움직임은 그대로)
      → assets/characters/<캐릭터>/<동작>/0001.png … + anim.json(움직이는 파일의 프레임 시간) + 조명 마스크
  python3 tools/char_sprites.py rig <캐릭터> [칸 수=32] [--blink]   리깅 idle: 원화 한 장을 부위별로 휨 → <캐릭터>/idle/ (숨쉬기 시트 대신)
      다리·골반 고정 · 몸통 숨쉬기 · 머리 = 목(head_rect 아래) 기준 갸웃·끄덕 · 팔 = 어깨 기준 흔들림(팔·몸통 사이 빈틈으로 팔 영역)
      --blink = 눈 깜빡임 1번 (눈 자리를 피부색으로 덮어 그림 — 그림체에 따라 어색할 수 있어 기본은 끔)
  python3 tools/char_sprites.py head <캐릭터> <동작> [--cut y] [--deg 14] [--scale 0.85-1.15] [--keep-deg 3] [--no-smooth]   AI 시트 얼굴이 뭉개졌을 때: 프레임마다 머리를 원화(base.png) 머리로 바꿔 붙임
      원화에서 턱 아래(cut = 원화 y, 턱 바로 아래로)까지 잘라 원화 머리 대표 색(머리카락·피부·모자) 영역이 가장 잘 겹치는 크기·기울기·위치에 붙이고,
      삐져나온 원래 머리카락은 지움 (sheet 다음에 실행). 고개가 엉뚱하게 기울면 --deg 로 기울기 찾는 폭을 줄임
  python3 tools/char_sprites.py report <시트.png> [--grid 6x6] [--align ground|cell] [--loop 8-36]
      AI 로 만든 시트 분석: 튀는 프레임 후보(앞뒤 사이로 바로 가는 것보다 크게 돌아가는 프레임) + 이음새가 매끄러운 반복 구간 후보
  python3 tools/char_sprites.py sheet <캐릭터> <동작> <시트.png> [--grid 6x6] [--frames 1-20,22] [--fps 12] [--align ground|cell] [--ref 1] [--loop 0|1] [--weapon 0|1]
        [--ref-height 324] [--anchor feet|torso]   (선 프레임이 없는 시트: 다른 시트의 선 키 · 몸통 기준 가로 위치)
      AI 시트(영상에서 뽑은 칸 배열) → <동작>/0001.png … 칸 경계는 그림이 가장 적은 줄로 자름, 쓸 프레임만 골라 순서대로
      크기: 기준 프레임(--ref, 똑바로 선 칸)의 키 = figure_px. ground = 프레임마다 발을 접지선에(카메라 흔들림 제거), cell = 칸 높이 그대로(뛰기처럼 뜨는 동작)
      누운 자세처럼 캔버스를 넘으면 그 동작만 캔버스를 넓힘 (anim.json 의 ground). 조명·선화·눈 마스크도 프레임마다
  python3 tools/char_sprites.py steps <캐릭터> [walk run]   걷기·뛰기에서 발이 땅에 닿는 프레임 2개 → anim.json "steps" (발자국 소리 맞추기)
  python3 tools/char_sprites.py export <캐릭터> [idle walk run] [--cols 6] [--out exports/sheets]   프레임 → 스프라이트 시트 한 장씩 (밖으로 내보내기용)
      <out>/<캐릭터>/<동작>_sheet.png (왼쪽 위부터 가로로, 투명 배경) + <동작>_sheet.json (칸 크기·열·행·장 수·fps·발 위치·발자국 프레임)
      모든 동작이 같은 칸 크기 · 같은 발 위치 (동작을 바꿔도 캐릭터가 안 튐), 원본 해상도 그대로. 미리보기 = preview.jpg
  python3 tools/char_sprites.py rows <캐릭터> [idle walk walk:l run run:l] [--name rows] [--scale 1,0.5]   동작마다 한 줄로 긴 시트 한 장
      줄마다 동작 하나(왼쪽부터 프레임 순서), ':l' = 좌우 뒤집어 왼쪽 보기. 칸 = 발이 가운데 오는 공통 크기, 짧은 줄 남는 칸은 투명
      → <out>/<캐릭터>/<name>.png (+ 배율마다 <name>_x0.5.png) + <name>.json (줄마다 동작·방향·장 수·fps·발자국 프레임)
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


def hat_figure_px(info):
    """모자 쓴 캐릭터의 키(px): 모자 위~모자 아래(이마에 닿는 곳)의 절반 높이부터 발까지. info["hat"] = [모자 위 y, 모자 아래 y]"""
    top, bottom = info["hat"]
    return int(info["ground"][1] - (top + (bottom - top) / 2.0))


def cmd_hat(cid, bottom):
    """모자 아래 y(기본 그림 기준)를 정하면 키 = 모자 절반부터 발까지로 (character.json figure_px). 숨쉬기 idle 도 다시 만들 것"""
    cdir = os.path.join(CHAR_DIR, cid)
    path = os.path.join(cdir, "character.json")
    info = json.load(open(path, encoding="utf-8"))
    base = Image.open(os.path.join(cdir, "base.png")).convert("RGBA")
    top = base.split()[3].point(lambda v: 255 if v > 128 else 0).getbbox()[1]
    if bottom <= 0:
        info.pop("hat", None)
        info["figure_px"] = int(info["ground"][1] - top)
    else:
        info["hat"] = [top, int(bottom)]
        info["figure_px"] = hat_figure_px(info)
    json.dump(info, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(cid, "모자", info.get("hat"), "figure_px", info["figure_px"])


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
        for k in ("style", "neon_gradient", "hat"):
            if k in prev:
                info[k] = prev[k]
        if "hat" in info:   # 모자 쓴 캐릭터: 키 = 모자 절반 높이 ~ 발
            info["figure_px"] = hat_figure_px(info)
    json.dump(info, open(old, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    line_mask(base).save(os.path.join(cdir, "base_line.png"))
    eye_mask(base, head).save(os.path.join(cdir, "base_eye.png"))
    print(cid, "base", (w, h), "ground", info["ground"], "head", head, "hand", info["hand"])



# ---------------------------------------------------------------- AI 스프라이트 시트 (영상에서 뽑은 6x6 등) → 애니메이션 폴더
def _sheet_cells(path, cols, rows):
    """시트를 칸으로 자르기: 칸 경계 근처에서 그림이 가장 적은 줄로 자름 (옆 칸 그림이 살짝 겹쳐도 OK), 칸마다 작은 조각 버림.
    반환 [(그림(잘라낸 bbox), x, y)…] — x, y = 그 칸의 원래 칸 왼쪽 위 기준 bbox 위치 (영상의 카메라 위치 그대로)"""
    import numpy as np
    from scipy import ndimage
    arr = np.array(Image.open(path).convert("RGBA"))
    a = arr[..., 3] > 8
    H, W = a.shape
    cw, ch = W / cols, H / rows

    r0 = max(30, round(min(cw, ch) * 0.12))   # 경계 찾는 폭 (4배 확대한 시트도 같은 비율)

    def cut(proj, nominal, r=r0):
        lo, hi = max(0, nominal - r), min(len(proj), nominal + r)
        return lo + int(np.argmin(proj[lo:hi]))
    rp = a.sum(1)
    ys = [0] + [cut(rp, round(ch * i)) for i in range(1, rows)] + [H]
    out = []
    for r in range(rows):
        cp = a[ys[r]:ys[r + 1]].sum(0)
        xs = [0] + [cut(cp, round(cw * i)) for i in range(1, cols)] + [W]
        for c in range(cols):
            sub = arr[ys[r]:ys[r + 1], xs[c]:xs[c + 1]].copy()
            al = sub[..., 3] > 8
            lab, n = ndimage.label(al)
            if n == 0:
                out.append(None)
                continue
            sz = ndimage.sum(al, lab, range(1, n + 1))
            keep = np.isin(lab, [i + 1 for i in range(n) if sz[i] >= sz.max() * 0.02])
            sub[..., 3] = np.where(keep, sub[..., 3], 0)
            yy, xx = np.nonzero(sub[..., 3] > 8)
            bb = (int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1)
            out.append((Image.fromarray(sub).crop(bb), xs[c] + bb[0] - round(c * cw), ys[r] + bb[1] - round(r * ch)))
    return out


def _pose_vecs(cells, ground=True):
    """프레임 비교용 작은 그림 (몸통 가운데·발 기준 정렬)"""
    import numpy as np
    vecs = []
    for cell in cells:
        if cell is None:
            vecs.append(None)
            continue
        im, x, y = cell
        a = np.array(im)[..., 3] > 40
        band = a[int(a.shape[0] * 0.18):int(a.shape[0] * 0.42)].sum(0)
        tcx = float((np.arange(len(band)) * band).sum() / max(1, band.sum()))
        can = Image.new("RGBA", (400, 400), (0, 0, 0, 0))
        can.alpha_composite(im, (int(200 - tcx), int((380 - im.height) if ground else y + 20)))
        v = np.array(can.resize((80, 80), Image.BILINEAR)).astype(np.float32) / 255
        vecs.append(np.concatenate([v[..., :3] * v[..., 3:4], v[..., 3:4]], -1))
    return vecs


def cmd_sheet_report(path, grid=(6, 6), ground=True, lo=8, hi=36):
    """튀는 프레임(앞뒤 프레임 사이로 바로 가는 것보다 크게 돌아가는 프레임)과 이음새가 매끄러운 반복 구간 후보"""
    import numpy as np
    cells = _sheet_cells(path, *grid)
    while cells and cells[-1] is None:   # 끝의 빈 칸은 빼고 (시트 칸이 다 차지 않았을 때)
        cells.pop()
    v = _pose_vecs(cells, ground)
    n = len(v)
    D = np.array([[np.abs(v[i] - v[j]).mean() if v[i] is not None and v[j] is not None else 9 for j in range(n)] for i in range(n)])
    steps = [D[k][k + 1] for k in range(n - 1)]
    print("프레임 %d개, 이웃 프레임 차이 중앙값 %.1f" % (n, np.median(steps) * 1000))
    det = sorted(((D[k - 1][k] + D[k][k + 1] - D[k - 1][k + 1]) * 1000, k + 1) for k in range(1, n - 1))[::-1]
    print("튀는 프레임 후보 (점수 높을수록):", ", ".join("%d(%.0f)" % (k, d) for d, k in det[:8]))
    # 반복 a..b 가 매끄러우려면 '마지막 다음 프레임(b+1)' 이 첫 프레임(a)과 거의 같아야 함 (마지막 = 첫 프레임이면 이음새에서 한 박자 멈칫)
    cands = []
    for i in range(n):
        for L in range(lo, hi + 1):
            j = i + L          # 0부터: 마지막 = j-1, 그 다음 = j
            if j >= n:
                break
            cands.append((D[j][i] + 0.3 * max(D[k][k + 1] for k in range(i, j - 1)), i + 1, j, D[j][i], D[j - 1][i]))
    for sc, a, b, seam, back in sorted(cands)[:6]:
        print("  반복 %d..%d (%d장) 이음새 %.0f (%d 다음 = %d 와 거의 같음, %d→%d 차이 %.0f)" % (a, b, b - a + 1, seam * 1000, b, a, b, a, back * 1000))


def _parse_frames(spec, n):
    """'1-20,22,30-26' → [1..20, 22, 30, 29, …, 26]"""
    out = []
    for part in spec.split(","):
        if "-" in part:
            a, b = (int(x) for x in part.split("-"))
            out += list(range(a, b + 1)) if a <= b else list(range(a, b - 1, -1))
        elif part.strip():
            out.append(int(part))
    return [k for k in out if 1 <= k <= n]


def cmd_sheet(cid, anim, path, grid=(6, 6), frames=None, fps=12.0, align="ground", ref=1, loop=None, weapon=None, durations=None,
              ref_height=None, anchor="feet"):
    """AI 시트 → assets/characters/<캐릭터>/<동작>/0001.png … + anim.json + 조명·선화·눈 마스크.
    크기: 기준 프레임(ref, 똑바로 선 프레임)의 키 = character.json figure_px. 시트 전체에 같은 배율·이동 (프레임 사이 움직임 그대로).
          선 프레임이 없는 시트(뛰기 등)는 ref_height = 같은 배율의 다른 시트에서 똑바로 선 키(원본 px).
    가로: anchor feet = 기준 프레임 두 발 가운데 / torso = 기준 프레임 몸통 가운데 → 접지점 x
    align: ground = 프레임마다 맨 아래를 발 접지선에 (발이 땅에 붙어 있는 동작 — 영상 카메라 흔들림 제거)
           cell = 칸 안 높이 그대로 (뛰기처럼 공중에 뜨는 동작)
    그림이 기본 캔버스(image_size)를 넘으면(누운 자세 등) 그 동작만 캔버스를 넓히고 anim.json 에 ground 를 적음"""
    import numpy as np
    cdir = os.path.join(CHAR_DIR, cid)
    info = json.load(open(os.path.join(cdir, "character.json"), encoding="utf-8"))
    W, H = info["image_size"]
    gx, gy = info["ground"]
    fig = float(info.get("figure_px", H))
    cells = _sheet_cells(path, *grid)
    pick = _parse_frames(frames, len(cells)) if frames else list(range(1, len(cells) + 1))
    rim, rx, ry = cells[ref - 1]
    s = fig / float(ref_height or rim.height)
    ra = np.array(rim)[..., 3] > 40
    if anchor == "torso":
        band = ra[int(ra.shape[0] * 0.18):int(ra.shape[0] * 0.42)].sum(0)
        ref_fx = rx + float((np.arange(len(band)) * band).sum() / max(1, band.sum()))
    else:
        feet = np.nonzero(ra[int(ra.shape[0] * 0.94):].any(0))[0]
        ref_fx = rx + (feet.min() + feet.max()) / 2.0       # 기준 프레임 두 발 가운데 = 접지점 x
    ref_bottom = max(c[2] + c[0].height for c in cells if c)   # cell: 시트 전체에서 가장 낮은 발 = 땅
    placed = []
    for k in pick:
        im, x, y = cells[k - 1]
        im2 = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
        px = gx + (x - ref_fx) * s
        py = gy - im2.height if align == "ground" else gy - (ref_bottom - y) * s
        placed.append((im2, px, py))
    x0 = min(0.0, min(p[1] for p in placed) - 4)
    x1 = max(float(W), max(p[1] + p[0].width for p in placed) + 4)
    y0 = min(0.0, min(p[2] for p in placed) - 4)
    sx, sy = -x0, -y0
    CW, CH = int(np.ceil(x1 - x0)), int(np.ceil(H - y0))
    adir = os.path.join(cdir, anim)
    os.makedirs(adir, exist_ok=True)
    for fn in os.listdir(adir):
        if fn.endswith(".png") or fn.endswith(".png.import"):
            os.remove(os.path.join(adir, fn))
    hr = info.get("head_rect")
    for i, (im2, px, py) in enumerate(placed):
        can = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
        can.alpha_composite(im2, (round(px + sx), round(py + sy)))
        stem = os.path.join(adir, "%04d" % (i + 1))
        can.save(stem + ".png")
        mr, ml = make_masks(can)
        mr.save(stem + "_mask_r.png")
        ml.save(stem + "_mask_l.png")
        line_mask(can).save(stem + "_line.png")
        bb = can.getbbox()
        head = (bb[0], bb[1], bb[2] - bb[0], (hr[3] if hr else fig * 0.2))   # 머리 = 그림 맨 위 띠 (누운 자세면 못 찾음 → 눈 마스크 비어 있음)
        eye_mask(can, head=head).save(stem + "_eye.png")
    meta = {"fps": fps, "ground": [round(gx + sx), round(gy + sy)], "figure_px": fig, "hip_y": round(float(info.get("hip_y", gy - fig * 0.55)) + sy),
            "source": "%s %s 프레임 %s" % (os.path.basename(path), "x".join(map(str, grid)), frames or "전부")}
    if loop is not None:
        meta["loop"] = loop
    if weapon is not None:
        meta["weapon"] = weapon
    if durations:
        meta["durations"] = durations
    json.dump(meta, open(os.path.join(adir, "anim.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print(cid, anim, "프레임", len(placed), "배율 %.3f" % s, "캔버스", (CW, CH), meta)


# ---------------------------------------------------------------- 리깅 idle (원화 한 장 → 숨쉬기 + 머리·팔 + 눈 깜빡임)
def _rig_bones(cid, info, a):
    """뼈 위치: 목(머리 회전 중심), 어깨 높이, 골반, 왼·오른팔 경계(x, 행마다)와 어깨 회전 중심. a = 알파 마스크"""
    import numpy as np
    H, W = a.shape
    fig = float(info.get("figure_px", H))
    gy = float(info["ground"][1])
    hr = info.get("head_rect") or [W * 0.3, gy - fig, W * 0.4, fig * 0.2]
    neck = (hr[0] + hr[2] / 2.0, hr[1] + hr[3])
    shoulder_y = neck[1] + fig * 0.04
    hip = float(info.get("hip_y", gy - fig * 0.53))
    hand = info.get("hand") or [W * 0.7, hip + fig * 0.05]
    y_lo, y_hi = int(shoulder_y + fig * 0.06), int(min(H - 1, hand[1] + fig * 0.025))
    left = np.full(H, np.nan)
    right = np.full(H, np.nan)
    for y in range(y_lo, y_hi):   # 팔과 몸통 사이 빈틈 (행마다 첫·마지막 빈틈)
        row = a[y]
        xs = np.nonzero(np.diff(np.concatenate([[0], row.astype(int), [0]])))[0]
        segs = list(zip(xs[::2], xs[1::2]))
        if len(segs) >= 2 and segs[0][1] - segs[0][0] < fig * 0.12:
            left[y] = (segs[0][1] + segs[1][0]) / 2.0
        if len(segs) >= 2 and segs[-1][1] - segs[-1][0] < fig * 0.12:
            right[y] = (segs[-2][1] + segs[-1][0]) / 2.0

    def fill(arr, default):
        ok = ~np.isnan(arr)
        if ok.sum() < 3:
            return None if default is None else np.full(H, default)
        ys = np.arange(H)
        return np.interp(ys, ys[ok], arr[ok])
    band = slice(y_lo, y_hi)
    nl, nr = int((~np.isnan(left[band])).sum()), int((~np.isnan(right[band])).sum())
    rows_n = max(1, y_hi - y_lo)
    edge_l = np.array([np.nonzero(a[y])[0].min() if a[y].any() else np.nan for y in range(H)], float)
    edge_r = np.array([np.nonzero(a[y])[0].max() if a[y].any() else np.nan for y in range(H)], float)
    from scipy.ndimage import median_filter, uniform_filter1d

    def smooth(v):
        return uniform_filter1d(median_filter(v, size=15, mode="nearest"), 21, mode="nearest")
    lx = fill(left, None) if nl >= rows_n * 0.3 else None
    rx = fill(right, None) if nr >= rows_n * 0.3 else None
    lx = smooth(lx) if lx is not None else None
    rx = smooth(rx) if rx is not None else None
    # 한쪽 팔만 몸통과 떨어져 있으면: 반대쪽 팔 너비만큼 몸 가장자리에서 안쪽 (팔 너비가 비슷하다고 봄)
    if rx is None and lx is not None:
        arm_w = float(np.nanmedian((left - edge_l)[band]))
        rx = smooth(np.nan_to_num(edge_r, nan=W / 2) - arm_w)
    if lx is None and rx is not None:
        arm_w = float(np.nanmedian((edge_r - right)[band]))
        lx = smooth(np.nan_to_num(edge_l, nan=0) + arm_w)
    torso_cx = neck[0]
    if lx is None:   # 빈틈이 없으면 손 위치로 대강 (손이 몸통 바깥쪽)
        lx = np.full(H, torso_cx - (hand[0] - torso_cx) + fig * 0.045) if hand[0] > torso_cx else np.full(H, hand[0] + fig * 0.045)
    if rx is None:
        rx = np.full(H, hand[0] - fig * 0.045) if hand[0] > torso_cx else np.full(H, torso_cx + (torso_cx - hand[0]) - fig * 0.045)
    row = a[int(shoulder_y + fig * 0.02)]
    xs = np.nonzero(row)[0]
    sh_l = (float(xs.min()) + fig * 0.03 if len(xs) else torso_cx - fig * 0.1, shoulder_y + fig * 0.01)
    sh_r = (float(xs.max()) - fig * 0.03 if len(xs) else torso_cx + fig * 0.1, shoulder_y + fig * 0.01)
    return {"fig": fig, "gy": gy, "neck": neck, "shoulder_y": shoulder_y, "hip": hip, "hand": hand, "lx": lx, "rx": rx,
            "sh_l": sh_l, "sh_r": sh_r, "arm_y": (y_lo - fig * 0.05, y_hi)}


def _blink(img, eye, line, c):
    """눈 깜빡임: c 0 = 뜸, 1 = 감음. 위 눈꺼풀이 내려옴 = 눈 마스크 위쪽을 주변 피부색으로, 경계에 속눈썹 선.
    img RGBA·eye·line 은 float 배열 (제자리 수정)"""
    import numpy as np
    from scipy import ndimage
    if c <= 0:
        return
    em = eye > 90
    lab, n = ndimage.label(em)
    for k in range(1, n + 1):
        blob = ndimage.binary_dilation(lab == k, iterations=1)
        ys, xs = np.nonzero(blob)
        if len(xs) < 6:
            continue
        y0, y1 = ys.min(), ys.max()
        ring = ndimage.binary_dilation(blob, iterations=6) & ~ndimage.binary_dilation(blob, iterations=2) & (img[..., 3] > 200)
        lum = img[..., :3].mean(-1)
        ring &= lum > np.percentile(lum[ring], 35) if ring.sum() > 10 else ring
        skin = np.median(img[..., :3][ring], 0) if ring.sum() > 10 else np.array([200, 150, 120])
        box = img[y0:y1 + 1, xs.min():xs.max() + 1, :3].mean(-1)
        dark_col = img[y0:y1 + 1, xs.min():xs.max() + 1, :3].reshape(-1, 3)[np.argsort(box.ravel())[:max(3, box.size // 12)]].mean(0)
        lid = y0 + (y1 - y0) * (0.62 * c if c < 1 else 0.62)
        cover = blob & (np.arange(img.shape[0])[:, None] <= (lid if c < 1 else y1 + 1))
        img[..., :3][cover] = skin
        eye[cover] = 0
        # 눈꺼풀 선 (가운데가 살짝 아래로 휜 선)
        x0, x1 = xs.min(), xs.max()
        for x in range(x0, x1 + 1):
            t = (x - x0) / max(1, x1 - x0)
            yy = lid + (1.2 * np.sin(np.pi * t) if c >= 1 else 0)
            for dy, al in ((0, 1.0), (1, 0.6)):
                yi = int(round(yy)) + dy
                if blob[min(max(yi, 0), img.shape[0] - 1), x] or (c >= 1 and y0 <= yi <= y1 + 1):
                    img[yi, x, :3] = img[yi, x, :3] * (1 - al) + dark_col * al
                    img[yi, x, 3] = 255
                    line[yi, x] = max(line[yi, x], 255 * al)


def cmd_rig(cid, frames=32, fps=12.0, head_deg=1.2, arm_deg=0.8, breath=0.005, blink_at=0.62, blink=False):
    """원화(base.png) 한 장을 부위별로 휘어 idle 만들기 → <캐릭터>/idle/ (시트 idle_4x4 대신)
    다리·골반 고정 · 몸통 숨쉬기(어깨가 오르내림, 가슴 살짝 넓어짐) · 머리 = 목 기준 기울기 · 팔 = 어깨 기준 흔들림 · (blink=True 면) 눈 깜빡임 1번
    조명·선화·눈 마스크도 같은 움직임으로."""
    import math
    import numpy as np
    from scipy.ndimage import map_coordinates
    cdir = os.path.join(CHAR_DIR, cid)
    info = json.load(open(os.path.join(cdir, "character.json"), encoding="utf-8"))
    base = np.array(Image.open(os.path.join(cdir, "base.png")).convert("RGBA")).astype(np.float32)
    H, W = base.shape[:2]
    B = _rig_bones(cid, info, base[..., 3] > 40)
    fig = B["fig"]
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

    def sstep(e0, e1, v):
        t = np.clip((v - e0) / (e1 - e0), 0.0, 1.0)
        return t * t * (3 - 2 * t)
    # 가중치
    w_head = sstep(B["neck"][1] + fig * 0.02, B["neck"][1] - fig * 0.025, yy)
    feather = fig * 0.008
    arm_band = sstep(B["arm_y"][0] - fig * 0.06, B["arm_y"][0], yy) * (1 - sstep(B["arm_y"][1] - fig * 0.03, B["arm_y"][1], yy))
    w_al = sstep(B["lx"][:, None] + feather, B["lx"][:, None] - feather, xx) * arm_band * (1 - w_head)
    w_ar = sstep(B["rx"][:, None] - feather, B["rx"][:, None] + feather, xx) * arm_band * (1 - w_head)
    t_torso = np.clip((B["hip"] - yy) / max(1.0, B["hip"] - B["shoulder_y"]), 0.0, 1.0)
    w_torso = t_torso * t_torso * (3 - 2 * t_torso)
    srcs = {"": base}
    for suf in ("_mask_r", "_mask_l", "_line", "_eye"):
        mp = os.path.join(cdir, "base" + suf + ".png")
        if os.path.exists(mp):
            srcs[suf] = np.array(Image.open(mp).convert("L")).astype(np.float32)
    adir = os.path.join(cdir, "idle")
    os.makedirs(adir, exist_ok=True)
    for fn in os.listdir(adir):
        if fn.endswith(".png") or fn.endswith(".png.import"):
            os.remove(os.path.join(adir, fn))
    kb = int(round(frames * blink_at))
    blinks = {kb - 1: 0.55, kb: 1.0, kb + 1: 1.0, kb + 2: 0.5} if blink else {}

    def rot(px, py, cx, cy, deg):
        r = math.radians(deg)
        dx, dy = px - cx, py - cy
        return cx + dx * math.cos(r) - dy * math.sin(r) - px, cy + dx * math.sin(r) + dy * math.cos(r) - py
    for i in range(frames):
        ph = 2 * math.pi * i / frames
        b = 0.5 - 0.5 * math.cos(ph)                          # 0 → 들숨 1 → 0
        lift = -fig * breath * b                              # 어깨 높이 변화 (위 = -)
        # 몸통: 골반 위로 갈수록 더 올라감 + 가슴 살짝 넓어짐
        dxt = (xx - B["neck"][0]) * 0.006 * b * w_torso * (1 - sstep(B["shoulder_y"], B["neck"][1] - fig * 0.05, yy))
        dyt = lift * w_torso
        hd = head_deg * math.sin(ph - 0.9)                    # 머리: 숨보다 조금 늦게 갸웃
        hx, hy = rot(xx, yy, B["neck"][0], B["neck"][1], hd)
        hy = hy + lift - fig * 0.0015 * math.sin(ph - 0.4)    # 고개 살짝 끄덕임
        al = arm_deg * math.sin(ph - 0.5)
        lxd, lyd = rot(xx, yy, B["sh_l"][0], B["sh_l"][1], al)
        rxd, ryd = rot(xx, yy, B["sh_r"][0], B["sh_r"][1], -al * 0.8)
        lyd = lyd + lift
        ryd = ryd + lift
        w_rest = np.clip(1 - w_head - w_al - w_ar, 0, 1)
        DX = w_head * hx + w_al * lxd + w_ar * rxd + w_rest * dxt
        DY = w_head * hy + w_al * lyd + w_ar * ryd + w_rest * dyt
        sy, sx = yy - DY, xx - DX
        img = base.copy()
        eye = srcs.get("_eye", np.zeros((H, W), np.float32)).copy()
        line = srcs.get("_line", np.zeros((H, W), np.float32)).copy()
        _blink(img, eye, line, blinks.get(i, 0.0))
        out = np.zeros_like(img)
        for ch in range(4):
            out[..., ch] = map_coordinates(img[..., ch], [sy, sx], order=1, mode="constant", cval=0.0)
        stem = os.path.join(adir, "%04d" % (i + 1))
        Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)).save(stem + ".png")
        for suf, src in srcs.items():
            if suf == "":
                continue
            m = eye if suf == "_eye" else (line if suf == "_line" else src)
            w = map_coordinates(m, [sy, sx], order=1, mode="constant", cval=85.0 if "_mask_" in suf else 0.0)
            Image.fromarray(np.clip(w, 0, 255).astype(np.uint8)).save(stem + suf + ".png")
    json.dump({"fps": fps, "source": "rig: base.png 리깅 idle (%d장)" % frames}, open(os.path.join(adir, "anim.json"), "w", encoding="utf-8"), ensure_ascii=False)
    for fn in os.listdir(cdir):   # 예전 숨쉬기 시트는 지움 (폴더 idle 이 우선이지만 헷갈리지 않게)
        if fn.startswith("idle_4x4") or fn == "idle.json":
            os.remove(os.path.join(cdir, fn))
    print(cid, "리깅 idle", frames, "장", "목", tuple(round(v) for v in B["neck"]), "어깨", tuple(round(v) for v in B["sh_l"]), tuple(round(v) for v in B["sh_r"]),
          "팔 경계 y%d %.0f / %.0f" % (int(B["hand"][1]), B["lx"][int(B["hand"][1])], B["rx"][int(B["hand"][1])]))


# ---------------------------------------------------------------- 머리 바꿔 붙이기 (AI 시트의 뭉개진 얼굴 → 원화 머리)
def _head_palette(rgba, k=6, iters=20):
    """원화 머리의 대표 색 k개 (간단한 k-평균) — 머리카락·피부·모자 색이 캐릭터마다 달라도 맞추기 위해"""
    import numpy as np
    px = rgba[rgba[..., 3] > 200][:, :3].astype(np.float32)
    lum = px.mean(1)
    c = np.array([px[np.argsort(lum)[int(q * (len(px) - 1))]] for q in np.linspace(0.05, 0.95, k)])
    for _ in range(iters):
        d = ((px[:, None, :] - c[None]) ** 2).sum(-1)
        lab = d.argmin(1)
        for i in range(k):
            if (lab == i).any():
                c[i] = px[lab == i].mean(0)
    return c


def _palette_labels(rgba, centers, tol=55.0):
    """1..k = 가장 가까운 대표 색 (거리 tol 이내), k+1 = 그 밖의 그림, 0 = 투명"""
    import numpy as np
    a = rgba.astype(np.float32)
    d = ((a[..., None, :3] - centers[None, None]) ** 2).sum(-1)
    lab = (d.argmin(-1) + 1).astype(np.uint8)
    lab[d.min(-1) > tol * tol] = len(centers) + 1
    lab[a[..., 3] <= 100] = 0
    return lab


def _circ_smooth(vals, w):
    """둥글게 이어지는(반복) 값 매끄럽게 — 삼각 가중 평균, 처음·끝 프레임이 이어짐"""
    n = len(vals)
    if n == 0 or w <= 0:
        return list(vals)
    out = []
    for i in range(n):
        tot = wsum = 0.0
        for k in range(-w, w + 1):
            wt = w + 1 - abs(k)
            tot += vals[(i + k) % n] * wt
            wsum += wt
        out.append(tot / wsum)
    return out


def _torso_offsets(frames, box, hair_masks, search=36, step=2):
    """프레임마다 윗몸(어깨·가슴, 머리카락 색 뺌)이 첫 프레임보다 얼마나 옮겨졌나 [(dx, dy)] — 반 크기에서 차이가 가장 작은 이동"""
    import numpy as np
    x0, y0, x1, y1 = box
    def gray(fa, hm):
        g = fa[..., :3].astype(np.float32).mean(-1) * (fa[..., 3] > 120)
        g[hm] = -1.0   # 머리카락 = 비교 안 함
        return g[::2, ::2]
    ref = gray(frames[0], hair_masks[0])
    hx0, hy0, hx1, hy1 = x0 // 2, y0 // 2, x1 // 2, y1 // 2
    r = ref[hy0:hy1, hx0:hx1]
    out = [(0.0, 0.0)]
    for fa, hm in zip(frames[1:], hair_masks[1:]):
        g = gray(fa, hm)
        best = None
        for dy in range(-search // 2, search // 2 + 1, step // 2 or 1):
            for dx in range(-search // 2, search // 2 + 1, step // 2 or 1):
                if hy0 + dy < 0 or hx0 + dx < 0 or hy1 + dy > g.shape[0] or hx1 + dx > g.shape[1]:
                    continue
                w = g[hy0 + dy:hy1 + dy, hx0 + dx:hx1 + dx]
                ok = (w >= 0) & (r >= 0) & ((w > 0) | (r > 0))
                if ok.sum() < r.size * 0.2:
                    continue
                d = np.abs(w[ok] - r[ok]).mean()
                if best is None or d < best[0]:
                    best = (d, dx * 2.0, dy * 2.0)
        out.append((best[1], best[2]) if best else (0.0, 0.0))
    return out


def cmd_head(cid, anim, cut=None, src=None, max_deg=14, scales=(0.85, 1.15), smooth=True, keep_deg=3.0):
    """<동작>/ 프레임마다 머리를 원화(base.png) 머리로 바꿔 붙임 — AI 시트 얼굴이 뭉개졌을 때.
    원화에서 턱 아래(cut, 기본 = head_rect 아래 끝보다 키의 3.5% 위)까지 잘라, 프레임마다 원화 머리 대표 색(머리카락·피부·모자…) 영역이 가장 잘 겹치는
    크기(0.85~1.15배)·기울기(±14°)·위치를 찾음. smooth(기본) = 그 값을 프레임마다 따로 쓰지 않고 머리를 목에 붙임:
      · 크기·기울기 = 모든 프레임 같은 값 (찾은 값들의 가운데, 기울기는 ±keep_deg 안)
      · 위치 = 목·옷깃·어깨가 첫 프레임보다 옮겨진 만큼만 따라감 (그 기준 머리 자리 = 찾은 값들의 가운데)
    → 걷기·뛰기에서 머리가 몸과 따로 흔들리지 않고 목 위에서 몸과 같이 움직임. 그 밖으로 삐져나온 원래 머리카락은 지움. 목 쪽은 부드럽게 섞음.
    조명·선화·눈 마스크도 다시 (눈 = 원화 눈 마스크를 같은 위치로)."""
    import math
    import numpy as np
    from scipy import ndimage
    cdir = os.path.join(CHAR_DIR, cid)
    info = json.load(open(os.path.join(cdir, "character.json"), encoding="utf-8"))
    base = Image.open(os.path.join(cdir, src or "base.png")).convert("RGBA")
    bey = os.path.join(cdir, "base_eye.png")
    beye = Image.open(bey).convert("L") if os.path.exists(bey) else Image.new("L", base.size, 0)
    fig = float(info.get("figure_px", base.height))
    hr = info["head_rect"]
    cut = float(cut) if cut is not None else hr[1] + hr[3] - fig * 0.035
    ba = np.array(base)
    ys, xs = np.nonzero(ba[: int(cut), :, 3] > 20)
    x0, y0, x1 = int(xs.min()) - 4, max(0, int(ys.min()) - 4), int(xs.max()) + 5
    # 원화 머리 대표 색으로 영역 나눔 (머리카락 색 무관) + 머리에만 있는 색(머리카락·모자 등 = 원화 몸에는 거의 없는 색)
    hb = ba[y0:int(cut), x0:x1]
    pal = _head_palette(hb)
    other = len(pal) + 1
    labels = lambda arr: _palette_labels(arr, pal)
    hl_b, bl_b = labels(hb), labels(ba[int(cut):])
    head_only = [i for i in range(1, other) if (bl_b == i).mean() < 0.05 * max(1e-6, (hl_b == i).mean())]
    # 자른 선 아래로 늘어진 머리카락(묶은 머리 등)은 머리카락 색만 조금 더 (키의 3%) — 옷깃은 안 가져옴
    y1 = min(ba.shape[0], int(cut + fig * 0.03))
    head = ba[y0:y1, x0:x1].copy()
    lab_h = labels(head)
    hair = np.isin(lab_h, head_only)
    feather = max(4, int(fig * 0.012))   # 아래쪽 경계(목)를 이만큼 부드럽게
    rows = np.arange(y1 - y0)[:, None]
    cut_r = int(cut) - y0
    fade = np.clip((cut_r - rows) / float(feather), 0, 1)
    below_keep = ndimage.binary_dilation(hair & (rows >= cut_r - feather), iterations=2)   # 머리카락 + 테두리 선
    hair_conn = ndimage.binary_propagation(below_keep & (rows < cut_r + 1), mask=below_keep)   # 위쪽 머리카락과 이어진 것만
    keep = np.where(hair_conn, 1.0, fade)
    head[..., 3] = (head[..., 3] * keep).astype(np.uint8)
    head_im = Image.fromarray(head)
    eye_im = beye.crop((x0, y0, x1, y1))
    anchor = (hr[0] + hr[2] / 2.0 - x0, cut - y0)        # 붙일 때 맞추는 점: 목(머리 가운데 · 자른 선)
    adir = os.path.join(cdir, anim)
    names = sorted(f for f in os.listdir(adir) if re.match(r"^\d+\.png$", f))
    k = 0.5                                               # 찾기는 반 크기로

    def fit(fa, sc_list, deg_list):
        fys = np.nonzero(fa[..., 3].max(1) > 20)[0]
        top = int(fys.min())
        fl = labels(fa)
        best = None
        for sc in sc_list:
            for deg in deg_list:
                t = head_im.resize((max(1, int(head_im.width * sc * k)), max(1, int(head_im.height * sc * k))), Image.BILINEAR)
                ax, ay = anchor[0] * sc * k, anchor[1] * sc * k
                t = t.rotate(deg, resample=Image.BILINEAR, center=(ax, ay), expand=False)
                tl = labels(np.array(t))
                th, tw = tl.shape
                nz = tl > 0
                # 위치: 머리 맨 위 ≈ 프레임 맨 위, 가로는 넓게
                ty0 = int(top * k - (np.nonzero(nz.any(1))[0].min()))
                for dy in range(-6, 7, 2):
                    for dx in range(-int(60 * k), int(60 * k) + 1, 2):
                        px = int(fa.shape[1] * k / 2 - tw / 2) + dx + int((anchor[0] + x0 - fa.shape[1] / 2) * k)
                        py = ty0 + dy
                        if px < 0 or py < 0 or px + tw > fa.shape[1] * k or py + th > fa.shape[0] * k:
                            continue
                        win = fl[int(py / k):int((py + th) / k):2, int(px / k):int((px + tw) / k):2][:th, :tw]
                        if win.shape != tl.shape:
                            continue
                        both = (win > 0) | nz
                        score = ((win == tl) & nz & (tl < other)).sum() / max(1, both.sum())
                        if best is None or score > best[0]:
                            best = (score, sc, deg, (px + ax) / k, (py + ay) / k)
        return best

    frames = [np.array(Image.open(os.path.join(adir, fn)).convert("RGBA")) for fn in names]
    sc_list = list(np.arange(scales[0], scales[1] + 0.001, 0.05))
    deg_list = list(range(-max_deg, max_deg + 1, 2))
    fits = [fit(fa, sc_list, deg_list) for fa in frames]
    if smooth and len(frames) > 2:
        sc_med = float(np.median([f[1] for f in fits]))
        deg_lim = int(min(max_deg, max(2, keep_deg * 2)))
        fits = [fit(fa, [sc_med], list(range(-deg_lim, deg_lim + 1, 1))) for fa in frames]   # 같은 크기로 다시 찾기
        deg_c = float(np.clip(np.median([f[2] for f in fits]), -keep_deg, keep_deg))
        # 윗몸(턱 선 바로 아래 목·옷깃·어깨) 이동
        nx_m, ny_m = float(np.median([f[3] for f in fits])), float(np.median([f[4] for f in fits]))
        hw = int(fig * 0.085)   # 목·옷깃·어깨 윗부분 (팔이 잘 안 들어오는 곳)
        box = (max(0, int(nx_m - hw)), int(ny_m + fig * 0.005), min(frames[0].shape[1], int(nx_m + hw)), min(frames[0].shape[0], int(ny_m + fig * 0.085)))
        hairs = [np.isin(labels(fa), head_only) for fa in frames]
        offs = _torso_offsets(frames, box, hairs)
        offs = list(zip(_circ_smooth([o[0] for o in offs], 1), _circ_smooth([o[1] for o in offs], 1)))
        rel_x = float(np.median([f[3] - o[0] for f, o in zip(fits, offs)]))
        rel_y = float(np.median([f[4] - o[1] for f, o in zip(fits, offs)]))
        fits = [(f[0], sc_med, deg_c, rel_x + o[0], rel_y + o[1]) for f, o in zip(fits, offs)]
    log = []
    for fn, fa, best in zip(names, frames, fits):
        path = os.path.join(adir, fn)
        fr = Image.fromarray(fa)
        score, sc, deg, nx, ny = best
        # 원래 크기로 붙이기
        t = head_im.resize((max(1, round(head_im.width * sc)), max(1, round(head_im.height * sc))), Image.LANCZOS)
        e = eye_im.resize(t.size, Image.LANCZOS)
        ax, ay = anchor[0] * sc, anchor[1] * sc
        t = t.rotate(deg, resample=Image.BICUBIC, center=(ax, ay))
        e = e.rotate(deg, resample=Image.BICUBIC, center=(ax, ay))
        ox, oy = int(round(nx - ax)), int(round(ny - ay))
        layer = Image.new("RGBA", fr.size, (0, 0, 0, 0))
        layer.alpha_composite(t, (max(0, ox), max(0, oy)), (max(0, -ox), max(0, -oy)))
        la = np.array(layer)[..., 3].astype(np.float32) / 255.0
        # 붙인 머리 밖으로 삐져나온 원래 머리(자른 선 위쪽)는 지움 — 머리 둘레만. 자른 선은 붙인 머리와 같이 기울어짐
        near = ndimage.binary_dilation(la > 0.05, iterations=int(fig * 0.06))
        th = math.radians(deg)
        gy_, gx_ = np.mgrid[0:fa.shape[0], 0:fa.shape[1]]
        v = (gx_ - nx) * math.sin(th) + (gy_ - ny) * math.cos(th)   # 붙인 머리 기준 세로 위치 (자른 선 = 0)
        erase = near & (v < -feather) & (la < 0.5)
        # 자른 선 바로 아래로 늘어진 원래 머리카락(몸에는 없는 색)도 지움
        fl_now = labels(fa)
        erase |= near & (v >= -feather) & (v < fig * 0.04) & (la < 0.5) & np.isin(fl_now, head_only)
        fa = fa.copy()
        fa[..., 3] = np.where(erase, 0, fa[..., 3])
        out = Image.fromarray(fa)
        out.alpha_composite(layer)
        # 지우고 남은 머리카락 조각(본체와 떨어진 작은 섬)은 머리 둘레에서만 지움
        oa = np.array(out)
        lab_c, n_c = ndimage.label(oa[..., 3] > 20)
        if n_c > 1:
            sizes = ndimage.sum(np.ones_like(lab_c), lab_c, range(1, n_c + 1))
            small = [i + 1 for i in range(n_c) if sizes[i] < fig * fig * 0.0008]
            drop = np.isin(lab_c, small) & near
            oa[..., 3] = np.where(drop, 0, oa[..., 3])
            out = Image.fromarray(oa)
        out.save(path)
        stem = path[:-4]
        mr, ml = make_masks(out)
        mr.save(stem + "_mask_r.png")
        ml.save(stem + "_mask_l.png")
        line_mask(out).save(stem + "_line.png")
        eye_layer = Image.new("L", fr.size, 0)
        eye_layer.paste(e, (ox, oy))
        eye_layer.save(stem + "_eye.png")
        log.append("%s %.2f배 %+.1f° (%d,%d)" % (fn, sc, deg, round(nx), round(ny)))
    print(cid, anim, "머리 바꿔 붙임%s:" % (" (윗몸에 붙임 — 크기·기울기 고정)" if smooth else ""), ", ".join(log))


# ---------------------------------------------------------------- 발 닿는 프레임 (발자국 소리 맞추기)
def cmd_steps(cid, anims=("walk", "run")):
    """걷기·뛰기 한 주기에서 발이 땅에 닿는 프레임 2개 → anim.json "steps" (0부터).
    점수 = 뛰기(발 높이가 변함)는 가장 낮은 프레임, 걷기는 두 발이 가장 벌어진 프레임(발 높이 띠의 가로 폭). 가장 높은 프레임과,
    그로부터 주기의 1/3 이상 떨어진 프레임 중 가장 높은 것. 게임은 이 프레임이 보일 때 발자국 한 조각을 재생."""
    import numpy as np
    for anim in anims:
        adir = os.path.join(CHAR_DIR, cid, anim)
        aj = os.path.join(adir, "anim.json")
        if not os.path.isdir(adir):
            continue
        names = sorted(f for f in os.listdir(adir) if re.match(r"^\d+\.png$", f))
        if len(names) < 4:
            continue
        spread, bottom = [], []
        for fn in names:
            a = np.array(Image.open(os.path.join(adir, fn)))[..., 3] > 40
            ys = np.nonzero(a.any(1))[0]
            top, bot = int(ys.min()), int(ys.max())
            band = a[bot - max(3, int((bot - top) * 0.06)):bot + 1]
            xs = np.nonzero(band.any(0))[0]
            spread.append(float(xs.max() - xs.min()))
            bottom.append(float(bot))
        sp, bo = np.array(spread), np.array(bottom)
        norm = lambda v: (v - v.min()) / max(1e-6, v.max() - v.min())
        # 뛰기처럼 뜨는 동작(발 높이가 변함) = 가장 낮은 프레임이 착지 (공중에서 다리를 벌린 프레임은 폭이 넓어도 착지 아님)
        # 걷기(발이 늘 땅) = 두 발이 가장 벌어진 프레임이 앞발 착지
        score = norm(bo) if bo.max() - bo.min() > 4 else norm(sp)
        n = len(names)
        i = int(np.argmax(score))
        far = [k for k in range(n) if min(abs(k - i), n - abs(k - i)) >= n / 3]
        j = max(far, key=lambda k: score[k])
        meta = json.load(open(aj, encoding="utf-8")) if os.path.exists(aj) else {}
        meta["steps"] = sorted([i, j])
        json.dump(meta, open(aj, "w", encoding="utf-8"), ensure_ascii=False)
        print(cid, anim, "발 닿는 프레임", meta["steps"], "(%d장 중)" % n)


def cmd_export(cid, anims=("idle", "walk", "run"), cols=6, out=None):
    """동작 프레임(<동작>/0001.png …, 원화 색 — 마스크·선화 제외) → 스프라이트 시트 한 장씩.
    칸 = 모든 동작의 발 위치(anim.json ground, 없으면 character.json)를 맞춘 공통 크기."""
    cdir = os.path.join(CHAR_DIR, cid)
    cj = json.load(open(os.path.join(cdir, "character.json"), encoding="utf-8"))
    out = os.path.join(out or os.path.join(ROOT, "exports", "sheets"), cid)
    os.makedirs(out, exist_ok=True)
    items = []
    for anim in anims:
        adir = os.path.join(cdir, anim)
        names = sorted(f for f in os.listdir(adir) if re.match(r"^\d+\.png$", f)) if os.path.isdir(adir) else []
        if not names:
            print(cid, anim, "프레임 없음 — 건너뜀")
            continue
        aj = os.path.join(adir, "anim.json")
        meta = json.load(open(aj, encoding="utf-8")) if os.path.exists(aj) else {}
        frames = [Image.open(os.path.join(adir, f)).convert("RGBA") for f in names]
        gx, gy = meta.get("ground", cj["ground"])
        items.append((anim, frames, int(gx), int(gy), meta))
    if not items:
        return
    left = max(gx for _, _, gx, _, _ in items)
    top = max(gy for _, _, _, gy, _ in items)
    right = max(max(f.width for f in fr) - gx for _, fr, gx, _, _ in items)
    bottom = max(max(f.height for f in fr) - gy for _, fr, _, gy, _ in items)
    cw, ch = left + right, top + bottom
    previews = []
    for anim, frames, gx, gy, meta in items:
        n = len(frames)
        c = min(cols, n)
        r = (n + c - 1) // c
        sheet = Image.new("RGBA", (cw * c, ch * r), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            sheet.paste(f, ((i % c) * cw + left - gx, (i // c) * ch + top - gy))
        path = os.path.join(out, "%s_sheet.png" % anim)
        sheet.save(path, optimize=True)
        info = {"character": cid, "anim": anim, "frame_size": [cw, ch], "cols": c, "rows": r, "frames": n,
                "fps": float(meta.get("fps", cj.get("fps", 12))), "loop": bool(meta.get("loop", True)),
                "ground": [left, top], "figure_px": float(meta.get("figure_px", cj.get("figure_px", 0))),
                "order": "왼쪽 위부터 가로로", "source": meta.get("source", "")}
        if "durations" in meta:
            info["durations"] = meta["durations"]
        if "steps" in meta:
            info["steps"] = meta["steps"]
        json.dump(info, open(os.path.join(out, "%s_sheet.json" % anim), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print(cid, anim, "→", os.path.relpath(path, ROOT), "%d장 · %d×%d 칸 · %d열×%d행 · %.0ffps" % (n, cw, ch, c, r, info["fps"]))
        previews.append((anim, sheet))
    # 미리보기: 시트들을 1/4 로 줄여 세로로 이어 붙임
    k = 4
    small = [(a, s.resize((s.width // k, s.height // k), Image.LANCZOS)) for a, s in previews]
    pw = max(s.width for _, s in small)
    pv = Image.new("RGBA", (pw, sum(s.height + 8 for _, s in small)), (40, 44, 52, 255))
    y = 0
    for _, s in small:
        pv.alpha_composite(s, (0, y))
        y += s.height + 8
    pv.convert("RGB").save(os.path.join(out, "preview.jpg"), quality=85)


def cmd_rows(cid, rows=("idle", "walk", "walk:l", "run", "run:l"), name="rows", scales=(1.0, 0.5), out=None):
    """동작마다 한 줄인 긴 시트 한 장. 'walk:l' = walk 를 좌우로 뒤집은 왼쪽 보기 (원본 프레임 = 오른쪽 보기).
    칸 = 모든 동작의 발(ground)이 칸 가운데 아래에 오는 공통 크기 → 뒤집어도 발 위치가 같음."""
    cdir = os.path.join(CHAR_DIR, cid)
    cj = json.load(open(os.path.join(cdir, "character.json"), encoding="utf-8"))
    out = os.path.join(out or os.path.join(ROOT, "exports", "sheets"), cid)
    os.makedirs(out, exist_ok=True)
    cache, lines = {}, []
    for spec in rows:
        anim, _, side = spec.partition(":")
        if anim not in cache:
            adir = os.path.join(cdir, anim)
            names = sorted(f for f in os.listdir(adir) if re.match(r"^\d+\.png$", f)) if os.path.isdir(adir) else []
            if not names:
                print(cid, anim, "프레임 없음 — 건너뜀")
                continue
            aj = os.path.join(adir, "anim.json")
            meta = json.load(open(aj, encoding="utf-8")) if os.path.exists(aj) else {}
            gx, gy = meta.get("ground", cj["ground"])
            cache[anim] = ([Image.open(os.path.join(adir, f)).convert("RGBA") for f in names], int(gx), int(gy), meta)
        lines.append((anim, side == "l", *cache[anim]))
    if not lines:
        return
    half = max(max(gx, max(f.width for f in fr) - gx) for _, _, fr, gx, _, _ in lines)
    top = max(gy for _, _, _, _, gy, _ in lines)
    bottom = max(max(f.height for f in fr) - gy for _, _, fr, _, gy, _ in lines)
    cw, ch = half * 2, top + bottom
    cols = max(len(fr) for _, _, fr, _, _, _ in lines)
    sheet = Image.new("RGBA", (cw * cols, ch * len(lines)), (0, 0, 0, 0))
    info_rows = []
    for r, (anim, flip, frames, gx, gy, meta) in enumerate(lines):
        for i, f in enumerate(frames):
            x = half - gx
            if flip:
                f = f.transpose(Image.FLIP_LEFT_RIGHT)
                x = half - (f.width - gx)
            sheet.paste(f, (i * cw + x, r * ch + top - gy))
        row = {"row": r, "anim": anim, "facing": "left" if flip else "right", "frames": len(frames),
               "fps": float(meta.get("fps", cj.get("fps", 12))), "loop": bool(meta.get("loop", True))}
        for k in ("durations", "steps"):
            if k in meta:
                row[k] = meta[k]
        info_rows.append(row)
        print(cid, "%d줄" % (r + 1), anim, row["facing"], "%d장 · %.0ffps" % (len(frames), row["fps"]))
    files = []
    for sc in scales:
        img = sheet if sc == 1 else sheet.resize((round(sheet.width * sc), round(sheet.height * sc)), Image.LANCZOS)
        fn = "%s.png" % name if sc == 1 else "%s_x%g.png" % (name, sc)
        img.save(os.path.join(out, fn), optimize=True)
        files.append({"file": fn, "scale": sc, "size": [img.width, img.height], "frame_size": [round(cw * sc), round(ch * sc)],
                      "ground": [round(half * sc), round(top * sc)]})
        print(" →", os.path.relpath(os.path.join(out, fn), ROOT), "%d×%d (칸 %d×%d)" % (img.width, img.height, round(cw * sc), round(ch * sc)))
    json.dump({"character": cid, "cols": cols, "rows": len(lines), "frame_size": [cw, ch], "ground": [half, top],
               "order": "줄마다 동작 하나, 왼쪽부터 프레임 순서 (짧은 줄의 남는 칸은 투명)", "files": files, "lines": info_rows},
              open(os.path.join(out, "%s.json" % name), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    pv = sheet.resize((sheet.width // 12, sheet.height // 12), Image.LANCZOS)
    bg = Image.new("RGBA", pv.size, (40, 44, 52, 255))
    bg.alpha_composite(pv)
    bg.convert("RGB").save(os.path.join(out, "%s_preview.jpg" % name), quality=85)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["masks"]:
        cmd_masks(args[1] if len(args) > 1 else None)
    elif args[:1] == ["lines"]:
        cmd_lines(args[1] if len(args) > 1 else None)
    elif args[:1] == ["hat"] and len(args) >= 3:
        cmd_hat(args[1], int(args[2]))
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
    elif args[:1] == ["head"] and len(args) >= 3:
        opt = {a[2:]: args[i + 1] for i, a in enumerate(args) if a.startswith("--") and i + 1 < len(args)}
        cmd_head(args[1], args[2], opt.get("cut"), None, int(opt.get("deg", 14)),
                 tuple(float(v) for v in opt.get("scale", "0.85-1.15").split("-")),
                 "--no-smooth" not in args, float(opt.get("keep-deg", 3.0)))
    elif args[:1] == ["export"] and len(args) >= 2:
        opt = {a[2:]: args[i + 1] for i, a in enumerate(args) if a.startswith("--") and i + 1 < len(args)}
        skip = {args[i + 1] for i, a in enumerate(args) if a.startswith("--") and i + 1 < len(args)}
        names = tuple(a for a in args[2:] if not a.startswith("--") and a not in skip)
        cmd_export(args[1], names or ("idle", "walk", "run"), int(opt.get("cols", 6)), opt.get("out"))
    elif args[:1] == ["rows"] and len(args) >= 2:
        opt = {a[2:]: args[i + 1] for i, a in enumerate(args) if a.startswith("--") and i + 1 < len(args)}
        skip = {args[i + 1] for i, a in enumerate(args) if a.startswith("--") and i + 1 < len(args)}
        specs = tuple(a for a in args[2:] if not a.startswith("--") and a not in skip)
        cmd_rows(args[1], specs or ("idle", "walk", "walk:l", "run", "run:l"), opt.get("name", "rows"),
                 tuple(float(v) for v in opt.get("scale", "1,0.5").split(",")), opt.get("out"))
    elif args[:1] == ["steps"] and len(args) >= 2:
        cmd_steps(args[1], tuple(args[2:]) or ("walk", "run"))
    elif args[:1] == ["rig"] and len(args) >= 2:
        nums = [a for a in args[2:] if a.isdigit()]
        cmd_rig(args[1], int(nums[0]) if nums else 32, blink="--blink" in args)
    elif args[:1] in (["sheet"], ["report"]) and len(args) >= 2:
        opts = {}
        rest = []
        it = iter(args[1:])
        for a in it:
            if a.startswith("--"):
                opts[a[2:]] = next(it)
            else:
                rest.append(a)
        grid = tuple(int(v) for v in opts.get("grid", "6x6").lower().split("x"))
        if args[0] == "report":
            lo, hi = (int(v) for v in opts.get("loop", "8-36").split("-"))
            cmd_sheet_report(rest[0], grid, opts.get("align", "ground") == "ground", lo, hi)
        else:
            cmd_sheet(rest[0], rest[1], rest[2], grid, opts.get("frames"), float(opts.get("fps", 12)), opts.get("align", "ground"),
                      int(opts.get("ref", 1)), {"1": True, "0": False}.get(opts.get("loop", ""), None),
                      {"1": True, "0": False}.get(opts.get("weapon", ""), None), None,
                      float(opts["ref-height"]) if "ref-height" in opts else None, opts.get("anchor", "feet"))
    else:
        print(__doc__)
        sys.exit(1)
