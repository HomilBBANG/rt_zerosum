#!/usr/bin/env python3
"""스킬 상태 이상 초기 데이터(data/skill_status.json) 생성. 처음 한 번만 — 이후에는 Godot 에디터 '스킬 트리' 탭 → '상태 이상' 에서 고치는 파일이 원본.
주의: 다시 실행하면 에디터에서 고친 값을 덮어씀. (사용: python3 tools/gen_skill_status.py --force)"""
import os, sys, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "skill_status.json")
if os.path.exists(OUT) and "--force" not in sys.argv:
    sys.exit("data/skill_status.json 이 이미 있습니다 (에디터에서 고친 값이 사라지므로 덮어쓰려면 --force)")

# [임시] (스킬 id, 상태, 턴, 수치, 확률)
STATUSES = [
    ("painkiller_shot", "regen_2", 3, 8, 100), ("self_heal", "regen_3", 3, 6, 100),   # 상태 정의(data/statuses.json): regen_2 진통제 · regen_3 자가 치유 = 효과 재생
    ("brutal_strike", "stun", 1, 0, 50),
    ("flank", "bleed", 2, 10, 100),
    ("inspire", "haste", 2, 30, 100),
    ("incendiary", "burn", 2, 4, 100),
    ("suppress", "slow", 2, 30, 100),
    ("rend", "bleed", 2, 8, 100),
    ("grave_chill", "frost", 2, 20, 100),
    ("hamstring", "root", 2, 0, 100),
    ("sand_kick", "blind", 1, 0, 70),
]
with open(OUT, "w", encoding="utf-8") as f:
    f.write(json.dumps({"version": 1, "statuses": [{"skill": a, "status": b, "turns": c, "value": d, "chance": e} for a, b, c, d, e in STATUSES]},
                       ensure_ascii=False, indent="\t"))
print(OUT, len(STATUSES))
