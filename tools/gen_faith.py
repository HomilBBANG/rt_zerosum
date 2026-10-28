#!/usr/bin/env python3
"""신앙 초기 데이터(data/faith.json) 생성. 처음 한 번만 — 이후에는 Godot 에디터 '스킬 트리' 탭 → '신앙' 에서 고치는 파일이 원본.
주의: 다시 실행하면 에디터에서 고친 신·신앙 스킬을 덮어씀. (사용: python3 tools/gen_faith.py --force)"""
import os, sys, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "faith.json")
if os.path.exists(OUT) and "--force" not in sys.argv:
    sys.exit("data/faith.json 이 이미 있습니다 (에디터에서 고친 값이 사라지므로 덮어쓰려면 --force)")

# 신앙 [임시 데이터 — 나중에 사용자 표로 교체]: 신 종류마다 배울 수 있는 신앙 스킬이 다름
GOD_COLS = ["id", "이름", "상징색", "설명"]
GODS = [
    ["solus", "태양신 솔루스", "#ffd166", "빛과 치유의 신 — 회복·체력 (임시)"],
    ["veyra", "전쟁신 베이라", "#ff5a4e", "피와 전투의 신 — 공격 위력 (임시)"],
    ["noct", "밤의 여신 녹트", "#8f7bff", "그림자와 은밀함의 신 — 속도·AP (임시)"],
    ["terra", "대지모 테라", "#5fd38a", "땅과 수호의 신 — 방어·체력 (임시)"],
]
# 누가 어느 신을 믿는지 · 시작 신앙도 (0~100, 출전마다 + 기지 설정 faith_battle)
BELIEVERS = {"a_dan": {"god": "veyra", "faith": 30}, "a_kira": {"god": "noct", "faith": 20}, "a_ethan": {"god": "solus", "faith": 40},
             "a_hana": {"god": "terra", "faith": 10}, "a_alma": {"god": "solus", "faith": 50}, "a_nikita": {"god": "noct", "faith": 25}}
# [임시] 신 해금 캐릭터: 정체가 신 — 조건을 채우면 신앙 탭이 '기적' 으로 / 그 캐릭터만의 기적 (필요 신성도 = 신앙도 값)
DIVINE = {"a_hana": {"god": "terra", "unlocked": False, "condition": {"type": "quest", "value": 0, "target": "contract:c_ext_escort"}}}
MIRACLES = [
    {"id": "hana_m1", "char": "a_hana", "name": "대지의 맥박", "need": 20, "effect": "hp", "value": 10, "desc": "최대 HP +10"},
    {"id": "hana_m2", "char": "a_hana", "name": "흔들리지 않는 자", "need": 40, "effect": "defense", "value": 2, "desc": "받는 피해 -2 (방어 +2)"},
    {"id": "hana_m3", "char": "a_hana", "name": "대지모의 현신", "need": 70, "effect": "skill_power:ultimate", "value": 8, "desc": "필살기 위력 +8"},
]
FS_COLS = ["신", "id", "이름", "필요신앙", "효과", "값", "설명"]
FAITH_SKILLS = [
    ["solus", "solus_1", "햇살의 손길", 20, "heal", 2, "회복량 +2"],
    ["solus", "solus_2", "빛의 가호", 40, "hp", 6, "최대 HP +6"],
    ["solus", "solus_3", "성광", 60, "skill_power:heal", 5, "응급 처치 회복 +5"],
    ["solus", "solus_4", "태양의 축복", 80, "hp", 12, "최대 HP +12"],
    ["veyra", "veyra_1", "피의 맹세", 20, "power", 1, "모든 공격 위력 +1"],
    ["veyra", "veyra_2", "전쟁의 함성", 40, "skill_power:heavy_attack", 3, "강공격 위력 +3"],
    ["veyra", "veyra_3", "광전사", 60, "power", 2, "모든 공격 위력 +2"],
    ["veyra", "veyra_4", "신의 철퇴", 80, "skill_power:ultimate", 6, "필살기 위력 +6"],
    ["noct", "noct_1", "그림자 걸음", 20, "speed", 1, "속도 +1"],
    ["noct", "noct_2", "밤의 숨결", 40, "ap_rec", 1, "턴마다 AP 회복 +1"],
    ["noct", "noct_3", "암습", 60, "skill_power:basic_attack", 3, "기본 공격 위력 +3"],
    ["noct", "noct_4", "달 없는 밤", 80, "ap", 1, "최대 AP +1"],
    ["terra", "terra_1", "단단한 뿌리", 20, "defense", 1, "방어 +1"],
    ["terra", "terra_2", "대지의 피", 40, "hp", 8, "최대 HP +8"],
    ["terra", "terra_3", "바위 피부", 60, "defense", 1, "방어 +1"],
    ["terra", "terra_4", "어머니의 품", 80, "hp", 14, "최대 HP +14"],
]

gods = [{"id": g[0], "name": g[1], "color": g[2], "symbol": "", "desc": g[3]} for g in GODS]
skills = [{"id": f[1], "god": f[0], "name": f[2], "need": f[3], "effect": f[4], "value": f[5], "desc": f[6]} for f in FAITH_SKILLS]
with open(OUT, "w", encoding="utf-8") as f:
    f.write(json.dumps({"version": 1, "gods": gods, "believers": BELIEVERS, "divine": DIVINE, "skills": skills, "miracles": MIRACLES}, ensure_ascii=False, indent="\t"))
print(OUT, len(gods), len(skills))
