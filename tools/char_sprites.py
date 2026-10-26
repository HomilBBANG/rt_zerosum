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
  python3 tools/char_sprites.py masks            프레임마다 조명 마스크(<프레임>_mask_l/_r.png)가 없으면 만든다
  python3 tools/char_sprites.py masks dan        한 캐릭터만
  python3 tools/char_sprites.py import <캐릭터> <동작> <파일…> [--grid 4x2] [--fps 12] [--hold 0.35]
      움직이는 GIF·WebP(APNG) → 프레임마다, 스프라이트 시트 → --grid 열x행 칸마다, PNG 여러 장 → 그 순서대로
      첫 프레임의 발·키를 base.png 에 맞추는 같은 이동·배율을 모든 프레임에 적용 (프레임 사이 움직임은 그대로)
      → assets/characters/<캐릭터>/<동작>/0001.png … + anim.json(움직이는 파일의 프레임 시간) + 조명 마스크
(지금 base.png·마스크·character.json 은 예전 Skeleton2D 리그를 쉬는 자세로 합쳐 만든 것 — 리그는 제거됨)
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from gen_sprites import build_zone_mask  # noqa: E402

CHAR_DIR = os.path.join(ROOT, "assets", "characters")


def make_masks(im, k=0.5):
    """원화(RGBA)에서 빛 오른쪽/왼쪽 구역 마스크 (리그 도구와 같은 규칙: 림 두께·경계 부드럽게, 원화 0.5배 기준)"""
    rim = max(2, round(11 * k))
    smooth = round(90 * k)
    return (build_zone_mask(im, [], "right", rim=rim, smooth=smooth),
            build_zone_mask(im, [], "left", rim=rim, smooth=smooth))


def cmd_masks(only=None):
    n = 0
    for cid in sorted(os.listdir(CHAR_DIR)):
        cdir = os.path.join(CHAR_DIR, cid)
        if not os.path.isdir(cdir) or (only and cid != only):
            continue
        for anim in sorted(os.listdir(cdir)):
            adir = os.path.join(cdir, anim)
            if not os.path.isdir(adir):
                continue
            for fn in sorted(os.listdir(adir)):
                if not fn.endswith(".png") or "_mask_" in fn:
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


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["masks"]:
        cmd_masks(args[1] if len(args) > 1 else None)
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
