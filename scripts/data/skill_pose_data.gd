@tool
class_name SkillPoseData
extends RefCounted
## 상황별 포즈 그림(캐릭터마다 assets/characters/<id>/<포즈>/0001.png, anim.json "pose": true — tools/char_sprites.py poses)을
## 전투 어느 때 쓰는지 + 스킬마다 쓰는 포즈 (data/skill_poses.json, Godot 에디터 '스킬 트리' 탭 → '스킬 포즈').
## 스킬 포즈 = {"skills": {스킬 id: 포즈}} — 없음/"" = 자동, "none" = 포즈 안 씀(예전 공격 동작).
## 무기별 공격 포즈 = {"weapons": {캐릭터 스프라이트 id: {무기 스프라이트: 포즈}}} — 그 캐릭터가 그 무기를 들고 공격할 때 쓰는 그림 (에디터 '스킬 포즈' 오른쪽 아래).
##   없으면 자동: <포즈>_<무기 스프라이트> 그림(shot_pistol 등)이 있으면 그것, 없으면 shot / slash.
## 자동 (쓰는 쪽): 다른 편에게 쓰는 피해·상태 스킬 = shot (근접 무기를 들고 있으면 slash, 없으면 shot), 그 밖의 스킬(회복·AP·버프·자기 대상) = point_up.
## 맞는 쪽: 피함 = miss · 기절 걸림 = stun · 디버프(부정 상태 이상, 구속 포함) 걸림 = tired · 피해 = hit (앞에 것이 먼저).
## 그 밖: AP 를 다 씀(탈진) = tired · 쓰러짐 = dead · 패배 = annoying (결과 화면).
## 그 캐릭터에게 그 포즈 그림이 없으면 다음 후보(맞는 쪽은 hit), 그것도 없으면 예전 동작. 자리 이동 = move.
## 같은 포즈의 다른 그림 <포즈>_2, _3 … 이 있으면 그때마다 무작위 (UnitSprite2D.pose_variant).
## 무기별 그림 <포즈>_<무기 스프라이트> (예: shot_pistol · slash_knife) 이 있으면 그 무기를 들었을 때 먼저.

const PATH := "res://data/skill_poses.json"
const NONE := "none"
## 알려진 포즈 이름 (에디터 표시 순서) → 이름 · 쓰는 때
const POSES := {
	"shot": {"name": "공격", "when": "적에게 쓰는 피해·상태 스킬 (자동)"},
	"slash": {"name": "근접 공격", "when": "근접 무기로 공격 (자동, 그림이 없으면 shot)"},
	"point_up": {"name": "버프·스킬", "when": "회복·AP·버프 등 그 밖의 스킬 (자동)"},
	"hit": {"name": "피격", "when": "공격에 맞음"},
	"miss": {"name": "회피", "when": "공격을 피함"},
	"stun": {"name": "기절", "when": "기절이 걸림"},
	"tired": {"name": "지침", "when": "디버프·구속이 걸림 · AP 를 다 씀(탈진)"},
	"dead": {"name": "쓰러짐", "when": "쓰러짐 (그대로 남음)"},
	"annoying": {"name": "언짢음", "when": "패배 (결과 화면)"},
	"move": {"name": "자리 이동", "when": "자리 이동 · 자리 교체할 때 (자동)"},
	"awkward": {"name": "머쓱함", "when": "대화용 (전투에서 자동으로 안 씀 — 스킬 포즈로 고를 수는 있음)"},
}
const POSE_ORDER := ["shot", "slash", "point_up", "hit", "miss", "stun", "tired", "dead", "annoying", "move", "awkward"]


## 표시 이름 — 같은 포즈의 다른 그림(hit_2)은 "피격 2"
static func pose_name(p: String) -> String:
	if POSES.has(p):
		return str(POSES[p].name)
	var i := p.rfind("_")
	if i > 0 and POSES.has(p.substr(0, i)):
		var tail := p.substr(i + 1)
		return "%s %s" % [POSES[p.substr(0, i)].name, tail] if tail.is_valid_int() else "%s (%s)" % [POSES[p.substr(0, i)].name, tail]
	return p


static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return j if j is Dictionary else {}


## 스킬 id → 포즈
static func read(path: String = PATH) -> Dictionary:
	var j := _json(path)
	var out := {}
	if j.get("skills") is Dictionary:
		for k in j.skills:
			var v := str(j.skills[k])
			if v != "":
				out[str(k)] = v
	return out


## 캐릭터 스프라이트 id → {무기 스프라이트 → 포즈}
static func read_weapons(path: String = PATH) -> Dictionary:
	var j := _json(path)
	var out := {}
	if j.get("weapons") is Dictionary:
		for cid in j.weapons:
			if j.weapons[cid] is Dictionary:
				var m := {}
				for w in j.weapons[cid]:
					if str(j.weapons[cid][w]) != "":
						m[str(w)] = str(j.weapons[cid][w])
				if not m.is_empty():
					out[str(cid)] = m
	return out


static func write(table: Dictionary, weapons: Dictionary = {}, path: String = PATH) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var keys := table.keys()
	keys.sort()
	var sk := {}
	for k in keys:
		if str(table[k]) != "":
			sk[k] = str(table[k])
	var wp := {}
	var cids := weapons.keys()
	cids.sort()
	for cid in cids:
		var m := {}
		var ws: Array = (weapons[cid] as Dictionary).keys()
		ws.sort()
		for w in ws:
			if str(weapons[cid][w]) != "":
				m[w] = str(weapons[cid][w])
		if not m.is_empty():
			wp[cid] = m
	f.store_string(JSON.stringify({"version": 1, "skills": sk, "weapons": wp}, "\t", false))
	return OK


## 무기 스프라이트 id (아이템 시트 '스프라이트', 없으면 id)
static func weapon_key(actor: UnitRuntime) -> String:
	if actor == null:
		return ""
	var w := actor.current_weapon()
	var ws := str(w.get("sprite", w.get("id", "")))
	return "" if ws == "none" else ws


## 에디터에서 정한 그 캐릭터 · 그 무기의 공격 포즈 ("" = 없음)
static func weapon_pose(actor: UnitRuntime, weapons: Dictionary) -> String:
	if actor == null or weapons.is_empty():
		return ""
	var m: Dictionary = weapons.get(actor.data.sprite_id, {})
	return str(m.get(weapon_key(actor), ""))


## 자동일 때 쓰는 쪽 포즈 후보 (앞에서부터, 그 캐릭터에게 그림이 있는 첫 것)
static func auto_caster(action: ActionData, actor: UnitRuntime, target: UnitRuntime) -> Array:
	if action == null or action.effect in ["move", "weapon_swap"]:
		return []
	if target != null and actor != null and target.team != actor.team and action.effect in ["damage", "status"]:
		return ["shot"] if actor.is_ranged_now() else ["slash", "shot"]
	return ["point_up"]


## 에디터 표시용 자동 포즈 (대상 규칙으로: 적 대상 피해·상태 = shot, 그 밖 point_up)
static func auto_for(action: ActionData) -> String:
	if action == null or action.effect in ["move", "weapon_swap"]:
		return ""
	return "shot" if action.target_rule in ["weapon", "enemy_melee", "enemy_any"] and action.effect in ["damage", "status"] else "point_up"


## 스킬을 쓸 때 쓰는 쪽 포즈 후보 ([] = 포즈 없음 → 예전 공격 동작). 앞에서부터 그림이 있는 첫 것.
##   1 에디터에서 스킬에 정한 포즈 → 2 공격이면 그 캐릭터 · 그 무기에 정한 포즈(weapons) → 3 자동 (<포즈>_<무기> 그림 → shot / slash)
static func caster_poses(action: ActionData, actor: UnitRuntime, target: UnitRuntime, table: Dictionary, weapons: Dictionary = {}) -> Array:
	if action == null:
		return []
	var p := str(table.get(action.id, ""))
	if p == NONE:
		return []
	if p != "":
		return with_weapon([p], actor)
	var cands := auto_caster(action, actor, target)
	var out := []
	if not cands.is_empty() and str(cands[0]) != "point_up":   # 공격일 때만 무기별 포즈
		var wp := weapon_pose(actor, weapons)
		if wp != "":
			out.append(wp)
	out.append_array(with_weapon(cands, actor))
	return out


static func with_weapon(cands: Array, actor: UnitRuntime) -> Array:
	if actor == null:
		return cands
	var w := actor.current_weapon()
	var ws := str(w.get("sprite", w.get("id", "")))
	if ws == "" or ws == "none":
		return cands
	var out := []
	for c in cands:
		out.append("%s_%s" % [c, ws])
		out.append(c)
	return out


## 첫 후보 (테스트·표시용)
static func caster_pose(action: ActionData, actor: UnitRuntime, target: UnitRuntime, table: Dictionary) -> String:
	var c := caster_poses(action, actor, target, table)
	return str(c[0]) if not c.is_empty() else ""


## 맞는 쪽 포즈 후보 (앞에서부터, 그림이 있는 첫 것) — kind = 결과 종류(damage·miss·heal…), effects = 이번에 걸린 상태 효과 id 들
static func target_poses(kind: String, effects: Array) -> Array:
	if kind == "miss":
		return ["miss"]
	var out := []
	if effects.has("stun"):
		out.append("stun")
	for e in effects:
		var d: Dictionary = StatusCatalog.EFFECTS.get(str(e), {})
		if not d.is_empty() and not bool(d.get("positive", false)) and not bool(d.get("instant", false)) and str(e) != "stun":
			out.append("tired")
			break
	if kind == "damage":
		out.append("hit")
	return out


## 검사: 없는 스킬 · 모르는 포즈 이름(그림이 있는 캐릭터가 없음) · 무기별 포즈의 그림이 그 캐릭터에게 없음
static func check(table: Dictionary, actions: Dictionary, known_poses: Array, weapons: Dictionary = {}) -> Dictionary:
	var errors := PackedStringArray()
	var notes := PackedStringArray()
	for sid in table:
		var p := str(table[sid])
		if not actions.has(sid):
			errors.append("스킬 포즈: 없는 스킬 '%s'" % sid)
		elif p != NONE and not known_poses.has(p):
			notes.append("스킬 포즈: %s → '%s' 그림이 있는 캐릭터가 없음 (자동 포즈로)" % [sid, p])
	for cid in weapons:
		var have := CharacterSprite2D.poses(str(cid))
		for w in weapons[cid]:
			var p2 := str(weapons[cid][w])
			if p2 != "" and not have.has(p2):
				errors.append("무기별 포즈: %s · %s → '%s' 그림이 없습니다 (assets/characters/%s/%s/)" % [cid, w, p2, cid, p2])
	return {"errors": errors, "notes": notes}
