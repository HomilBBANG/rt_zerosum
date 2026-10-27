#!/usr/bin/env python3
"""아웃게임(기지) 데이터 엑셀(data/outgame.xlsx)과 대원 주간 일정(data/outgame/schedules/*.json) 초기 생성.
처음 한 번만 — 이후에는 엑셀·Godot 에디터 '일정' 탭에서 고친 파일이 원본.
주의: 다시 실행하면 고친 값을 덮어씀. (사용: python3 tools/gen_outgame_xlsx.py --force)
모든 값은 01_OUTGAME_GDD / 03_IMPLEMENTATION_HANDOFF 의 '프로토타입 임시값·더미'다 (시설 이름·대사·일정 포함)."""
import json, os, sys
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "outgame.xlsx")
SCHED_DIR = os.path.join(ROOT, "data", "outgame", "schedules")
if os.path.exists(OUT) and "--force" not in sys.argv:
    sys.exit("data/outgame.xlsx 가 이미 있습니다 (고친 값이 사라지므로 덮어쓰려면 --force)")

SETTINGS = [
    ["id", "값", "설명"],
    ["start_date", "2048-04-07", "시작 날짜 [확정]"],
    ["start_time", "08:00", "시작 시각 [임시]"],
    ["minutes_per_second", 1, "현실 1초 = 게임 N분 (기본 1, HUD 배속 버튼은 이 값에 곱함) [임시]"],
    ["start_cash", 150, "시작 달러 [임시]"],
    ["weekly_subsidy", 100, "주간 행정 지원금 USD [임시]"],
    ["week_days", 7, "결산 주기(일). 시작 날짜부터 N일마다 결산 [임시]"],
    ["initial_cleanliness", 90, "시설 초기 청결도 0~100 [임시]"],
    ["dirt_min", 1, "하루 오염 발생 최소 횟수 [임시]"],
    ["dirt_max", 2, "하루 오염 발생 최대 횟수 [임시]"],
    ["dirt_amount", 20, "오염 1회당 청결도 감소 [임시]"],
    ["clean_minutes", 20, "청소에 걸리는 게임 분 [임시]"],
    ["inspect_good_score", 80, "점검: 이 점수 이상이면 '만족' [임시]"],
    ["inspect_good_bonus", 60, "점검 '만족' 보너스 USD [임시]"],
    ["inspect_ok_score", 50, "점검: 이 점수 이상이면 '보통' [임시]"],
    ["inspect_ok_bonus", 30, "점검 '보통' 보너스 USD [임시]"],
    ["inspect_bad_bonus", 0, "점검 '불만' 보너스 USD [임시]"],
    ["train_minutes", 120, "훈련 1회 게임 분 [임시]"],
    ["train_hp_bonus", 5, "훈련 단계당 전투 최대 HP + (더미 성장) [임시]"],
    ["enhance_minutes", 60, "무기 강화 1회 게임 분 [임시]"],
    ["enhance_power_bonus", 1, "강화 단계당 무기 위력 + (더미) [임시]"],
    ["enhance_max", 5, "강화 최대 단계 [임시]"],
    ["chat_minutes", 30, "대원끼리 대화 지속 게임 분 [임시]"],
    ["chat_cooldown", 180, "대원이 다시 대화를 시작하기까지 게임 분 [임시]"],
    ["walk_speed", 90, "대원 걷는 속도: 게임 1분당 px (방 한 칸 = 240px) [임시]"],
    ["run_speed_mult", 2.2, "더블클릭으로 보낸 대원이 뛰는 속도 = 걷기 × [임시]"],
    ["fatigue_run_per_hour", 12, "뛰는 동안 시간당 피로 증가 [임시]"],
    ["seed", 2048, "오염·점검 날짜 난수 시드 [임시]"],
    ["fatigue_start", 20, "시작 피로도 0~100 (높을수록 피곤) [임시]"],
    ["fatigue_awake_per_hour", 2, "깨어 있을 때 시간당 피로 증가 [임시]"],
    ["fatigue_work_per_hour", 4, "업무·청소·지시 중 시간당 피로 증가 [임시]"],
    ["fatigue_train_per_hour", 7, "훈련 중 시간당 피로 증가 [임시]"],
    ["fatigue_battle", 20, "전투 한 번 참가 시 피로 증가 [임시]"],
    ["hungry_fatigue", 6, "식사 시간에 식재료가 없으면 피로 증가 [임시]"],
    ["food_start", 10, "시작 식재료 (1 = 한 끼) [임시]"],
    ["food_pack_price", 20, "식재료 한 묶음 가격 USD [임시]"],
    ["food_pack_amount", 12, "식재료 한 묶음 = N 끼 [임시]"],
    ["treat_minutes", 60, "의무실 치료(상태 이상 제거)에 걸리는 게임 분 [임시]"],
    ["affinity_start", 20, "시작 친밀도 0~100 [임시]"],
    ["affinity_talk", 1, "하루 첫 직접 대화 시 친밀도 + [임시]"],
    ["affinity_request", 5, "요청 수락 시 그 대원 친밀도 + [임시]"],
    ["xp_win", 100, "전투 승리 시 출전 대원 경험치 [임시]"],
    ["xp_lose", 40, "전투 패배 시 출전 대원 경험치 [임시]"],
    ["xp_level_base", 100, "다음 레벨까지 필요 경험치 = base + step × (지금 레벨 - 시작 레벨) [임시]"],
    ["xp_level_step", 50, "(위 공식의 step) [임시]"],
    ["level_max", 20, "최대 레벨 [임시]"],
    ["faith_battle", 5, "전투에 출전할 때마다 신앙도 + [임시]"],
    ["researcher_npc", "npc_rohan", "연구원 대원 id — 클릭하면 연구 창, 이 대원이 연구실(기능=연구)에서 깨어 있을 때만 연구가 진행됨 [임시]"],
]

FLOORS = [
    ["id", "이름", "순서", "설명"],
    ["f1", "지상 1층", 0, "기본 개방 [확정]"],
    ["b1", "지하 1층", 1, "기본 개방 [확정]"],
    ["b2", "지하 2층(임시)", 2, "세 번째 층. 번호·개방 방식 미정 → 프로토타입은 잠금 구역 [임시]"],
]

# 시설: 이름·기능은 더미 태그 (4.4 시설 종류 미정)
FAC = [
    ["id", "이름", "층", "칸", "폭", "해금비용", "초기해금", "기능", "청소", "조명", "설명"],
    ["f1_gate", "정문", "f1", 0, 1, 0, "O", "출입", "X", "g3", "외부 의뢰 출발·복귀 지점"],
    ["f1_stair_w", "서쪽 계단", "f1", 1, 1, 0, "O", "계단", "X", "g1", ""],
    ["f1_office", "행정실", "f1", 2, 2, 0, "O", "행정", "O", "g3", "외부 의뢰 게시판 (더미 이름)"],
    ["f1_lounge", "공용실", "f1", 4, 2, 0, "O", "공용", "O", "g1", "청소 가능한 공용 구역 (더미)"],
    ["f1_mess", "식당", "f1", 6, 2, 50, "X", "식당", "O", "g2", "달러로 식재료 공급, 식사하면 피로 감소"],
    ["f1_px", "PX", "f1", 8, 1, 40, "X", "상점", "O", "g4", "친밀도 선물 구매"],
    ["f1_stair_e", "동쪽 계단", "f1", 9, 1, 0, "O", "계단", "X", "g1", ""],
    ["b1_stair_w", "서쪽 계단", "b1", 1, 1, 0, "O", "계단", "X", "g1", ""],
    ["b1_quarters", "숙소", "b1", 2, 2, 0, "O", "생활", "O", "g4", "침대 6 (잠자면 피로 회복)"],
    ["b1_infirmary", "의무실", "b1", 4, 2, 0, "O", "의무", "O", "g1", "치료(상태 이상 제거)·휴식(체력 회복)"],
    ["b1_workshop", "무기고", "b1", 6, 2, 0, "O", "무기고", "O", "g3", "무기 강화·제작·장착 (id 는 이전 이름 그대로)"],
    ["b1_training", "훈련실", "b1", 8, 1, 90, "X", "훈련", "O", "g2", "대원 훈련 (더미)"],
    ["b1_stair_e", "동쪽 계단", "b1", 9, 1, 0, "O", "계단", "X", "g1", ""],
    ["b1_lab", "연구실", "b1", 0, 1, 0, "O", "연구", "O", "g4", "로한이 일하는 곳 — 로한을 클릭하면 새 무기 연구 (지하 1층 서쪽 끝)"],
    ["b2_stair_w", "서쪽 계단", "b2", 1, 1, 40, "X", "계단", "X", "g1", ""],
    ["b2_storage", "창고", "b2", 2, 3, 120, "X", "공용", "O", "g4", "잠금 방 (더미)"],
    ["b2_sealed", "봉쇄 구역", "b2", 5, 4, 200, "X", "미정", "O", "g2", "잠금 방 (더미)"],
    ["b2_stair_e", "동쪽 계단", "b2", 9, 1, 40, "X", "계단", "X", "g1", ""],
]

# 오브젝트: 앉거나 누울 수 있는 가구. 잠(수면)은 오브젝트 위에서만 피로가 회복되고, 체력은 의무침대에서만 회복
OBJS = [
    ["id", "시설", "종류", "위치", "높이", "피로회복", "체력회복", "설명"],
    ["obj_bed_1", "b1_quarters", "침대", 0.17, 0.45, 12, 0, "2층 침대 아래"],
    ["obj_bed_2", "b1_quarters", "침대", 0.17, 1.55, 11, 0, "2층 침대 위"],
    ["obj_bed_3", "b1_quarters", "침대", 0.50, 0.45, 12, 0, ""],
    ["obj_bed_4", "b1_quarters", "침대", 0.50, 1.55, 11, 0, ""],
    ["obj_bed_5", "b1_quarters", "침대", 0.83, 0.45, 12, 0, ""],
    ["obj_bed_6", "b1_quarters", "침대", 0.83, 1.55, 11, 0, ""],
    ["obj_sofa_1", "f1_lounge", "소파", 0.16, 0.45, 7, 0, "공용실 소파 왼쪽"],
    ["obj_sofa_2", "f1_lounge", "소파", 0.36, 0.45, 7, 0, "공용실 소파 오른쪽"],
    ["obj_chair_o1", "f1_office", "의자", 0.24, 0.5, 3, 0, "행정실 책상 의자"],
    ["obj_chair_o2", "f1_office", "의자", 0.68, 0.5, 3, 0, ""],
    ["obj_chair_m1", "f1_mess", "의자", 0.22, 0.5, 3, 0, "식당 의자"],
    ["obj_chair_m2", "f1_mess", "의자", 0.38, 0.5, 3, 0, ""],
    ["obj_chair_m3", "f1_mess", "의자", 0.54, 0.5, 3, 0, ""],
    ["obj_medbed_1", "b1_infirmary", "의무침대", 0.20, 0.6, 10, 8, "의무실 침대 (체력 회복)"],
    ["obj_medbed_2", "b1_infirmary", "의무침대", 0.50, 0.6, 10, 8, ""],
    ["obj_medbed_3", "b1_infirmary", "의무침대", 0.80, 0.6, 10, 8, ""],
    ["obj_chair_l1", "b1_lab", "의자", 0.32, 0.5, 3, 0, "연구실 책상 의자"],
    ["obj_cot_lab", "b1_lab", "침대", 0.78, 0.45, 10, 0, "연구실 간이침대 (로한은 여기서 잠)"],
]

# PX 선물: 대원마다 좋아하는 게 다르고, 좋아하는 정도(친밀도 상승량)도 다르다. 빈 칸 = 기본, 기본보다 작으면 '별로'
PX = [
    ["id", "이름", "가격", "기본", "단", "키라", "이선", "하나", "앨마", "니키타", "설명"],
    ["gift_coffee", "캔커피", 5, 2, "", 3, 4, "", 1, 8, "니키타가 제일 좋아함 (더미)"],
    ["gift_choco", "초콜릿", 8, 3, 1, 5, "", 12, 9, "", "하나·앨마가 좋아함"],
    ["gift_gloves", "가죽 장갑", 20, 5, 16, 10, "", "", "", "", "단이 제일 좋아함"],
    ["gift_book", "문고본", 12, 4, 2, "", 13, "", 6, 6, "이선이 제일 좋아함"],
    ["gift_charm", "행운 부적", 15, 4, "", 14, "", 8, "", "", "키라가 제일 좋아함"],
    ["gift_canned", "소시지 통조림", 10, 3, 11, "", 6, "", "", 1, "단이 좋아함"],
]

# 친밀도 대화: 친밀도가 기준 이상이 되면 해금 → 대원을 클릭하면 아직 안 본 대화부터 (다 봤으면 해금된 것 중 가장 높은 단계)
AFF_NPCS = [("npc_dan", "단"), ("npc_kira", "키라"), ("npc_ethan", "이선"), ("npc_hana", "하나"), ("npc_alma", "앨마"), ("npc_nikita", "니키타"), ("npc_rohan", "로한")]
AFF_TIERS = [30, 50, 70, 90]
AFF_TEXT = {
    "npc_dan": ["요즘 기지 분위기 나쁘지 않네요.", "예전 부대 얘기, 언젠가 해 드리죠.", "지휘관님 등은 제가 지킵니다.", "…고맙습니다. 여기가 집 같아요."],
    "npc_kira": ["일정표, 지휘관님 것도 정리해 뒀어요.", "부적 같은 거 믿진 않지만… 고마워요.", "저, 사실 겁이 많아요. 비밀이에요.", "끝까지 같이 가요, 지휘관님."],
    "npc_ethan": ["무기고 정리는 제 담당이죠.", "이 책, 다 읽으면 빌려 드릴게요.", "지하 2층… 조금 더 알아봤어요.", "지휘관님이라면 믿을 수 있어요."],
    "npc_hana": ["오늘도 무사히 끝났네요.", "단 거 먹으면 기운이 나요.", "가끔은 같이 쉬어요.", "지휘관님 덕분에 버텨요."],
    "npc_alma": ["다친 데 없죠? 확인할게요.", "의무실 커튼 색, 바꿔도 될까요?", "사실 피 보는 거 아직도 무서워요.", "모두 살아서 돌아오게 할게요."],
    "npc_rohan": ["커피는 블랙. 연구원의 기본이죠.", "이 기지 발전기, 제가 몰래 손봤어요.", "사실 전에 있던 연구소는… 말하기 싫네요.", "지휘관님 무기엔 제 이름 새겨 둘게요."],
    "npc_nikita": ["관측 기록, 이상 없음.", "커피… 고마워요. 이건 진짜예요.", "별 보는 거 좋아해요. 기지 위에서.", "제 기록에 지휘관님 이름, 꼭 남길게요."],
}
AFF_TALKS = [["id", "대원", "친밀도", "대사", "설명"]]
AFF_LINES = []
for nid, nm in AFF_NPCS:
    for i, need in enumerate(AFF_TIERS):
        did = "d_aff_%s_%d" % (nid[4:], need)
        AFF_TALKS.append(["aff_%s_%d" % (nid[4:], need), nid, need, did, "더미 대사" if i == 0 and nid == "npc_dan" else ""])
        AFF_LINES.append([did, 1, nid, "[친밀도 %d 대화] %s" % (need, AFF_TEXT[nid][i])])

# 대원 = 전투 아군과 같은 인물 (character_id 로 연결). 이름·설정은 전투 프로토타입 그대로, 성격·관계는 미정
NPCS = [
    ["id", "이름", "전투캐릭터", "스프라이트", "키(cm)", "시작장소", "대사", "설명"],
    ["npc_dan", "단", "a_dan", "dan", 185, "f1_lounge", "d_talk_dan", ""],
    ["npc_kira", "키라", "a_kira", "kira", 175, "f1_office", "d_talk_kira", ""],
    ["npc_ethan", "이선", "a_ethan", "ethan", 178, "b1_workshop", "d_talk_ethan", ""],
    ["npc_hana", "하나", "a_hana", "hero2", 176.8, "f1_lounge", "d_talk_hana", ""],
    ["npc_alma", "앨마", "a_alma", "alma", 166, "b1_quarters", "d_talk_alma", ""],
    ["npc_nikita", "니키타", "a_nikita", "nikita_army", 168, "f1_office", "d_talk_nikita", ""],
    ["npc_rohan", "로한", "", "rohan", 172, "b1_lab", "d_talk_rohan", "연구원 — 전투에 나가지 않음. 클릭하면 무기 연구"],
]

JOBS = [
    ["id", "이름", "종류", "보상", "소요(분)", "장소", "반복", "처음부터", "설명"],
    ["c_task_office", "서류 정리", "작업지시", 25, 120, "f1_office", "O", "O", "기지 안 업무 (더미)"],
    ["c_task_workshop", "장비 정비", "작업지시", 30, 180, "b1_workshop", "O", "O", "무기고에서 일함 (더미)"],
    ["c_ext_supply", "보급품 운반", "외부의뢰", 40, 240, "f1_gate", "X", "O", "정문으로 나가 일정 시간 뒤 복귀. 성공률·위험 미정 → 고정 완료 (더미)"],
    ["c_ext_escort", "민간인 호위", "외부의뢰", 60, 360, "f1_gate", "X", "X", "앨마의 요청을 수락하면 열림 (더미)"],
]

LINES = [
    ["id", "순서", "화자", "내용"],
    ["d_talk_dan", 1, "npc_dan", "[테스트 대사] 지휘관님, 이상 없습니다."],
    ["d_talk_kira", 1, "npc_kira", "[테스트 대사] 오늘 일정 확인했습니다."],
    ["d_talk_ethan", 1, "npc_ethan", "[테스트 대사] 장비 점검 중입니다."],
    ["d_talk_hana", 1, "npc_hana", "[테스트 대사] 부르셨어요?"],
    ["d_talk_alma", 1, "npc_alma", "[테스트 대사] 의무실 물품은 아직 충분해요."],
    ["d_talk_nikita", 1, "npc_nikita", "[테스트 대사] 관측 기록 정리하고 있어요."],
    ["d_talk_rohan", 1, "npc_rohan", "아, 지휘관님. 마침 설계도 하나 봐 주실래요?"],
    ["d_talk_rohan", 2, "npc_rohan", "재료랑 돈만 있으면 뭐든 만들어 보죠."],
    ["d_conv_01", 1, "npc_dan", "[일반 대화 테스트] 오늘 저녁 메뉴 들었어?"],
    ["d_conv_01", 2, "npc_kira", "[일반 대화 테스트] 아니. 또 통조림이겠지."],
    ["d_conv_02", 1, "npc_hana", "[일반 대화 테스트] 훈련 끝나고 뭐 해?"],
    ["d_conv_02", 2, "npc_nikita", "[일반 대화 테스트] 장비 손질. 같이 할래?"],
    ["d_conv_story_01", 1, "npc_ethan", "[스토리 대화 테스트] 지하 2층 기록, 누가 봉인했는지 알아?"],
    ["d_conv_story_01", 2, "npc_alma", "[스토리 대화 테스트] 쉿. 지휘관님 귀에 들어가면 곤란해."],
    ["d_conv_story_01", 3, "npc_ethan", "[스토리 대화 테스트] …알았어. 이 얘긴 나중에."],
    ["d_req_01", 1, "npc_alma", "[요청 테스트] 지휘관님, 바깥에서 들어온 호위 의뢰가 있어요. 받아 주실 수 있나요?"],
    ["d_req_01_ok", 1, "npc_alma", "[요청 테스트] 감사합니다. 의뢰 게시판에 올려 둘게요."],
    ["d_req_02", 1, "npc_ethan", "[요청 테스트] 작업실 공구가 모자랍니다. 확인만 해 주세요."],
    ["d_req_02_ok", 1, "npc_ethan", "[요청 테스트] 확인 감사합니다."],
]

CONVS = [
    ["id", "대원1", "대원2", "장소", "대사", "스토리", "최대횟수", "우선순위", "시작일", "설명"],
    ["conv_01", "npc_dan", "npc_kira", "", "d_conv_01", "", 3, 1, "", "일반 대화 (엿듣기 검증용 더미)"],
    ["conv_02", "npc_hana", "npc_nikita", "", "d_conv_02", "", 3, 1, "", "일반 대화 (더미)"],
    ["conv_story_01", "npc_ethan", "npc_alma", "", "d_conv_story_01", "story_test_01", 1, 5, "", "스토리 관련 대화 검증용 더미 (6.3절)"],
]

REQS = [
    ["id", "대원", "시작일", "대사", "수락대사", "수락효과", "설명"],
    ["req_01", "npc_alma", "2048-04-07", "d_req_01", "d_req_01_ok", "의뢰:c_ext_escort", "수락하면 외부 의뢰 '민간인 호위'가 열림 (더미)"],
    ["req_02", "npc_ethan", "2048-04-09", "d_req_02", "d_req_02_ok", "", "보상 없는 확인 요청 (더미)"],
]

RECIPES = [
    ["id", "이름", "결과무기", "소요(분)", "설명"],
    ["r_knife", "단검 제작", "knife", 120, "레시피·재료 미정 → 시간만 (더미)"],
    ["r_pistol", "권총 제작", "pistol", 180, ""],
    ["r_rifle", "소총 제작", "rifle", 240, ""],
    ["r_axe", "전투도끼 제작", "axe", 240, ""],
    ["r_shotgun", "산탄총 제작", "shotgun", 240, "연구: 산탄총 설계"],
    ["r_smg", "기관단총 제작", "smg", 240, "연구: 기관단총 설계"],
    ["r_blade", "고주파 블레이드 제작", "blade", 300, "연구: 고주파 블레이드"],
    ["r_mg", "경기관총 제작", "mg", 360, "연구: 경기관총 (기관단총 다음)"],
    ["r_launcher", "유탄발사기 제작", "launcher", 420, "연구: 유탄발사기 (산탄총 다음)"],
]

# 연구 (로한): 완료하면 해금제작 레시피가 무기고에서 제작 가능
RESEARCH = [["id", "이름", "해금제작", "비용", "소요(분)", "선행연구", "설명"], ["res_shotgun", "산탄총 설계", "r_shotgun", 60, 180, "", "가까운 적에게 강한 원거리 무기 (더미)"], ["res_smg", "기관단총 설계", "r_smg", 80, 240, "", "가벼운 연사 무기 (더미)"], ["res_blade", "고주파 블레이드", "r_blade", 100, 300, "", "근접 위력 최고 (더미)"], ["res_mg", "경기관총 설계", "r_mg", 150, 360, "res_smg", "기관단총 연구 후 (더미)"], ["res_launcher", "유탄발사기 설계", "r_launcher", 200, 480, "res_shotgun", "산탄총 연구 후 (더미)"]]


README = [
    ["시트", "열", "설명"],
    ["공통", "", "모든 수치·이름·대사는 프로토타입 임시값/더미 (01_OUTGAME_GDD 13절 미정 항목). 게임 실행 중 저장하면 1초 안에 다시 읽음"],
    ["설정", "id / 값", "시계·달러·위생·점검·훈련·강화 임시값. id 는 바꾸지 말 것"],
    ["층", "순서", "0 = 맨 위 (지상 1층). 화면에서 위→아래"],
    ["시설", "층 / 칸 / 폭", "시설 위치: 그 층의 왼쪽부터 칸 번호, 폭 = 차지하는 칸 수 (한 칸 240px). 자유 건설 없음 — 해금만"],
    ["시설", "해금비용 / 초기해금", "달러 해금 [확정]. 초기해금 O = 처음부터 열림 (지상 1층·지하 1층 기본 개방)"],
    ["시설", "기능", "출입(외부 의뢰 출발) / 계단(층 이동, 같은 칸 위아래 계단끼리 연결) / 행정 / 공용 / 생활 / 식당(식재료) / 상점(PX 선물) / 의무(치료·체력 회복) / 무기고(강화·제작·장착) / 훈련 / 미정"],
    ["오브젝트", "", "침대·소파·의자·의무침대. 잠은 오브젝트 위에서만 피로 회복(피로회복/시간), 체력은 체력회복 > 0 인 오브젝트(의무침대)에서만. 위치 = 방 폭 비율, 높이 = 눕는/앉는 높이 m"],
    ["PX", "기본 / 대원 이름 열", "친밀도 선물: 가격(USD). 대원 이름 열 = 그 대원에게 줄 때 오르는 친밀도 (빈 칸 = 기본). 기본보다 크면 좋아함(2배 이상 = 아주 좋아함), 작으면 별로"],
    ["친밀도대화", "친밀도 / 대사", "그 대원 친밀도가 기준 이상이면 해금 → 클릭해 대화하면 안 본 대화부터, 다 봤으면 해금된 가장 높은 단계. 머리 위 ♥ = 새 대화"],
    ["시설", "청소", "O = 오염·청소 대상, 점검 점수에 들어감"],
    ["시설", "조명", "방 조명 색 g1~g4 (전투 조명 프리셋과 같은 색 조합)"],
    ["대원", "전투캐릭터", "밸런스 엑셀 캐릭터 시트 id — 훈련·장비 결과가 전투에 반영됨"],
    ["대원", "스프라이트", "assets/characters/<스프라이트>/ — 캐릭터 프레임 애니메이션 (tools/char_sprites.py)"],
    ["대원", "일정", "주간 일정은 data/outgame/schedules/<대원 id>.json — Godot 에디터 '일정' 탭"],
    ["의뢰", "종류", "작업지시(기지 안 시설에서 일함) / 외부의뢰(장소=정문, 나갔다가 복귀). 수익은 미지급으로 쌓였다가 주간 결산 때 지급"],
    ["의뢰", "반복 / 처음부터", "반복 X = 한 번만 수락 가능. 처음부터 X = 요청 수락 등으로 열려야 보임"],
    ["대사", "id / 순서 / 화자", "같은 id 의 줄을 순서대로. 화자 = 대원 id (또는 아무 이름)"],
    ["대화이벤트", "", "두 대원이 같은 방에서 쉬는 중이면 대화(말풍선) → 클릭해 엿듣기. 장소 비우면 어디서나. 스토리 = 스토리 이벤트 id (있으면 '스토리' 표시)"],
    ["요청", "수락효과", "의뢰:<의뢰 id> = 그 의뢰를 엶 / 비우면 효과 없음"],
    ["제작", "결과무기", "밸런스 엑셀 아이템 시트 id. 비용·재료는 미정이라 시간만"],
]

# ------------------------------------------------------------------ 주간 일정 (더미)
H = 60
def blk(day, s, e, fac, act, req=None, fb=""):
    b = {"weekday": day, "start_minute": int(s * H), "end_minute": int(e * H), "target_facility_id": fac, "activity_id": act}
    if req:
        b["required_unlocks"] = req
    if fb:
        b["fallback_facility_id"] = fb
    return b

def week(npc, morning_fac, afternoon_fac, preferred, extra=None, weekend_fac="f1_lounge", delegate=None, nap_fac="b1_quarters"):
    out = []
    for d in range(7):
        weekend = d >= 5
        out.append(blk(d, 0, 7, "b1_quarters", "sleep"))
        out.append(blk(d, 7, 8, "f1_mess", "eat", fb="f1_lounge"))
        if weekend:
            out.append(blk(d, 8, 12, weekend_fac, "rest"))
            out.append(blk(d, 12, 13, "f1_mess", "eat", fb="f1_lounge"))
            out.append(blk(d, 13, 15, nap_fac, "sleep"))   # 주말 낮잠 (소파·침대에서만 피로 회복)
            out.append(blk(d, 15, 17, weekend_fac, "rest"))
        else:
            out.append(blk(d, 8, 12, morning_fac, "work"))
            out.append(blk(d, 12, 13, "f1_mess", "eat", fb="f1_lounge"))
            # 훈련실이 열리면 오후는 훈련 (해금 → 생활 변화 예시), 아니면 원래 업무
            out.append(blk(d, 13, 17, "b1_training", "train", req=["b1_training"]))
            out.append(blk(d, 13, 17, afternoon_fac, "work"))
        out.append(blk(d, 17, 19, "f1_lounge", "chat"))
        out.append(blk(d, 19, 20, "f1_mess", "eat", fb="f1_lounge"))
        out.append(blk(d, 20, 24, "b1_quarters", "rest"))
    if extra:
        out = extra(out)
    j = {"npc_id": npc, "preferred_facility_ids": preferred, "weekly_schedule": out,
         "delegation_rules": delegate or {"can_delegate_cleaning": False}}
    return j

def dan_extra(out):
    # 창고가 열리면 저녁 휴식을 창고에서 (해금 → 생활 변화 예시 2)
    res = []
    for b in out:
        if b["start_minute"] == 20 * H:
            res.append(dict(blk(b["weekday"], 20, 22, "b2_storage", "work", req=["b2_storage"])))
        res.append(b)
    return res

def rohan_week():
    # 연구원: 연구실에서 일하고 연구실 간이침대에서 잠 (주말 오후는 공용실 휴식)
    out = []
    for d in range(7):
        out.append(blk(d, 0, 7, "b1_lab", "sleep"))
        out.append(blk(d, 7, 8, "f1_mess", "eat", fb="f1_lounge"))
        out.append(blk(d, 8, 12, "b1_lab", "work"))
        out.append(blk(d, 12, 13, "f1_mess", "eat", fb="f1_lounge"))
        if d >= 5:
            out.append(blk(d, 13, 16, "f1_lounge", "rest"))
            out.append(blk(d, 16, 19, "b1_lab", "work"))
        else:
            out.append(blk(d, 13, 19, "b1_lab", "work"))
        out.append(blk(d, 19, 20, "f1_mess", "eat", fb="f1_lounge"))
        out.append(blk(d, 20, 23, "b1_lab", "work"))
        out.append(blk(d, 23, 24, "b1_lab", "rest"))
    return {"npc_id": "npc_rohan", "preferred_facility_ids": ["b1_lab"], "weekly_schedule": out,
            "delegation_rules": {"can_delegate_cleaning": False}}

SCHEDULES = [
    week("npc_dan", "f1_office", "b1_workshop", ["f1_lounge", "b1_quarters"], extra=dan_extra, nap_fac="f1_lounge",
         delegate={"can_delegate_cleaning": True, "delegate_to": ["npc_hana", "npc_kira"], "chance": 1.0, "self_if_none": True}),
    week("npc_kira", "f1_office", "f1_office", ["f1_office", "f1_lounge"]),
    week("npc_ethan", "b1_workshop", "b1_workshop", ["b1_workshop"], weekend_fac="b1_workshop"),
    week("npc_hana", "b1_workshop", "f1_office", ["f1_lounge"], nap_fac="f1_lounge"),
    week("npc_alma", "b1_quarters", "f1_lounge", ["b1_quarters", "f1_lounge"], weekend_fac="b1_quarters"),
    week("npc_nikita", "f1_office", "f1_office", ["f1_office"]),
    rohan_week(),
]

HEAD_FILL = PatternFill("solid", fgColor="2E3440")
wb = Workbook()
first = True
for name, table, widths in [("설정", SETTINGS, [22, 14, 70]), ("층", FLOORS, None), ("시설", FAC, None), ("대원", NPCS, None),
                             ("의뢰", JOBS, None), ("대사", LINES + AFF_LINES, [18, 6, 12, 70]), ("대화이벤트", CONVS, None),
                             ("요청", REQS, None), ("제작", RECIPES, None), ("연구", RESEARCH, None), ("오브젝트", OBJS, None), ("PX", PX, None), ("친밀도대화", AFF_TALKS, None), ("읽어보기", README, [12, 22, 90])]:
    ws = wb.active if first else wb.create_sheet()
    first = False
    ws.title = name
    cols, rows = table[0], table[1:]
    for r in table:
        ws.append(r)
    for c in ws[1]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = HEAD_FILL
        c.alignment = Alignment(horizontal="center")
    ws.freeze_panes = "B2" if name not in ("읽어보기", "대사") else "A2"
    for i, col in enumerate(cols):
        letter = ws.cell(row=1, column=i + 1).column_letter
        w = widths[i] if widths else max(8, min(46, max(len(str(col)) * 2 + 2, *[len(str(r[i])) + 2 for r in rows if i < len(r)])))
        ws.column_dimensions[letter].width = w
    def pick(colname, opts):
        if colname in cols:
            letter = ws.cell(row=1, column=cols.index(colname) + 1).column_letter
            dv = DataValidation(type="list", formula1='"%s"' % ",".join(opts), allow_blank=True)
            dv.add(f"{letter}2:{letter}200")
            ws.add_data_validation(dv)
    for c in ["초기해금", "청소", "반복", "처음부터"]:
        pick(c, ["O", "X"])
    pick("조명", ["g1", "g2", "g3", "g4"])
    pick("층", [f[0] for f in FLOORS[1:]])
    pick("종류", ["작업지시", "외부의뢰"])
    pick("기능", ["출입", "계단", "행정", "공용", "생활", "식당", "상점", "의무", "무기고", "훈련", "연구", "미정"])
    if name == "오브젝트":
        pick("종류", ["침대", "소파", "의자", "의무침대"])
os.makedirs(os.path.dirname(OUT), exist_ok=True)
wb.save(OUT)
print("saved", OUT)
RULES = {"rules": [
    {"id": "raid_6h", "name": "정기 습격 (예시)", "enabled": True, "mode": "interval", "interval_minutes": 360, "anchor": "06:00",
     "weekdays": [0, 1, 2, 3, 4, 5, 6], "start_day": "", "times": [], "date": "", "stages": ["stage_01"], "allow_skip": False,
     "note": "예시: 6시간마다(00·06·12·18시) 전투 발생"},
]}
with open(os.path.join(ROOT, "data", "outgame", "battle_rules.json"), "w", encoding="utf-8") as f:
    json.dump(RULES, f, ensure_ascii=False, indent="\t")
print("saved data/outgame/battle_rules.json")
os.makedirs(SCHED_DIR, exist_ok=True)
for s in SCHEDULES:
    p = os.path.join(SCHED_DIR, s["npc_id"] + ".json")
    with open(p, "w", encoding="utf-8") as f:
        json.dump(s, f, ensure_ascii=False, indent=1)
    print("saved", p)
