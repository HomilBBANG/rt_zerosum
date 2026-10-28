@tool
class_name UnlockCond
extends RefCounted
## 해금 조건 (신 해금 캐릭터 등). 조건 = {type, value}. 판정은 BaseSim.cond_met (게임 상태가 필요해서).
## always = 처음부터 해금 · manual = 이벤트·대사에서 직접 (BaseSim.unlock_divine) · level/faith/affinity = 그 캐릭터 값 이상 · day = n일차부터

const TYPES := {"always": "처음부터 해금", "manual": "직접 해금 (이벤트·대사)", "level": "레벨", "faith": "신앙도", "affinity": "친밀도", "day": "일차"}
const ORDER := ["always", "manual", "level", "faith", "affinity", "day"]
## 값을 쓰는 조건과 범위
const RANGE := {"level": [1, 20], "faith": [0, 100], "affinity": [0, 100], "day": [1, 999]}


static func norm(c: Variant) -> Dictionary:
	var d: Dictionary = c if c is Dictionary else {}
	var t := str(d.get("type", "manual"))
	if not TYPES.has(t):
		t = "manual"
	var r: Array = RANGE.get(t, [0, 0])
	return {"type": t, "value": clampi(int(d.get("value", r[0])), int(r[0]), int(r[1])) if RANGE.has(t) else 0}


static func uses_value(t: String) -> bool:
	return RANGE.has(t)


## "레벨 8 이상" · "12일차부터" · "처음부터 해금"
static func describe(c: Dictionary) -> String:
	match str(c.get("type", "")):
		"level", "faith", "affinity":
			return "%s %d 이상" % [TYPES[c.type], int(c.value)]
		"day":
			return "%d일차부터" % int(c.value)
	return str(TYPES.get(c.get("type", ""), "?"))
