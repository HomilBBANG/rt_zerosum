#!/usr/bin/env python3
"""몬스터 스킬 초기 데이터(data/monster_skills.json) 생성. 처음 한 번만 — 이후에는 Godot 에디터 '스킬 트리' 탭 → '몬스터 스킬' 에서 고치는 파일이 원본.
주의: 다시 실행하면 에디터에서 고친 값을 덮어씀. (사용: python3 tools/gen_monster_skills.py --force)"""
import os, sys, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "monster_skills.json")
if os.path.exists(OUT) and "--force" not in sys.argv:
    sys.exit("data/monster_skills.json 이 이미 있습니다 (에디터에서 고친 값이 사라지므로 덮어쓰려면 --force)")

DATA = {
    "version": 1,
    "skills": [
        {
            "id": "rend",
            "name": "할퀴기",
            "kind": "heavy",
            "ap": 2,
            "target": "weapon",
            "effect": "damage",
            "power": 9,
            "desc": "맞으면 출혈"
        },
        {
            "id": "grave_chill",
            "name": "무덤의 냉기",
            "kind": "attack",
            "ap": 2,
            "target": "enemy_any",
            "effect": "damage",
            "power": 4,
            "desc": "열 무관, 맞으면 동상"
        },
        {
            "id": "hamstring",
            "name": "발목 물기",
            "kind": "attack",
            "ap": 2,
            "target": "weapon",
            "effect": "damage",
            "power": 7,
            "desc": "맞으면 구속 (자리 이동 불가)"
        },
        {
            "id": "sand_kick",
            "name": "모래 차기",
            "kind": "attack",
            "ap": 1,
            "target": "weapon",
            "effect": "damage",
            "power": 2,
            "desc": "맞으면 실명 (대상 무작위)"
        }
    ],
    "kits": {
        "ghoul": [
            "basic_attack",
            "heavy_attack",
            "rend",
            "grave_chill",
            "ultimate"
        ],
        "wolf": [
            "basic_attack",
            "heavy_attack",
            "hamstring",
            "sand_kick",
            "ultimate"
        ],
        "slime": [
            "basic_attack",
            "heavy_attack"
        ]
    }
}
with open(OUT, "w", encoding="utf-8") as f:
    f.write(json.dumps(DATA, ensure_ascii=False, indent="\t"))
print(OUT, len(DATA["skills"]), len(DATA["kits"]))
