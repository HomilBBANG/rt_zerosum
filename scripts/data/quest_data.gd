@tool
class_name QuestData
extends RefCounted
## 퀘스트 (data/quests.json, Godot 에디터 상단 '퀘스트' 탭에서 편집).
## 퀘스트 = {id, name, giver(의뢰인 대원 npc id, "" = 없음), desc, start(시작 조건 UnlockCond), steps[단계], rewards{cash, affinity}}
## 단계 = {kind, target, count, desc} — 앞 단계부터 하나씩. 진행은 BaseSim (start_quest · quest_state · update_quests).
##   횟수 단계(의뢰 완료 · 전투 승리 · 대화)는 그 단계가 시작된 뒤부터 셈 / 상태 단계(연구 · 친밀도 · 레벨 · 일차 · 다른 퀘스트)는 그때 맞으면 바로 완료
## 시작 조건: 처음부터 / 직접(이벤트·대사에서 BaseSim.start_quest) / 미션 완료(의뢰·전투·연구·다른 퀘스트) / 의뢰인 레벨·신앙도·친밀도 / n일차
## 완료한 퀘스트는 신 해금 조건 '미션 완료' 의 미션으로 쓸 수 있음 (target "quest:퀘스트 id").

const PATH := "res://data/quests.json"
const STEP_KINDS := {"contract": "의뢰 완료", "stage": "전투 승리", "research": "연구 완료", "talk": "대원과 대화",
	"affinity": "대원 친밀도", "level": "대원 레벨", "day": "일차 도달", "quest": "다른 퀘스트 완료"}
const STEP_ORDER := ["contract", "stage", "talk", "research", "affinity", "level", "day", "quest"]
## 횟수로 세는 단계 (그 단계 시작 뒤부터) / 값 이상이면 되는 단계
const COUNTED := ["contract", "stage", "talk"]
const VALUED := ["affinity", "level", "day"]


static func new_quest(id: String) -> Dictionary:
	return {"id": id, "name": "새 퀘스트", "giver": "", "desc": "", "start": {"type": "always", "value": 0, "target": ""},
		"steps": [new_step("contract")], "rewards": {"cash": 0, "affinity": 0}}


static func new_step(kind: String) -> Dictionary:
	return {"kind": kind, "target": "", "count": 1 if kind in COUNTED else (50 if kind == "affinity" else (5 if kind == "level" else (3 if kind == "day" else 1))), "desc": ""}


static func _norm_step(st: Dictionary) -> Dictionary:
	var k := str(st.get("kind", "contract"))
	if not STEP_KINDS.has(k):
		k = "contract"
	return {"kind": k, "target": str(st.get("target", "")), "count": maxi(1, int(st.get("count", 1))), "desc": str(st.get("desc", ""))}


static func read(path: String = PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (j is Dictionary and j.get("quests") is Array):
		return []
	var out := []
	for q in j.quests:
		if not q is Dictionary:
			continue
		var steps := []
		for st in q.get("steps", []):
			if st is Dictionary:
				steps.append(_norm_step(st))
		var rw: Dictionary = q.get("rewards", {}) if q.get("rewards") is Dictionary else {}
		out.append({"id": str(q.get("id", "")), "name": str(q.get("name", "")), "giver": str(q.get("giver", "")), "desc": str(q.get("desc", "")),
			"start": UnlockCond.norm(q.get("start", {"type": "always"})), "steps": steps,
			"rewards": {"cash": maxi(0, int(rw.get("cash", 0))), "affinity": int(rw.get("affinity", 0))}})
	return out


static func write(quests: Array, path: String = PATH) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version": 1, "quests": quests}, "\t", false))
	return OK


static func by_id(quests: Array) -> Dictionary:
	var out := {}
	for q in quests:
		out[q.id] = q
	return out


## 단계 자동 설명 ("민간인 호위 의뢰 완료 ×1", "하나 친밀도 50 이상") — names = 대상 id → 이름 (target_names)
static func step_text(st: Dictionary, names: Dictionary = {}) -> String:
	var t := str(st.get("target", ""))
	var nm: String = names.get(st.kind + ":" + t, t)
	var n := int(st.get("count", 1))
	match str(st.kind):
		"contract":
			return "의뢰 '%s' 완료%s" % [nm, " ×%d" % n if n > 1 else ""]
		"stage":
			return ("전투 '%s' 승리" % nm if t != "" else "전투 승리") + (" ×%d" % n if n > 1 else "")
		"research":
			return "연구 '%s' 완료" % nm
		"talk":
			return "%s 와 대화%s" % [nm, " ×%d" % n if n > 1 else ""]
		"affinity":
			return "%s 친밀도 %d 이상" % [nm, n]
		"level":
			return "%s 레벨 %d 이상" % [nm, n]
		"day":
			return "%d일차가 되기" % n
		"quest":
			return "퀘스트 '%s' 완료" % nm
	return str(st.kind)


## 단계 대상 고르기 목록 [[id, 표시]] (kind 마다) — od = OutgameData, gd = GameData, quests = 퀘스트 목록
static func targets(kind: String, od: OutgameData, gd: GameData, quests: Array = []) -> Array:
	var out := []
	match kind:
		"contract":
			if od != null:
				for id in od.job_order:
					out.append([id, "%s (%s)" % [od.jobs[id].name, "외부 의뢰" if od.jobs[id].kind == "external" else "작업 지시"]])
		"stage":
			out.append(["", "아무 전투"])
			if gd != null:
				for id in gd.stage_order:
					out.append([id, str(gd.stages[id].get("name", id))])
		"research":
			if od != null:
				for id in od.research_order:
					out.append([id, str(od.research[id].get("name", id))])
		"talk", "affinity":
			if od != null:
				for id in od.npc_order:
					out.append([id, str(od.npcs[id].name)])
		"level":
			if gd != null:
				for u in gd.allies:
					out.append([u.id, u.display_name])
		"quest":
			for q in quests:
				out.append([q.id, str(q.name)])
	return out


## "kind:id" → 이름 (단계 설명용)
static func target_names(od: OutgameData, gd: GameData, quests: Array = []) -> Dictionary:
	var out := {}
	for k in STEP_ORDER:
		for t in targets(k, od, gd, quests):
			var nm := str(t[1])
			out[k + ":" + str(t[0])] = nm.substr(0, nm.find(" (")) if nm.find(" (") > 0 else nm
	return out


## 검사 → {errors, notes}
static func check(quests: Array, od: OutgameData, gd: GameData) -> Dictionary:
	var errors := PackedStringArray()
	var notes := PackedStringArray()
	var ids := {}
	for q in quests:
		if str(q.id) == "":
			errors.append("id 가 빈 퀘스트가 있습니다")
		elif ids.has(q.id):
			errors.append("퀘스트 id '%s' 가 두 번 있습니다" % q.id)
		ids[q.id] = true
	for q in quests:
		var where := "%s(%s)" % [q.name, q.id]
		if (q.steps as Array).is_empty():
			errors.append("%s: 단계가 없습니다" % where)
		if str(q.giver) != "" and od != null and not od.npcs.has(q.giver):
			errors.append("%s: 없는 의뢰인 '%s'" % [where, q.giver])
		var sc: Dictionary = q.start
		if sc.type in ["level", "faith", "affinity"] and str(q.giver) == "":
			errors.append("%s: 시작 조건 '%s' 는 의뢰인이 있어야 함" % [where, UnlockCond.TYPES[sc.type]])
		if sc.type == "quest":
			var tg := str(sc.get("target", ""))
			if tg == "quest:" + q.id:
				errors.append("%s: 시작 조건이 자기 자신 완료" % where)
			elif tg == "":
				errors.append("%s: 시작 조건 '미션 완료' 인데 미션이 없습니다" % where)
		if sc.type == "manual":
			notes.append("%s: 직접 시작 — 이벤트·대사에서 BaseSim.start_quest('%s') 를 불러야 시작" % [where, q.id])
		for i in (q.steps as Array).size():
			var st: Dictionary = q.steps[i]
			var k: String = st.kind
			var t := str(st.target)
			var ok := k == "day" or (k == "stage" and t == "")
			if not ok:
				ok = targets(k, od, gd, quests).any(func(x): return str(x[0]) == t)
			if not ok:
				errors.append("%s %d단계: %s 대상 '%s' 가 없습니다" % [where, i + 1, STEP_KINDS[k], t])
			if k == "quest" and t == q.id:
				errors.append("%s %d단계: 자기 자신 완료" % [where, i + 1])
	return {"errors": errors, "notes": notes}
