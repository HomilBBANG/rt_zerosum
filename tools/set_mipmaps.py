#!/usr/bin/env python3
"""색 텍스처(캐릭터·무기·리그 파츠·배경·얼굴)의 Godot 임포트 설정에 밉맵을 켠다.
화면에서 크게 축소되는 원화가 계단 현상 없이 보이게 하기 위함. 구역 마스크(_mask)는 코드값이 섞이면 안 되므로 끈 채로 둔다.
사용: godot --headless --import 로 .import 파일이 생긴 뒤 실행 → 다시 --import."""
import glob, os, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pats = ["assets/sprites/*.png", "assets/sprites/rig_*/*.png", "assets/textures/*.png"]
changed = 0
for pat in pats:
    for png in glob.glob(os.path.join(ROOT, pat)):
        name = os.path.basename(png)
        imp = png + ".import"
        if "_mask" in name or name.startswith("_") or not os.path.exists(imp):
            continue
        s = open(imp, encoding="utf-8").read()
        n = re.sub(r"mipmaps/generate=false", "mipmaps/generate=true", s)
        if n != s:
            open(imp, "w", encoding="utf-8").write(n)
            changed += 1
print("mipmaps enabled:", changed)
