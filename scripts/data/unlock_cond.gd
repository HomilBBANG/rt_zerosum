@tool
class_name UnlockCond
extends RefCounted
## 해금 조건 (신 해금 캐릭터 등). 조건 = {type, value, target}. 판정은 BaseSim.cond_met (게임 상태가 필요해서).
## always = 처음부터 해금 · manual = 이벤트·대사에서 직접 (BaseSim.unlock_divine) · level/faith/affinity = 그 캐릭터 값 이상 · day = n일차부터
## quest = 미션 완료 — target "contract:의뢰 id"(그 의뢰 업무를 끝냄) / "stage:스테이지 id"(그 전투 승리) / "research:연구 id"(연구 완료) / "quest:퀘스트 id"(퀘스트 완료 — data/quests.json)

const TYPES := {"always": "처음부터 해금", "manual": "직접 해금 (이벤트·대사)", "quest": "미션 완료", "level": "레벨", "faith": "신앙도", "affinity": "친밀도", "day": "일차"}
const ORDER := ["always", "manual", "quest", "level", "faith", "affinity", "day"]
## 미션 종류 (quest 의 target 앞부분)
const MISSION_KINDS := {"contract": "의뢰", "stage": "전투", "research": "연구", "quest": "퀘스트"}
## 값을 쓰는 조건과 범위
const RANGE := {"level": [1, 20], "faith": [0, 100], "affinity": [0, 100], "day": [1, 999]}


static func norm(c: Variant) -> Dictionary:
	var d: Dictionary = c if c is Dictionary else {}
	var t := str(d.get("type", "manual"))
	if not TYPES.has(t):
		t = "manual"
	var r: Array = RANGE.get(t, [0, 0])
	return {"type": t, "value": clampi(int(d.get("value", r[0])), int(r[0]), int(r[1])) if RANGE.has(t) else 0,
		"target": str(d.get("target", "")) if t == "quest" else ""}


static func uses_value(t: String) -> bool:
	return RANGE.has(t)


## "레벨 8 이상" · "12일차부터" · "미션 완료: 의뢰 민간인 호위" · "처음부터 해금". names = 미션 target → 이름 (없으면 id)
static func describe(c: Dictionary, names: Dictionary = {}) -> String:
	match str(c.get("type", "")):
		"quest":
			var t := str(c.get("target", ""))
			if t == "":
				return "미션 완료 (미션을 고르세요)"
			var kind := t.split(":")[0]
			return "미션 완료: %s %s" % [MISSION_KINDS.get(kind, kind), names.get(t, t.substr(kind.length() + 1))]
		"level", "faith", "affinity":
			return "%s %d 이상" % [TYPES[c.type], int(c.value)]
		"day":
			return "%d일차부터" % int(c.value)
	return str(TYPES.get(c.get("type", ""), "?"))


## 미션 목록 [[target, 표시]] — od = OutgameData(의뢰·연구), gd = GameData(스테이지·퀘스트)
static func missions(od: OutgameData, gd: GameData) -> Array:
	var out := []
	if od != null:
		for id in od.job_order:
			var j: Dictionary = od.jobs[id]
			out.append(["contract:" + id, "의뢰 · %s (%s)" % [j.name, "외부 의뢰" if j.kind == "external" else "작업 지시"]])
	if gd != null:
		for id in gd.stage_order:
			out.append(["stage:" + id, "전투 · %s 승리" % gd.stages[id].get("name", id)])
	if od != null:
		for id in od.research_order:
			out.append(["research:" + id, "연구 · %s" % od.research[id].get("name", id)])
	if gd != null:
		for q in gd.quests:
			out.append(["quest:" + q.id, "퀘스트 · %s 완료" % q.name])
	return out


## 미션 target → 이름만 ("contract:c_ext_escort" → "민간인 호위")
static func mission_names(od: OutgameData, gd: GameData) -> Dictionary:
	var out := {}
	if od != null:
		for id in od.job_order:
			out["contract:" + id] = str(od.jobs[id].name)
		for id in od.research_order:
			out["research:" + id] = str(od.research[id].get("name", id))
	if gd != null:
		for id in gd.stage_order:
			out["stage:" + id] = str(gd.stages[id].get("name", id))
		for q in gd.quests:
			out["quest:" + q.id] = str(q.name)
	return out

