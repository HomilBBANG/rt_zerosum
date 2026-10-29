@tool
class_name MonsterSkillData
extends RefCounted
## 몬스터 스킬 (data/monster_skills.json, Godot 에디터 '스킬 트리' 탭의 '몬스터 스킬' 에서 편집).
## skills = 몬스터 전용 스킬 정의 [{id, name, kind, ap, target, effect, power, accuracy(명중 %), desc}] (형식은 밸런스 엑셀 스킬 시트와 같음)
## kits = 몬스터 id → [스킬 id…] (그 몬스터가 쓰는 스킬, 순서대로). 공용 스킬(기본 공격·강공격·필살기 등 엑셀 스킬 시트)도 넣을 수 있음.
## 상태 이상은 data/skill_status.json (같은 탭 '상태 이상' 또는 몬스터 스킬 화면에서 바로).
## 몬스터 스탯(HP·속도·AI 등)은 밸런스 엑셀 몬스터 시트. AI 가 실제로 쓰려면 그 몬스터 AI 그래프(data/ai)에 그 스킬 노드가 있어야 함.

const PATH := "res://data/monster_skills.json"
const KINDS := {"attack": "공격", "heavy": "강공격류", "support": "지원", "ultimate": "필살기 (필살기 칸)"}
const TARGETS := {"weapon": "무기 사거리 (근접 = 앞열 우선)", "enemy_any": "적 아무나 (열 무관)", "ally_any": "아군 아무나 (자신 포함)",
	"ally_other": "다른 아군", "self": "자신"}
const EFFECTS := {"damage": "피해", "heal": "회복", "ap_grant": "AP 부여", "status": "상태 이상만 (피해 없음)"}


static func new_skill(id: String) -> Dictionary:
	return {"id": id, "name": "새 몬스터 스킬", "kind": "attack", "ap": 2, "target": "weapon", "effect": "damage", "power": 8, "accuracy": 90, "desc": ""}


static func read(path: String = PATH) -> Dictionary:
	var out := {"skills": [], "kits": {}}
	if not FileAccess.file_exists(path):
		return out
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not j is Dictionary:
		return out
	for s in j.get("skills", []):
		if s is Dictionary:
			out.skills.append({"id": str(s.get("id", "")), "name": str(s.get("name", "")), "kind": str(s.get("kind", "attack")),
				"ap": maxi(0, int(s.get("ap", 1))), "target": str(s.get("target", "weapon")), "effect": str(s.get("effect", "damage")),
				"power": int(s.get("power", 0)), "accuracy": int(s.get("accuracy", GameData.default_accuracy(str(s.get("effect", "damage"))))),
				"desc": str(s.get("desc", ""))})
	var k: Variant = j.get("kits", {})
	if k is Dictionary:
		for mid in k:
			out.kits[str(mid)] = (k[mid] as Array).map(func(x): return str(x)) if k[mid] is Array else []
	return out


static func write(d: Dictionary, path: String = PATH) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version": 1, "skills": d.skills, "kits": d.kits}, "\t", false))
	return OK


static func to_action(s: Dictionary) -> ActionData:
	var a := ActionData.new()
	a.id = s.id
	a.display_name = s.name
	a.kind = s.kind
	a.ap_cost = int(s.ap)
	a.target_rule = s.target
	a.effect = s.effect
	a.power = int(s.power)
	a.accuracy = int(s.get("accuracy", GameData.default_accuracy(a.effect)))
	a.description = s.desc
	return a


## 검사. sheet_skills = 엑셀 스킬 시트 id 들, monsters = 몬스터 id → UnitData, ai_uses = 몬스터 id → AI 그래프가 쓰는 스킬 id 목록
static func check(d: Dictionary, sheet_skills: Array, monsters: Dictionary, ai_uses: Dictionary = {}) -> Dictionary:
	var errors := PackedStringArray()
	var notes := PackedStringArray()
	var ids := {}
	for s in d.skills:
		if str(s.id) == "":
			errors.append("id 가 빈 몬스터 스킬이 있습니다")
		elif ids.has(s.id):
			errors.append("몬스터 스킬 id '%s' 가 두 번 있습니다" % s.id)
		elif sheet_skills.has(s.id):
			errors.append("'%s' 는 엑셀 스킬 시트에도 있습니다 (id 를 바꾸세요)" % s.id)
		ids[s.id] = true
		if not KINDS.has(s.kind):
			errors.append("%s: 모르는 종류 '%s'" % [s.id, s.kind])
		if not TARGETS.has(s.target):
			errors.append("%s: 모르는 대상 '%s'" % [s.id, s.target])
		if not EFFECTS.has(s.effect):
			errors.append("%s: 모르는 효과 '%s'" % [s.id, s.effect])
		if s.effect in ["heal", "ap_grant"] and s.target in ["weapon", "enemy_any"]:
			notes.append("%s: %s 인데 대상이 적입니다" % [s.id, EFFECTS[s.effect]])
		if s.effect == "damage" and s.target in ["ally_any", "ally_other", "self"]:
			notes.append("%s: 피해인데 대상이 아군입니다" % s.id)
		if not d.kits.values().any(func(k): return (k as Array).has(s.id)):
			notes.append("%s: 어느 몬스터도 쓰지 않습니다" % s.id)
	for mid in d.kits:
		if not monsters.has(mid):
			errors.append("몬스터 시트에 없는 몬스터 '%s'" % mid)
		for sid in d.kits[mid]:
			if not ids.has(sid) and not sheet_skills.has(sid):
				errors.append("%s: 없는 스킬 '%s'" % [mid, sid])
			elif ai_uses.has(mid) and not (ai_uses[mid] as Array).has(sid):
				notes.append("%s: AI 그래프가 '%s' 를 쓰지 않습니다 ('AI 그래프에 넣기')" % [mid, sid])
	for mid in monsters:
		if not d.kits.has(mid) or (d.kits[mid] as Array).is_empty():
			notes.append("%s: 스킬이 없습니다" % mid)
	return {"errors": errors, "notes": notes}
