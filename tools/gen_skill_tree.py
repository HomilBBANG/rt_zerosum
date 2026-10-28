#!/usr/bin/env python3
"""스킬 트리 초기 데이터(data/skill_tree.json) 생성. 처음 한 번만 — 이후에는 Godot 에디터 '스킬 트리' 탭에서 고치는 파일이 원본.
옛 십자형(dir · tier) 형식으로 만듦 — 게임·에디터가 읽을 때 자유 모양(x, y · 선행 · 택일 그룹)으로 바뀌고, 에디터에서 저장하면 새 형식.
주의: 다시 실행하면 에디터에서 고친 노드를 덮어씀. (사용: python3 tools/gen_skill_tree.py --force)"""
import os, sys, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "skill_tree.json")
if os.path.exists(OUT) and "--force" not in sys.argv:
    sys.exit("data/skill_tree.json 이 이미 있습니다 (에디터에서 고친 노드가 사라지므로 덮어쓰려면 --force)")

# 스킬 트리: 캐릭터마다 액티브 · 패시브 두 개의 십자형 트리 (중앙 + 동서남북 1~3단계). 방향 = 빌드 성향 (북 화력 / 동 기동 / 남 생존 / 서 전술)
# 액티브 = 전투에서 쓰는 스킬을 새로 얻거나 강화, 패시브 = 늘 적용되는 능력치. 스킬 포인트는 두 트리가 같이 씀 [임시 데이터]
TREE_COLS = ["캐릭터", "종류", "방향", "단계", "id", "이름", "필요레벨", "효과", "값", "설명"]
# (방향, 단계, id 꼬리, 이름, 효과, 값, 설명) — 새 스킬은 액티브 갈래 끝(3단계)에서만 → 트리마다 갈래 끝 하나라 새 스킬은 최대 하나
ACTIVE_STD = [
    ("중앙", 0, "core", "기본기", "skill_power:basic_attack", 1, "처음부터 습득 (기본 공격 위력 +1)"),
    ("북", 1, "n1", "강공 단련", "skill_power:heavy_attack", 2, "강공격 위력 +2"),
    ("북", 2, "n2", "강공 숙달", "skill_power:heavy_attack", 3, "강공격 위력 +3"),
    ("북", 3, "n3", "강타", "skill:brutal_strike", 1, "새 스킬: 강타 (AP 3, 위력 16)"),
    ("동", 1, "e1", "속사", "skill_power:basic_attack", 2, "기본 공격 위력 +2"),
    ("동", 2, "e2", "연사", "skill_power:basic_attack", 2, "기본 공격 위력 +2"),
    ("동", 3, "e3", "측면 기습", "skill:flank", 1, "새 스킬: 측면 기습 (AP 2, 열 무관)"),
    ("남", 1, "s1", "견제 사격", "skill_power:basic_attack", 1, "기본 공격 위력 +1"),
    ("남", 2, "s2", "반격 자세", "skill_power:heavy_attack", 2, "강공격 위력 +2"),
    ("남", 3, "s3", "재정비", "skill:second_wind", 1, "새 스킬: 재정비 (AP 1, 회복 8)"),
    ("서", 1, "w1", "필살 연마", "skill_power:ultimate", 3, "필살기 위력 +3"),
    ("서", 2, "w2", "필살 숙달", "skill_power:ultimate", 4, "필살기 위력 +4"),
    ("서", 3, "w3", "고무", "skill:inspire", 1, "새 스킬: 고무 (AP 1, 아군 AP +1)"),
]
# 의무병은 기본 스킬 칸(3칸)이 이미 차서 새 스킬 대신 강화만
ACTIVE_MEDIC = [
    ("중앙", 0, "core", "응급 처치 숙련", "skill_power:heal", 2, "처음부터 습득 (응급 처치 회복 +2)"),
    ("북", 1, "n1", "사격 연습", "skill_power:basic_attack", 2, "기본 공격 위력 +2"),
    ("북", 2, "n2", "조준 사격", "skill_power:basic_attack", 2, "기본 공격 위력 +2"),
    ("북", 3, "n3", "정밀 사격", "skill_power:basic_attack", 4, "기본 공격 위력 +4"),
    ("동", 1, "e1", "독려 숙련", "skill_power:rally", 1, "독려 AP 지급 +1"),
    ("동", 2, "e2", "격려", "skill_power:rally", 1, "독려 AP 지급 +1"),
    ("동", 3, "e3", "독려 달인", "skill_power:rally", 1, "독려 AP 지급 +1"),
    ("남", 1, "s1", "지혈", "skill_power:heal", 3, "응급 처치 회복 +3"),
    ("남", 2, "s2", "봉합", "skill_power:heal", 4, "응급 처치 회복 +4"),
    ("남", 3, "s3", "외과 처치", "skill_power:heal", 6, "응급 처치 회복 +6"),
    ("서", 1, "w1", "필살 연마", "skill_power:ultimate", 3, "필살기 위력 +3"),
    ("서", 2, "w2", "필살 숙달", "skill_power:ultimate", 4, "필살기 위력 +4"),
    ("서", 3, "w3", "결정타", "skill_power:ultimate", 6, "필살기 위력 +6"),
]
PASSIVE_STD = [
    ("중앙", 0, "core", "기초 훈련", "hp", 4, "처음부터 습득 (최대 HP +4)"),
    ("북", 1, "n1", "무기 숙련", "power", 1, "모든 공격 위력 +1"),
    ("북", 2, "n2", "전투 감각", "power", 1, "모든 공격 위력 +1"),
    ("북", 3, "n3", "전투의 달인", "power", 2, "모든 공격 위력 +2"),
    ("동", 1, "e1", "빠른 발", "speed", 1, "속도 +1 (행동 순서가 빨라짐)"),
    ("동", 2, "e2", "전술 호흡", "ap_rec", 1, "턴마다 AP 회복 +1"),
    ("동", 3, "e3", "기민함", "speed", 2, "속도 +2"),
    ("남", 1, "s1", "단련된 몸", "hp", 6, "최대 HP +6"),
    ("남", 2, "s2", "방탄 조끼", "defense", 1, "받는 피해 -1 (방어 +1)"),
    ("남", 3, "s3", "강인함", "hp", 12, "최대 HP +12"),
    ("서", 1, "w1", "여유 체력", "ap", 1, "최대 AP +1"),
    ("서", 2, "w2", "응급 교육", "heal", 2, "모든 회복량 +2"),
    ("서", 3, "w3", "전술 숙달", "ap", 1, "최대 AP +1"),
]
TREE = []
for _cid, _short, _lv in [("a_dan", "dan", 5), ("a_kira", "kira", 5), ("a_ethan", "ethan", 5), ("a_hana", "hana", 5), ("a_alma", "alma", 4), ("a_nikita", "nikita", 6)]:
    for _kind, _tag, _rows in [("액티브", "a", ACTIVE_MEDIC if _cid == "a_alma" else ACTIVE_STD), ("패시브", "p", PASSIVE_STD)]:
        for _d, _t, _id, _nm, _ef, _v, _desc in _rows:
            TREE.append([_cid, _kind, _d, _t, "%s_%s_%s" % (_short, _tag, _id), _nm, _lv + {0: 0, 1: 0, 2: 2, 3: 4}[_t], _ef, _v, _desc])

DIRS = {"중앙": "center", "북": "n", "동": "e", "남": "s", "서": "w"}
KINDS = {"액티브": "active", "패시브": "passive"}
nodes = [{"id": r[4], "char": r[0], "kind": KINDS[r[1]], "dir": DIRS[r[2]], "tier": r[3], "name": r[5], "level": r[6],
          "effect": r[7], "value": r[8], "desc": r[9]} for r in TREE]
with open(OUT, "w", encoding="utf-8") as f:
    f.write(json.dumps({"version": 1, "nodes": nodes}, ensure_ascii=False, indent="\t"))
print(OUT, len(nodes))
