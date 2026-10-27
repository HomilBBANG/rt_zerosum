@tool
class_name StatusCatalog
extends RefCounted
## 상태 이상 정의. positive = 긍정(녹색) / 부정(붉은색).
## expires: "own_turn_end" = 그 유닛의 다음 턴이 끝나면 사라짐, "" = 직접 지울 때까지 (기지 상태: 부상 등).
## blocks_move: 자리 이동·교체 대상에서 빠짐.
## battle: 전투 안에서만 (전투가 끝나면 사라지고 기지로 안 넘어감). 지속 턴·수치는 스킬마다 (밸런스 엑셀 스킬 시트 상태이상·상태턴·상태수치·상태확률).
## 전투 상태 이상 규칙 (StatusRules):
##  · 처음 걸릴 때 바로 한 번 적용 (출혈·화상 = 그 자리에서 피해, 감속·가속 = 그 라운드 남은 순서부터 반영)
##  · 그 뒤 그 캐릭터 차례가 올 때마다 행동보다 먼저 적용 (출혈·화상 피해, 동상 카운트, 기절 = 그 차례 행동 불가)
##  · 지속 n턴 = 그 캐릭터 차례 n번 (차례가 끝날 때 1 줄고 0 이면 사라짐). 동상만 차례가 시작할 때 1 줄고 0 이 되면 터짐

const DEFS := {
	"rallied": {"name": "독려", "positive": true, "expires": "own_turn_end",
		"desc": "아군의 독려로 AP 를 추가로 받았습니다. 이 유닛의 다음 턴이 끝나면 사라집니다."},
	"injured": {"name": "부상", "positive": false, "expires": "", "blocks_move": true,
		"desc": "다쳐서 자리 이동·교체를 할 수 없습니다."},
	"bleed": {"name": "출혈", "short": "혈", "positive": false, "battle": true, "color": Color(0.95, 0.2, 0.25),
		"desc": "걸릴 때와 자기 차례마다 최대 HP 의 {v}% 피해. {t}턴."},
	"burn": {"name": "화상", "short": "화", "positive": false, "battle": true, "element": "fire", "color": Color(1.0, 0.55, 0.15),
		"desc": "걸릴 때와 자기 차례마다 화염 속성 고정 피해 {v} (방어 무시). {t}턴."},
	"frost": {"name": "동상", "short": "동", "positive": false, "battle": true, "color": Color(0.55, 0.85, 1.0),
		"desc": "자기 차례 {t}번 뒤 최대 HP 의 {v}% 피해 1회, 그리고 풀림."},
	"slow": {"name": "감속", "short": "감", "positive": false, "battle": true, "color": Color(0.6, 0.6, 0.95),
		"desc": "속도 {v}% 감소 (행동 순서가 늦어짐). {t}턴."},
	"haste": {"name": "가속", "short": "가", "positive": true, "battle": true, "color": Color(0.4, 1.0, 0.6),
		"desc": "속도 {v}% 증가 (행동 순서가 빨라짐). {t}턴."},
	"stun": {"name": "기절", "short": "기", "positive": false, "battle": true, "color": Color(1.0, 0.9, 0.3),
		"desc": "{t}턴 동안 자기 차례에 행동할 수 없음. 다른 아군이 자기 차례에 기절한 캐릭터와 자리를 바꾸는 것은 가능."},
	"root": {"name": "구속", "short": "구", "positive": false, "battle": true, "blocks_move": true, "color": Color(0.75, 0.55, 0.35),
		"desc": "{t}턴 동안 자리 이동 불가. 다른 캐릭터와 자리를 바꾸는 것도 불가."},
	"blind": {"name": "실명", "short": "실", "positive": false, "battle": true, "color": Color(0.7, 0.7, 0.75),
		"desc": "{t}턴 동안 대상이 무작위 — 아군 대상 스킬은 아군 중 무작위 1명, 적 대상 스킬은 적 중 무작위 1명 (사거리 규칙 안에서)."},
}
## 전투 상태 이상 (엑셀 스킬 시트 '상태이상' 열에 쓰는 것)
const BATTLE := ["bleed", "burn", "frost", "slow", "haste", "stun", "root", "blind"]


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {"name": id, "positive": false, "expires": "", "desc": ""})


## id 또는 한글 이름 → id ("" = 없음)
static func find(name_or_id: String) -> String:
	var k := name_or_id.strip_edges()
	if k == "" or DEFS.has(k):
		return k
	for id in DEFS:
		if DEFS[id].name == k:
			return id
	return ""


## 설명 문장 (info = {turns, value})
static func describe(id: String, info: Dictionary = {}) -> String:
	var d := get_def(id)
	var t: String = d.get("desc", "")
	return t.replace("{t}", str(int(info.get("turns", 0)))).replace("{v}", str(int(info.get("value", 0))))


static func color_of(id: String) -> Color:
	var d := get_def(id)
	return d.get("color", Color(0.45, 1.0, 0.6) if d.get("positive", false) else Color(1.0, 0.45, 0.4))
