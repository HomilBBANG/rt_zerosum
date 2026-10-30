@tool
class_name StatusCatalog
extends RefCounted
## 상태 이상 = 이름 붙은 상태(data/statuses.json, 에디터 '스킬 트리' 탭 → 상태 정의) + 그 상태가 쓰는 효과(EFFECTS, 규칙은 StatusRules).
## 같은 효과를 이름만 다르게 여러 상태로 쓸 수 있음 — 예: '진통제'·'자가 치유' 둘 다 효과 regen(재생).
## 상태 id = 효과 id, 같은 효과의 두 번째부터는 _2, _3 … (예: regen = 재생, regen_2 = 진통제, regen_3 = 자가 치유).
## 같은 id 는 겹치지 않음(다시 걸리면 남은 턴·수치 큰 쪽으로 갱신) → 같은 효과라도 id 가 다르면 따로 걸림.
## 상태 = {id, name, effect, short(머리 위 한 글자), color(#rrggbb), desc(비우면 효과 설명)}. 스킬에는 상태 id 를 담 (data/skill_status.json).
## positive = 긍정(녹색) / 부정(붉은색). blocks_move: 자리 이동·교체 대상에서 빠짐. instant: 맞는 순간 한 번(넉백·끌어당김), 남지 않음.
## battle: 전투 안에서만 (전투가 끝나면 사라지고 기지로 안 넘어감). expires "own_turn_end" = 그 유닛의 다음 턴이 끝나면 사라짐.
## 전투 상태 이상 규칙 (StatusRules):
##  · 처음 걸릴 때 바로 한 번 적용 (출혈·화상 = 그 자리에서 피해, 재생 = 회복, 감속·가속 = 그 라운드 남은 순서부터 반영)
##  · 그 뒤 그 캐릭터 차례가 올 때마다 행동보다 먼저 적용 (출혈·화상 피해, 재생 회복, 동상 카운트, 기절 = 그 차례 행동 불가)
##  · 지속 n턴 = 그 캐릭터 차례 n번 (차례가 끝날 때 1 줄고 0 이면 사라짐). 동상만 차례가 시작할 때 1 줄고 0 이 되면 터짐

const PATH := "res://data/statuses.json"

## 게임 규칙이 직접 거는 상태 (스킬에 달지 않음)
const SYSTEM := {
	"rallied": {"name": "독려", "effect": "rallied", "positive": true, "expires": "own_turn_end",
		"desc": "아군의 독려로 AP 를 추가로 받았습니다. 이 유닛의 다음 턴이 끝나면 사라집니다."},
	"injured": {"name": "부상", "effect": "injured", "positive": false, "expires": "", "blocks_move": true,
		"desc": "다쳐서 자리 이동·교체를 할 수 없습니다."},
}

## 효과 (규칙) — name/short/color 는 그 효과로 새 상태를 만들 때의 기본값. hint = '수치' 의 뜻 ("" = 수치 안 씀), value = 기본 수치
const EFFECTS := {
	"bleed": {"name": "출혈", "short": "혈", "positive": false, "color": Color(0.95, 0.2, 0.25), "hint": "최대 HP %", "value": 10,
		"desc": "걸릴 때와 자기 차례마다 최대 HP 의 {v}% 피해. {t}턴."},
	"burn": {"name": "화상", "short": "화", "positive": false, "element": "fire", "color": Color(1.0, 0.55, 0.15), "hint": "고정 피해", "value": 4,
		"desc": "걸릴 때와 자기 차례마다 화염 속성 고정 피해 {v} (방어 무시). {t}턴."},
	"frost": {"name": "동상", "short": "동", "positive": false, "color": Color(0.55, 0.85, 1.0), "hint": "최대 HP %", "value": 20,
		"desc": "자기 차례 {t}번 뒤 최대 HP 의 {v}% 피해 1회, 그리고 풀림."},
	"slow": {"name": "감속", "short": "감", "positive": false, "color": Color(0.6, 0.6, 0.95), "hint": "속도 %", "value": 30,
		"desc": "속도 {v}% 감소 (행동 순서가 늦어짐). {t}턴."},
	"haste": {"name": "가속", "short": "가", "positive": true, "color": Color(0.4, 1.0, 0.6), "hint": "속도 %", "value": 30,
		"desc": "속도 {v}% 증가 (행동 순서가 빨라짐). {t}턴."},
	"stun": {"name": "기절", "short": "기", "positive": false, "color": Color(1.0, 0.9, 0.3), "hint": "", "value": 0,
		"desc": "{t}턴 동안 자기 차례에 행동할 수 없음. 다른 아군이 자기 차례에 기절한 캐릭터와 자리를 바꾸는 것은 가능."},
	"root": {"name": "구속", "short": "구", "positive": false, "blocks_move": true, "color": Color(0.75, 0.55, 0.35), "hint": "", "value": 0,
		"desc": "{t}턴 동안 자리 이동 불가. 다른 캐릭터와 자리를 바꾸는 것도, 넉백·끌어당김도 불가."},
	"blind": {"name": "실명", "short": "실", "positive": false, "color": Color(0.7, 0.7, 0.75), "hint": "", "value": 0,
		"desc": "{t}턴 동안 대상이 무작위 — 아군 대상 스킬은 아군 중 무작위 1명, 적 대상 스킬은 적 중 무작위 1명 (사거리 규칙 안에서)."},
	"knockback": {"name": "넉백", "short": "넉", "positive": false, "instant": true, "color": Color(0.95, 0.75, 0.45), "hint": "칸 수", "value": 1,
		"desc": "맞으면 {v}칸 뒤로 밀림 (뒤 칸에 같은 편이 있으면 그와 자리를 바꿈). 맨 뒤 열·구속·부상·큰 몸집이면 안 밀림."},
	"pull": {"name": "끌어당김", "short": "끌", "positive": false, "instant": true, "color": Color(0.85, 0.5, 0.95), "hint": "칸 수", "value": 1,
		"desc": "맞으면 {v}칸 앞으로 끌려옴 (앞 칸에 같은 편이 있으면 그와 자리를 바꿈). 맨 앞 열·구속·부상·큰 몸집이면 안 끌려옴."},
	"mark": {"name": "표식", "short": "표", "positive": false, "color": Color(1.0, 0.35, 0.6), "hint": "공격 위력 %", "value": 25,
		"desc": "{t}턴 동안 이 대상을 노리는 공격의 위력 {v}% 증가. 적 AI 는 표식이 있는 대상을 먼저 노림."},
	"taunt": {"name": "도발", "short": "도", "positive": true, "color": Color(1.0, 0.6, 0.25), "hint": "", "value": 0,
		"desc": "{t}턴 동안 상대 편은 공격할 때 이 캐릭터만 고를 수 있음 (사거리 안에 있을 때. 근접은 닿는 열에 있을 때)."},
	"vulnerable": {"name": "취약", "short": "취", "positive": false, "color": Color(0.9, 0.45, 0.35), "hint": "받는 피해 %", "value": 25,
		"desc": "{t}턴 동안 받는 피해 {v}% 증가 (출혈·화상 같은 상태 이상 피해 포함)."},
	"regen": {"name": "재생", "short": "재", "positive": true, "color": Color(0.45, 0.95, 0.55), "hint": "최대 HP %", "value": 10,
		"desc": "걸릴 때와 자기 차례마다 최대 HP 의 {v}% 회복. {t}턴."},
	"shield": {"name": "보호막", "short": "막", "positive": true, "color": Color(0.55, 0.8, 1.0), "hint": "막는 피해", "value": 10,
		"desc": "받는 피해를 {v}만큼 대신 막고, 다 막으면 사라짐 (상태 이상 피해 포함). 최대 {t}턴."},
}
## 효과 목록 순서 (에디터)
const EFFECT_ORDER := ["bleed", "burn", "frost", "slow", "haste", "stun", "root", "blind", "knockback", "pull", "mark", "taunt", "vulnerable", "regen", "shield"]

static var _defs: Dictionary = {}    # 상태 id → 정의 (data/statuses.json)
static var _order: Array = []        # 상태 id 순서
static var _loaded := false


# ---------------------------------------------------------------- data/statuses.json
static func new_status(id: String, effect: String) -> Dictionary:
	var e: Dictionary = EFFECTS.get(effect, {})
	return {"id": id, "name": str(e.get("name", id)), "effect": effect, "short": str(e.get("short", "?")),
		"color": "#" + (e.get("color", Color.WHITE) as Color).to_html(false), "desc": ""}


## 그 효과로 새로 만들 상태 id: 효과 id → 이미 있으면 효과_2, 효과_3 … (except = 지금 고치는 상태라 빼고 셈)
static func next_id(effect: String, entries: Array, except: Variant = null) -> String:
	var used := {}
	for s in entries:
		if s != except:
			used[str(s.id)] = true
	if not used.has(effect):
		return effect
	var n := 2
	while used.has("%s_%d" % [effect, n]):
		n += 1
	return "%s_%d" % [effect, n]


## id 가 그 효과의 id 규칙(효과 id 또는 효과 id_숫자)에 맞나
static func id_matches(id: String, effect: String) -> bool:
	if id == effect:
		return true
	var tail := id.trim_prefix(effect + "_")
	return id.begins_with(effect + "_") and tail.is_valid_int() and int(tail) >= 2


## 파일 → 상태 목록. 파일이 없으면 효과마다 같은 id 의 기본 상태
static func read(path: String = PATH) -> Array:
	var out := []
	if FileAccess.file_exists(path):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if j is Dictionary and j.get("statuses") is Array:
			for s in j.statuses:
				if s is Dictionary:
					var eff := str(s.get("effect", s.get("id", "")))
					var d := new_status(str(s.get("id", "")), eff)
					for k in ["name", "short", "color", "desc"]:
						if s.has(k):
							d[k] = str(s[k])
					out.append(d)
			if path == PATH:
				SkillTable.apply_statuses(out)   # data/skills.xlsx 표의 이름 · 글자 · 색 · 설명이 우선
			return out
	for eff in EFFECT_ORDER:
		out.append(new_status(eff, eff))
	return out


static func write(entries: Array, path: String = PATH) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version": 1, "statuses": entries}, "\t", false))
	f.close()
	refresh(entries)
	return OK


## 다시 읽기 (게임 실행 중 파일이 바뀌면 · 에디터 저장 뒤). entries 를 주면 그 목록으로
static func refresh(entries: Variant = null) -> void:
	_defs.clear()
	_order.clear()
	for s in (entries if entries is Array else read()):
		_defs[s.id] = s
		_order.append(s.id)
	_loaded = true


static func _ensure() -> void:
	if not _loaded:
		refresh()


## 검사: 오류(게임에서 틀어짐) / 주의. used = 상태 id → 쓰는 스킬 수
static func check(entries: Array, used: Dictionary = {}) -> Dictionary:
	var errors := PackedStringArray()
	var notes := PackedStringArray()
	var ids := {}
	var names := {}
	for s in entries:
		var id := str(s.id)
		if id == "":
			errors.append("id 가 빈 상태가 있습니다")
		elif ids.has(id):
			errors.append("상태 id '%s' 가 두 번 있습니다" % id)
		elif SYSTEM.has(id):
			errors.append("'%s' 는 게임이 쓰는 상태 id 입니다 (다른 id)" % id)
		ids[id] = true
		if not EFFECTS.has(str(s.effect)):
			errors.append("%s: 모르는 효과 '%s'" % [id, s.effect])
		elif id != "" and not SYSTEM.has(id) and not id_matches(id, str(s.effect)):
			errors.append("%s: id 는 효과 id 또는 효과 id_숫자 (예: %s, %s_2)" % [id, s.effect, s.effect])
		if str(s.name).strip_edges() == "":
			errors.append("%s: 이름이 비었습니다" % id)
		elif names.has(s.name):
			notes.append("이름 '%s' 가 둘 (%s, %s) — 전투 화면에서 구분이 안 됨" % [s.name, names[s.name], id])
		names[s.name] = id
		if str(s.short).length() != 1:
			notes.append("%s: 머리 위 글자는 한 글자가 보기 좋습니다 ('%s')" % [id, s.short])
		if not used.is_empty() and int(used.get(id, 0)) == 0:
			notes.append("%s(%s): 어느 스킬에도 안 달림" % [s.name, id])
	return {"errors": errors, "notes": notes}


# ---------------------------------------------------------------- 조회
## 상태 정의 (효과 규칙 값 + 상태 이름·글자·색). 모르는 id 면 이름 = id
static func get_def(id: String) -> Dictionary:
	if SYSTEM.has(id):
		return SYSTEM[id]
	_ensure()
	var s: Dictionary = _defs.get(id, {})
	var eff := str(s.get("effect", id))
	if s.is_empty() and not EFFECTS.has(eff):
		return {"name": id, "effect": id, "positive": false, "expires": "", "desc": ""}
	var d: Dictionary = (EFFECTS.get(eff, {}) as Dictionary).duplicate()
	d["effect"] = eff
	d["battle"] = true
	if not s.is_empty():
		d["name"] = s.name
		d["short"] = s.short
		if str(s.color).begins_with("#"):
			d["color"] = Color.html(s.color)
		if str(s.get("desc", "")).strip_edges() != "":
			d["desc"] = s.desc
	return d


## 상태 → 효과 id (규칙). 효과 이름 그대로 쓴 상태는 자기 자신
static func effect_of(id: String) -> String:
	if SYSTEM.has(id):
		return id
	_ensure()
	return str((_defs.get(id, {}) as Dictionary).get("effect", id))


## 스킬에 달 수 있는 전투 상태 id (data/statuses.json 순서)
static func battle_ids() -> Array:
	_ensure()
	return _order.duplicate()


## 게임 규칙 상태 + 전투 상태 모두
static func all_ids() -> Array:
	return SYSTEM.keys() + battle_ids()


## id 또는 한글 이름 → id ("" = 없음)
static func find(name_or_id: String) -> String:
	var k := name_or_id.strip_edges()
	_ensure()
	if k == "" or SYSTEM.has(k) or _defs.has(k):
		return k
	for id in SYSTEM:
		if SYSTEM[id].name == k:
			return id
	for id in _order:
		if _defs[id].name == k:
			return id
	return k if EFFECTS.has(k) else ""


## '수치' 의 뜻 ("" = 수치 안 씀)
static func hint(id: String) -> String:
	return str((EFFECTS.get(effect_of(id), {}) as Dictionary).get("hint", ""))


static func default_value(id: String) -> int:
	return int((EFFECTS.get(effect_of(id), {}) as Dictionary).get("value", 0))


## 맞는 순간 한 번만 (넉백·끌어당김) — 지속 턴 없음
static func is_instant(id: String) -> bool:
	return bool((EFFECTS.get(effect_of(id), {}) as Dictionary).get("instant", false))


## 설명 문장 (info = {turns, value})
static func describe(id: String, info: Dictionary = {}) -> String:
	var d := get_def(id)
	var t: String = d.get("desc", "")
	return t.replace("{t}", str(int(info.get("turns", 0)))).replace("{v}", str(int(info.get("value", 0))))


static func color_of(id: String) -> Color:
	var d := get_def(id)
	return d.get("color", Color(0.45, 1.0, 0.6) if d.get("positive", false) else Color(1.0, 0.45, 0.4))
