@tool
class_name SkillStatusData
extends RefCounted
## 스킬에 다는 상태 이상 (data/skill_status.json, Godot 에디터 '스킬 트리' 탭의 '상태 이상' 에서 편집).
## 항목 = {skill(스킬 id), status(StatusCatalog id), turns(지속 = 그 캐릭터 차례 수), value(수치), chance(확률 %)}
## 한 스킬에 여러 개를 달 수 있음 (각각 따로 확률). 스킬 자체(AP·위력·대상)는 밸런스 엑셀 스킬 시트.

const PATH := "res://data/skill_status.json"
## 상태마다 '수치' 의 뜻 ("" = 수치 안 씀)
const VALUE_HINT := {"bleed": "최대 HP %", "burn": "고정 피해", "frost": "최대 HP %", "slow": "속도 %", "haste": "속도 %",
	"stun": "", "root": "", "blind": ""}


static func new_entry(skill: String, status: String = "bleed") -> Dictionary:
	return {"skill": skill, "status": status, "turns": 2, "value": 10 if VALUE_HINT.get(status, "") != "" else 0, "chance": 100}


static func read(path: String = PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (j is Dictionary and j.get("statuses") is Array):
		return []
	var out := []
	for e in j.statuses:
		if e is Dictionary:
			out.append({"skill": str(e.get("skill", "")), "status": StatusCatalog.find(str(e.get("status", ""))),
				"turns": maxi(1, int(e.get("turns", 1))), "value": int(e.get("value", 0)), "chance": clampi(int(e.get("chance", 100)), 0, 100)})
	return out


static func write(entries: Array, path: String = PATH) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version": 1, "statuses": entries}, "\t", false))
	return OK


## 스킬 id → [{id, turns, value, chance}] (ActionData.statuses 형식)
static func by_skill(entries: Array) -> Dictionary:
	var out := {}
	for e in entries:
		if not out.has(e.skill):
			out[e.skill] = []
		out[e.skill].append({"id": e.status, "turns": int(e.turns), "value": int(e.value), "chance": int(e.chance)})
	return out


## "출혈 2턴 (최대 HP 10%) · 확률 70%"
static func summary(st: Dictionary) -> String:
	var sid := str(st.get("id", st.get("status", "")))
	var hint: String = VALUE_HINT.get(sid, "")
	var t := "%s %d턴" % [StatusCatalog.get_def(sid).name, int(st.get("turns", 1))]
	if hint.ends_with(" %"):
		t += " (%s %d%%)" % [hint.trim_suffix(" %"), int(st.get("value", 0))]
	elif hint != "":
		t += " (%s %d)" % [hint, int(st.get("value", 0))]
	if int(st.get("chance", 100)) < 100:
		t += " · 확률 %d%%" % int(st.get("chance", 100))
	return t


static func check(entries: Array, actions: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var notes := PackedStringArray()
	var seen := {}
	for e in entries:
		if not actions.has(e.skill):
			errors.append("스킬 시트에 없는 스킬 '%s'" % e.skill)
		if not e.status in StatusCatalog.BATTLE:
			errors.append("%s: 모르는 상태 이상 '%s'" % [e.skill, e.status])
			continue
		var key := "%s|%s" % [e.skill, e.status]
		if seen.has(key):
			notes.append("%s: %s 가 두 번 달려 있습니다 (둘 다 굴리고, 걸리면 남은 턴·수치 큰 쪽)" % [e.skill, StatusCatalog.get_def(e.status).name])
		seen[key] = true
		if VALUE_HINT.get(e.status, "") != "" and int(e.value) <= 0:
			notes.append("%s: %s 수치가 0 입니다 (효과 없음)" % [e.skill, StatusCatalog.get_def(e.status).name])
		if int(e.chance) <= 0:
			notes.append("%s: %s 확률 0%% (안 걸림)" % [e.skill, StatusCatalog.get_def(e.status).name])
		var a: ActionData = actions.get(e.skill)
		if a != null and a.effect in ["move", "weapon_swap"]:
			errors.append("%s: 이동·무기 변경에는 상태 이상을 달 수 없습니다" % e.skill)
	return {"errors": errors, "notes": notes}
