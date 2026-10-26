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
(지금 base.png·마스크·character.json 은 예전 Skeleton2D 리그를 쉬는 자세로 합쳐 만든 것 — 리그는 제거됨)
"""
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


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] != "masks":
        print(__doc__)
        sys.exit(1)
    cmd_masks(sys.argv[2] if len(sys.argv) > 2 else None)
