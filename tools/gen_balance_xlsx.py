#!/usr/bin/env python3
"""밸런스 엑셀(data/balance.xlsx) 초기 생성. 처음 한 번만 — 이후에는 엑셀에서 직접 고치는 파일이 원본.
주의: 다시 실행하면 엑셀에서 고친 값을 덮어씀. (사용: python3 tools/gen_balance_xlsx.py --force)"""
import os, sys
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "balance.xlsx")
if os.path.exists(OUT) and "--force" not in sys.argv:
    sys.exit("data/balance.xlsx 가 이미 있습니다 (엑셀에서 고친 값이 사라지므로 덮어쓰려면 --force)")

CHAR_COLS = ["id", "이름", "병과", "레벨", "속도", "사거리", "HP", "AP", "AP회복", "방어", "스킬", "무기", "열", "줄", "키(cm)", "스프라이트", "눈색", "원화방향"]
CHARS = [
    ["a_dan", "단", "돌격병", 5, 8, "근접", 46, 6, 2, 2, "basic_attack, heavy_attack, ultimate", "axe, pistol", "전방", 1, 185, "dan", "#7fb2ff", "오른쪽"],
    ["a_kira", "키라", "돌격병", 5, 10, "근접", 40, 6, 2, 1, "basic_attack, heavy_attack, ultimate", "combat_knife, pistol", "전방", 2, 175, "kira", "#c8d4ff", "오른쪽"],
    ["a_ethan", "이선", "소총수", 5, 9, "원거리", 30, 6, 2, 0, "basic_attack, heavy_attack, ultimate", "rifle, bayonet", "중앙", 1, 178, "ethan", "", "오른쪽"],
    ["a_hana", "하나", "돌격소총수", 5, 9, "원거리", 34, 6, 2, 1, "basic_attack, heavy_attack, ultimate", "rifle, bayonet", "중앙", 2, 176.8, "hero2", "#ffb020", "오른쪽"],
    ["a_alma", "앨마", "의무병", 4, 7, "원거리", 28, 7, 3, 0, "basic_attack, heal, rally, ultimate", "pistol, syringe", "후방", 1, 166, "alma", "#43d6a0", "오른쪽"],
    ["a_nikita", "니키타", "저격수", 6, 11, "원거리", 24, 5, 2, 0, "basic_attack, heavy_attack, ultimate", "sniper, knife", "후방", 2, 168, "nikita_army", "#4f9cff", "오른쪽"],
]
MON_COLS = ["id", "이름", "분류", "레벨", "속도", "사거리", "HP", "AP", "AP회복", "방어", "스킬", "무기", "차지칸", "키(cm)", "스프라이트", "원화방향", "AI"]
MONS = [
    ["ghoul", "구울", "괴물", 6, 10, "근접", 110, 6, 2, 2, "basic_attack, heavy_attack, ultimate", "claw", 2, 240, "ghoul", "왼쪽", "default"],
    ["wolf", "늑대", "괴물", 7, 12, "근접", 90, 6, 2, 1, "basic_attack, heavy_attack, ultimate", "claw", 1, 400, "wolf", "오른쪽", "aggressive"],
    ["slime", "슬라임", "괴물", 4, 5, "근접", 130, 5, 2, 3, "basic_attack, heavy_attack", "slam", 2, 400, "slime", "오른쪽", "default"],
]
ITEM_COLS = ["id", "이름", "종류", "사거리", "위력보너스", "스프라이트", "설명"]
ITEMS = [
    ["combat_knife", "전투단검", "무기", "근접", 2, "knife", ""],
    ["knife", "단검", "무기", "근접", 0, "knife", ""],
    ["pistol", "권총", "무기", "원거리", 0, "pistol", ""],
    ["sniper", "저격총", "무기", "원거리", 3, "sniper", ""],
    ["rifle", "소총", "무기", "원거리", 1, "rifle", ""],
    ["bayonet", "대검", "무기", "근접", 2, "bayonet", ""],
    ["axe", "전투도끼", "무기", "근접", 2, "axe", ""],
    ["syringe", "전투 주사기", "무기", "근접", 1, "syringe", ""],
    ["claw", "발톱", "무기", "근접", 3, "", "괴물 전용"],
    ["slam", "덮치기", "무기", "근접", 2, "", "괴물 전용"],
    ["shotgun", "산탄총", "무기", "원거리", 2, "shotgun", "연구로 해금 (더미 수치)"],
    ["smg", "기관단총", "무기", "원거리", 1, "smg", "연구로 해금 (더미 수치)"],
    ["blade", "고주파 블레이드", "무기", "근접", 4, "blade", "연구로 해금 (더미 수치)"],
    ["mg", "경기관총", "무기", "원거리", 3, "mg", "연구로 해금 (더미 수치)"],
    ["launcher", "유탄발사기", "무기", "원거리", 4, "launcher", "연구로 해금 (더미 수치)"],
]
SKILL_COLS = ["id", "이름", "종류", "AP비용", "대상", "효과", "위력", "설명"]
SKILLS = [
    ["basic_attack", "기본 공격", "attack", 1, "weapon", "damage", 6, "현재 무기로 공격. 근접: 상대 앞열 우선 / 원거리: 전열 무관"],
    ["heavy_attack", "강공격", "heavy", 2, "weapon", "damage", 11, "현재 무기로 강하게 공격"],
    ["heal", "응급 처치", "support", 2, "ally_any", "heal", 10, "아군 1명 HP 회복"],
    ["rally", "독려", "support", 2, "ally_other", "ap_grant", 2, "다른 아군 1명 AP +2 (상한까지)"],
    ["ultimate", "필살기", "ultimate", 4, "enemy_any", "damage", 18, "열 무관 강력한 일격"],
    ["move", "위치 변경", "move", 1, "slot", "move", 0, "빈 슬롯 이동 / 점유 슬롯 아군과 교환"],
    ["weapon", "무기 변경", "weapon", 1, "none", "weapon_swap", 0, "보조 무기로 교체 (사거리 변경)"],
    ["brutal_strike", "강타", "heavy", 3, "weapon", "damage", 16, "스킬 트리(북·화력 끝): 현재 무기로 아주 강하게 공격"],
    ["flank", "측면 기습", "attack", 2, "enemy_any", "damage", 9, "스킬 트리(동·기동 끝): 열 무관 적 1명 공격"],
    ["second_wind", "재정비", "support", 1, "ally_any", "heal", 8, "스킬 트리(남·생존 끝): 아군 1명(자신 포함) HP 회복"],
    ["inspire", "고무", "support", 1, "ally_other", "ap_grant", 1, "스킬 트리(서·전술 끝): 다른 아군 1명 AP +1"],
]
# 스킬 트리 (캐릭터마다 십자형: 중앙 + 동서남북 1~3단계). 방향 = 빌드 성향 (북 화력 / 동 기동 / 남 생존 / 서 전술)
TREE_COLS = ["캐릭터", "방향", "단계", "id", "이름", "필요레벨", "효과", "값", "설명"]
TREE = [
    ["a_dan", "중앙", 0, "dan_core", "기초 훈련", 5, "hp", 4, "처음부터 습득 (최대 HP +4)"],
    ["a_dan", "북", 1, "dan_n1", "무기 숙련", 5, "power", 1, "모든 공격 위력 +1"],
    ["a_dan", "북", 2, "dan_n2", "강공 단련", 7, "skill_power:heavy_attack", 3, "강공격 위력 +3"],
    ["a_dan", "북", 3, "dan_n3", "강타", 9, "skill:brutal_strike", 1, "새 스킬: 강타 (AP 3, 위력 16)"],
    ["a_dan", "동", 1, "dan_e1", "빠른 발", 5, "speed", 1, "속도 +1 (행동 순서가 빨라짐)"],
    ["a_dan", "동", 2, "dan_e2", "전술 호흡", 7, "ap_rec", 1, "턴마다 AP 회복 +1"],
    ["a_dan", "동", 3, "dan_e3", "측면 기습", 9, "skill:flank", 1, "새 스킬: 측면 기습 (AP 2, 열 무관)"],
    ["a_dan", "남", 1, "dan_s1", "단련된 몸", 5, "hp", 6, "최대 HP +6"],
    ["a_dan", "남", 2, "dan_s2", "방탄 조끼", 7, "defense", 1, "받는 피해 -1 (방어 +1)"],
    ["a_dan", "남", 3, "dan_s3", "재정비", 9, "skill:second_wind", 1, "새 스킬: 재정비 (AP 1, 회복 8)"],
    ["a_dan", "서", 1, "dan_w1", "여유 체력", 5, "ap", 1, "최대 AP +1"],
    ["a_dan", "서", 2, "dan_w2", "필살 연마", 7, "skill_power:ultimate", 4, "필살기 위력 +4"],
    ["a_dan", "서", 3, "dan_w3", "고무", 9, "skill:inspire", 1, "새 스킬: 고무 (AP 1, 아군 AP +1)"],
    ["a_kira", "중앙", 0, "kira_core", "기초 훈련", 5, "hp", 4, "처음부터 습득 (최대 HP +4)"],
    ["a_kira", "북", 1, "kira_n1", "무기 숙련", 5, "power", 1, "모든 공격 위력 +1"],
    ["a_kira", "북", 2, "kira_n2", "강공 단련", 7, "skill_power:heavy_attack", 3, "강공격 위력 +3"],
    ["a_kira", "북", 3, "kira_n3", "강타", 9, "skill:brutal_strike", 1, "새 스킬: 강타 (AP 3, 위력 16)"],
    ["a_kira", "동", 1, "kira_e1", "빠른 발", 5, "speed", 1, "속도 +1 (행동 순서가 빨라짐)"],
    ["a_kira", "동", 2, "kira_e2", "전술 호흡", 7, "ap_rec", 1, "턴마다 AP 회복 +1"],
    ["a_kira", "동", 3, "kira_e3", "측면 기습", 9, "skill:flank", 1, "새 스킬: 측면 기습 (AP 2, 열 무관)"],
    ["a_kira", "남", 1, "kira_s1", "단련된 몸", 5, "hp", 6, "최대 HP +6"],
    ["a_kira", "남", 2, "kira_s2", "방탄 조끼", 7, "defense", 1, "받는 피해 -1 (방어 +1)"],
    ["a_kira", "남", 3, "kira_s3", "재정비", 9, "skill:second_wind", 1, "새 스킬: 재정비 (AP 1, 회복 8)"],
    ["a_kira", "서", 1, "kira_w1", "여유 체력", 5, "ap", 1, "최대 AP +1"],
    ["a_kira", "서", 2, "kira_w2", "필살 연마", 7, "skill_power:ultimate", 4, "필살기 위력 +4"],
    ["a_kira", "서", 3, "kira_w3", "고무", 9, "skill:inspire", 1, "새 스킬: 고무 (AP 1, 아군 AP +1)"],
    ["a_ethan", "중앙", 0, "ethan_core", "기초 훈련", 5, "hp", 4, "처음부터 습득 (최대 HP +4)"],
    ["a_ethan", "북", 1, "ethan_n1", "무기 숙련", 5, "power", 1, "모든 공격 위력 +1"],
    ["a_ethan", "북", 2, "ethan_n2", "강공 단련", 7, "skill_power:heavy_attack", 3, "강공격 위력 +3"],
    ["a_ethan", "북", 3, "ethan_n3", "강타", 9, "skill:brutal_strike", 1, "새 스킬: 강타 (AP 3, 위력 16)"],
    ["a_ethan", "동", 1, "ethan_e1", "빠른 발", 5, "speed", 1, "속도 +1 (행동 순서가 빨라짐)"],
    ["a_ethan", "동", 2, "ethan_e2", "전술 호흡", 7, "ap_rec", 1, "턴마다 AP 회복 +1"],
    ["a_ethan", "동", 3, "ethan_e3", "측면 기습", 9, "skill:flank", 1, "새 스킬: 측면 기습 (AP 2, 열 무관)"],
    ["a_ethan", "남", 1, "ethan_s1", "단련된 몸", 5, "hp", 6, "최대 HP +6"],
    ["a_ethan", "남", 2, "ethan_s2", "방탄 조끼", 7, "defense", 1, "받는 피해 -1 (방어 +1)"],
    ["a_ethan", "남", 3, "ethan_s3", "재정비", 9, "skill:second_wind", 1, "새 스킬: 재정비 (AP 1, 회복 8)"],
    ["a_ethan", "서", 1, "ethan_w1", "여유 체력", 5, "ap", 1, "최대 AP +1"],
    ["a_ethan", "서", 2, "ethan_w2", "필살 연마", 7, "skill_power:ultimate", 4, "필살기 위력 +4"],
    ["a_ethan", "서", 3, "ethan_w3", "고무", 9, "skill:inspire", 1, "새 스킬: 고무 (AP 1, 아군 AP +1)"],
    ["a_hana", "중앙", 0, "hana_core", "기초 훈련", 5, "hp", 4, "처음부터 습득 (최대 HP +4)"],
    ["a_hana", "북", 1, "hana_n1", "무기 숙련", 5, "power", 1, "모든 공격 위력 +1"],
    ["a_hana", "북", 2, "hana_n2", "강공 단련", 7, "skill_power:heavy_attack", 3, "강공격 위력 +3"],
    ["a_hana", "북", 3, "hana_n3", "강타", 9, "skill:brutal_strike", 1, "새 스킬: 강타 (AP 3, 위력 16)"],
    ["a_hana", "동", 1, "hana_e1", "빠른 발", 5, "speed", 1, "속도 +1 (행동 순서가 빨라짐)"],
    ["a_hana", "동", 2, "hana_e2", "전술 호흡", 7, "ap_rec", 1, "턴마다 AP 회복 +1"],
    ["a_hana", "동", 3, "hana_e3", "측면 기습", 9, "skill:flank", 1, "새 스킬: 측면 기습 (AP 2, 열 무관)"],
    ["a_hana", "남", 1, "hana_s1", "단련된 몸", 5, "hp", 6, "최대 HP +6"],
    ["a_hana", "남", 2, "hana_s2", "방탄 조끼", 7, "defense", 1, "받는 피해 -1 (방어 +1)"],
    ["a_hana", "남", 3, "hana_s3", "재정비", 9, "skill:second_wind", 1, "새 스킬: 재정비 (AP 1, 회복 8)"],
    ["a_hana", "서", 1, "hana_w1", "여유 체력", 5, "ap", 1, "최대 AP +1"],
    ["a_hana", "서", 2, "hana_w2", "필살 연마", 7, "skill_power:ultimate", 4, "필살기 위력 +4"],
    ["a_hana", "서", 3, "hana_w3", "고무", 9, "skill:inspire", 1, "새 스킬: 고무 (AP 1, 아군 AP +1)"],
    ["a_alma", "중앙", 0, "alma_core", "기초 훈련", 4, "hp", 4, "처음부터 습득 (최대 HP +4)"],
    ["a_alma", "북", 1, "alma_n1", "무기 숙련", 4, "power", 1, "모든 공격 위력 +1"],
    ["a_alma", "북", 2, "alma_n2", "사격 연습", 6, "skill_power:basic_attack", 2, "기본 공격 위력 +2"],
    ["a_alma", "북", 3, "alma_n3", "명사수", 8, "power", 3, "모든 공격 위력 +3"],
    ["a_alma", "동", 1, "alma_e1", "빠른 발", 4, "speed", 1, "속도 +1 (행동 순서가 빨라짐)"],
    ["a_alma", "동", 2, "alma_e2", "전술 호흡", 6, "ap_rec", 1, "턴마다 AP 회복 +1"],
    ["a_alma", "동", 3, "alma_e3", "기민함", 8, "speed", 2, "속도 +2"],
    ["a_alma", "남", 1, "alma_s1", "단련된 몸", 4, "hp", 6, "최대 HP +6"],
    ["a_alma", "남", 2, "alma_s2", "방탄 조끼", 6, "defense", 1, "받는 피해 -1 (방어 +1)"],
    ["a_alma", "남", 3, "alma_s3", "강인함", 8, "hp", 12, "최대 HP +12"],
    ["a_alma", "서", 1, "alma_w1", "여유 체력", 4, "ap", 1, "최대 AP +1"],
    ["a_alma", "서", 2, "alma_w2", "독려 숙련", 6, "skill_power:rally", 1, "독려 AP 지급 +1"],
    ["a_alma", "서", 3, "alma_w3", "응급 처치 숙련", 8, "skill_power:heal", 6, "응급 처치 회복 +6"],
    ["a_nikita", "중앙", 0, "nikita_core", "기초 훈련", 6, "hp", 4, "처음부터 습득 (최대 HP +4)"],
    ["a_nikita", "북", 1, "nikita_n1", "무기 숙련", 6, "power", 1, "모든 공격 위력 +1"],
    ["a_nikita", "북", 2, "nikita_n2", "강공 단련", 8, "skill_power:heavy_attack", 3, "강공격 위력 +3"],
    ["a_nikita", "북", 3, "nikita_n3", "강타", 10, "skill:brutal_strike", 1, "새 스킬: 강타 (AP 3, 위력 16)"],
    ["a_nikita", "동", 1, "nikita_e1", "빠른 발", 6, "speed", 1, "속도 +1 (행동 순서가 빨라짐)"],
    ["a_nikita", "동", 2, "nikita_e2", "전술 호흡", 8, "ap_rec", 1, "턴마다 AP 회복 +1"],
    ["a_nikita", "동", 3, "nikita_e3", "측면 기습", 10, "skill:flank", 1, "새 스킬: 측면 기습 (AP 2, 열 무관)"],
    ["a_nikita", "남", 1, "nikita_s1", "단련된 몸", 6, "hp", 6, "최대 HP +6"],
    ["a_nikita", "남", 2, "nikita_s2", "방탄 조끼", 8, "defense", 1, "받는 피해 -1 (방어 +1)"],
    ["a_nikita", "남", 3, "nikita_s3", "재정비", 10, "skill:second_wind", 1, "새 스킬: 재정비 (AP 1, 회복 8)"],
    ["a_nikita", "서", 1, "nikita_w1", "여유 체력", 6, "ap", 1, "최대 AP +1"],
    ["a_nikita", "서", 2, "nikita_w2", "필살 연마", 8, "skill_power:ultimate", 4, "필살기 위력 +4"],
    ["a_nikita", "서", 3, "nikita_w3", "고무", 10, "skill:inspire", 1, "새 스킬: 고무 (AP 1, 아군 AP +1)"],
]
STAGE_COLS = ["id", "이름", "조명", "선공", "적HP배율", "적공격배율", "시드", "설명"]
STAGES = [
    ["stage_01", "첫 조우", "g1", "동전", 1.0, 1.0, 12345, "구울(전방·중앙) + 늑대(후방). 배치는 스테이지 에디터"],
]
README = [
    ["시트", "열", "설명"],
    ["스킬트리", "캐릭터 / 방향 / 단계", "캐릭터마다 십자형 트리: 중앙(0단계, 처음부터 습득) + 동서남북 갈래 1~3단계. 갈래 안에서는 앞 단계를 배워야 다음 단계"],
    ["스킬트리", "필요레벨", "이 레벨이 되어야 배울 수 있음 (안 되면 스킬 창에 회색 + '경험 부족'). 스킬 포인트 = 레벨 오를 때마다 1 + 처음 1"],
    ["스킬트리", "효과 / 값", "hp·speed·ap·ap_rec·defense·power(모든 공격 위력)·heal(회복량) +값, skill_power:<스킬 id> = 그 스킬 위력 +값, skill:<스킬 id> = 새 스킬 (기본 스킬 칸 3개까지)"],
    ["스킬트리", "갈래 끝", "3단계(갈래 끝)는 한 캐릭터에 하나만 — 어느 방향으로 뻗을지가 빌드 [임시]"],
    ["공통", "id", "다른 시트·파일에서 참조하는 고유 이름 (영문 권장, 바꾸면 참조도 같이 바꿀 것)"],
    ["캐릭터", "사거리", "근접 / 원거리 — 행동 순서 동률 정렬용 병과 기본 사거리"],
    ["캐릭터", "스킬 / 무기", "쉼표로 구분한 스킬 id / 아이템 id. 무기 첫 번째 = 주무기, 두세 번째 = 보조무기"],
    ["캐릭터", "열 / 줄", "기본 배치: 열 = 전방·중앙·후방, 줄 = 1(뒤쪽 줄)·2(카메라 쪽 줄)"],
    ["캐릭터", "눈색", "눈동자를 일부러 칠할 색(#RRGGBB). 비우면 원화 눈 색 그대로"],
    ["캐릭터·몬스터", "원화방향", "원화가 바라보는 쪽 (오른쪽 / 왼쪽) — 화면에서 상대를 보게 자동 반전"],
    ["몬스터", "차지칸", "1 = 한 칸, 2 = 전방+중앙처럼 연속 두 열 (이동·교환 불가)"],
    ["몬스터", "AI", "data/ai/<AI>.json — 메뉴 → AI 에디터에서 만들고 고침"],
    ["아이템", "스프라이트", "assets/sprites/w_<스프라이트>.png (비우면 손에 든 무기 그림 없음)"],
    ["스킬", "종류", "attack / heavy / support / ultimate / move / weapon (ultimate = 필살기 칸)"],
    ["스킬", "대상", "weapon(무기 사거리) / enemy_any / ally_any / ally_other / self / slot / none"],
    ["스킬", "효과", "damage(피해) / heal(회복) / ap_grant(AP 부여) / move / weapon_swap"],
    ["스테이지", "조명 / 선공", "조명 g1~g4, 선공 동전 / 기습(아군 선공) / 매복(적 선공)"],
    ["스테이지", "적HP배율 / 적공격배율", "이 스테이지의 적 최대 HP·피해에 곱함 (1 = 그대로)"],
    ["스테이지", "배치", "적 배치는 data/stages/<id>.json — 메뉴 → 스테이지 에디터"],
    ["반영", "", "게임 실행 중 이 파일을 저장하면 1초 안에 다시 읽어 바로 적용 (현재 전투 수치 포함). 편성·배치 변경은 다음 전투부터"],
]

HEAD_FILL = PatternFill("solid", fgColor="2E3440")
wb = Workbook()
first = True
for name, cols, rows, widths in [
    ("캐릭터", CHAR_COLS, CHARS, None), ("몬스터", MON_COLS, MONS, None), ("아이템", ITEM_COLS, ITEMS, None),
    ("스킬", SKILL_COLS, SKILLS, None), ("스킬트리", TREE_COLS, TREE, None), ("스테이지", STAGE_COLS, STAGES, None), ("읽어보기", README[0], README[1:], [12, 22, 90])]:
    ws = wb.active if first else wb.create_sheet()
    first = False
    ws.title = name
    ws.append(cols)
    for r in rows:
        ws.append(r)
    for c in ws[1]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = HEAD_FILL
        c.alignment = Alignment(horizontal="center")
    ws.freeze_panes = "B2" if name != "읽어보기" else "A2"
    for i, col in enumerate(cols):
        letter = ws.cell(row=1, column=i + 1).column_letter
        w = widths[i] if widths else max(8, min(40, max(len(str(col)) * 2 + 2, *[len(str(r[i])) + 2 for r in rows if i < len(r)])))
        ws.column_dimensions[letter].width = w
    # 선택지 칸은 목록으로
    def pick(colname, opts):
        if colname in cols:
            letter = ws.cell(row=1, column=cols.index(colname) + 1).column_letter
            dv = DataValidation(type="list", formula1='"%s"' % ",".join(opts), allow_blank=True)
            dv.add(f"{letter}2:{letter}200")
            ws.add_data_validation(dv)
    pick("사거리", ["근접", "원거리"])
    pick("열", ["전방", "중앙", "후방"])
    pick("원화방향", ["오른쪽", "왼쪽"])
    pick("조명", ["g1", "g2", "g3", "g4"])
    pick("선공", ["동전", "기습", "매복"])
    if name == "스킬":
        pick("종류", ["attack", "heavy", "support", "ultimate", "move", "weapon"])
        pick("효과", ["damage", "heal", "ap_grant", "move", "weapon_swap"])
os.makedirs(os.path.dirname(OUT), exist_ok=True)
wb.save(OUT)
print("saved", OUT)
