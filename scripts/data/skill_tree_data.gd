@tool
class_name SkillTreeData
extends RefCounted
## 스킬 트리 노드 (data/skill_tree.json, Godot 에디터 '스킬 트리' 탭에서 편집).
## 캐릭터마다 액티브 · 패시브 두 개의 십자형 트리: 중앙(0단계, 처음부터 습득) + 북 화력 · 동 기동 · 남 생존 · 서 전술 갈래 1~MAX_TIER 단계.
## 노드 = {id, char, kind(active|passive), dir(center|n|e|s|w), tier, name, level(필요 레벨), effect, value, desc}
## 효과: hp · speed · ap · ap_rec · defense · power(모든 공격 위력) · heal(회복량) +값, skill_power:<스킬 id> = 그 스킬 위력 +값, skill:<스킬 id> = 새 스킬

const PATH := "res://data/skill_tree.json"
const MAX_TIER := 4
## 전투 HUD 기본 스킬 칸 (필살기 제외)
const SKILL_SLOTS := 3
const KINDS := ["active", "passive"]
const KIND_NAME := {"active": "액티브", "passive": "패시브"}
const DIRS := ["center", "n", "e", "s", "w"]
const DIR_NAME := {"center": "중앙", "n": "북 · 화력", "e": "동 · 기동", "s": "남 · 생존", "w": "서 · 전술"}
const DIR_SHORT := {"center": "c", "n": "n", "e": "e", "s": "s", "w": "w"}
## 효과 종류 (에디터 목록 순서)
const EFFECTS := ["hp", "speed", "ap", "ap_rec", "defense", "power", "heal", "skill_power", "skill"]
const EFFECT_NAME := {"hp": "최대 HP", "speed": "속도", "ap": "최대 AP", "ap_rec": "턴마다 AP 회복", "defense": "방어 (받는 피해 -)",
	"power": "모든 공격 위력", "heal": "모든 회복량", "skill_power": "스킬 강화 (그 스킬 위력·회복·AP 지급 +)", "skill": "새 스킬 (전투 스킬 칸에 추가)"}


static func new_node(cid: String, kind: String, dir: String, tier: int) -> Dictionary:
	return {"id": "", "char": cid, "kind": kind, "dir": dir, "tier": 0 if dir == "center" else tier, "name": "새 스킬",
		"level": 1, "effect": "hp" if kind == "passive" else "skill_power:basic_attack", "value": 1, "desc": ""}


static func _norm(r: Dictionary) -> Dictionary:
	var dir := str(r.get("dir", "center"))
	if not dir in DIRS:
		dir = "center"
	var ef := str(r.get("effect", "")).strip_edges()
	var kind := str(r.get("kind", ""))
	if not kind in KINDS:
		kind = "active" if ef.begins_with("skill") else "passive"
	return {"id": str(r.get("id", "")), "char": str(r.get("char", "")), "kind": kind, "dir": dir,
		"tier": 0 if dir == "center" else clampi(int(r.get("tier", 1)), 1, MAX_TIER), "name": str(r.get("name", "")),
		"level": maxi(1, int(r.get("level", 1))), "effect": ef, "value": int(r.get("value", 0)), "desc": str(r.get("desc", ""))}


static func read(path: String = PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (j is Dictionary and j.get("nodes") is Array):
		return []
	var out := []
	for r in j.nodes:
		if r is Dictionary:
			out.append(_norm(r))
	return out


static func write(nodes: Array, path: String = PATH) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version": 1, "nodes": sorted(nodes)}, "\t", false))
	return OK


## 저장 순서: 캐릭터 → 액티브/패시브 → 중앙·북·동·남·서 → 단계
static func sorted(nodes: Array) -> Array:
	var chars := []
	for n in nodes:
		if not chars.has(n.char):
			chars.append(n.char)
	var out := nodes.duplicate()
	out.sort_custom(func(a, b):
		if a.char != b.char:
			return chars.find(a.char) < chars.find(b.char)
		if a.kind != b.kind:
			return KINDS.find(a.kind) < KINDS.find(b.kind)
		if a.dir != b.dir:
			return DIRS.find(a.dir) < DIRS.find(b.dir)
		return int(a.tier) < int(b.tier))
	return out


## 캐릭터 id → [노드] (GameData.skill_tree)
static func by_char(nodes: Array) -> Dictionary:
	var out := {}
	for n in nodes:
		if not out.has(n.char):
			out[n.char] = []
		out[n.char].append(n)
	return out


## 효과 → 자동 설명 (actions = 스킬 id → ActionData)
static func auto_desc(effect: String, value: int, actions: Dictionary) -> String:
	if effect.begins_with("skill:"):
		var a: ActionData = actions.get(effect.substr(6))
		if a == null:
			return "새 스킬: %s" % effect.substr(6)
		var what := "위력 %d" % a.power if a.effect == "damage" else ("회복 %d" % a.power if a.effect == "heal" else "AP +%d" % a.power)
		if a.status_id != "":
			what += ", %s %d턴" % [StatusCatalog.get_def(a.status_id).name, a.status_turns]
		return "새 스킬: %s (AP %d, %s)" % [a.display_name, a.ap_cost, what]
	if effect.begins_with("skill_power:"):
		var b: ActionData = actions.get(effect.substr(12))
		if b == null:
			return "%s +%d" % [effect.substr(12), value]
		var unit := "위력" if b.effect == "damage" else ("회복" if b.effect == "heal" else "AP 지급")
		return "%s %s +%d" % [b.display_name, unit, value]
	match effect:
		"hp": return "최대 HP +%d" % value
		"speed": return "속도 +%d (행동 순서가 빨라짐)" % value
		"ap": return "최대 AP +%d" % value
		"ap_rec": return "턴마다 AP 회복 +%d" % value
		"defense": return "받는 피해 -%d (방어 +%d)" % [value, value]
		"power": return "모든 공격 위력 +%d" % value
		"heal": return "모든 회복량 +%d" % value
	return effect


## 같은 트리 같은 갈래의 가장 깊은 단계
static func branch_end(nodes: Array, cid: String, kind: String, dir: String) -> int:
	var t := 0
	for n in nodes:
		if n.char == cid and n.kind == kind and n.dir == dir:
			t = maxi(t, int(n.tier))
	return t


## 검사: 오류(게임에서 틀어짐) / 주의. allies = [UnitData], actions = 스킬 id → ActionData
static func check(nodes: Array, allies: Array, actions: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var notes := PackedStringArray()
	var ids := {}
	var chars := {}
	for u in allies:
		chars[u.id] = u
	var slot := {}   # "char|kind|dir|tier" → id
	for n in nodes:
		var where := "%s %s %s %d단계" % [n.char, KIND_NAME.get(n.kind, n.kind), DIR_NAME.get(n.dir, n.dir), int(n.tier)]
		if str(n.id) == "":
			errors.append("%s: id 가 비었습니다" % where)
		elif ids.has(n.id):
			errors.append("id '%s' 가 두 번 있습니다" % n.id)
		ids[n.id] = true
		if not chars.has(n.char):
			errors.append("%s: 캐릭터 시트에 없는 캐릭터 '%s'" % [n.id, n.char])
		var key := "%s|%s|%s|%d" % [n.char, n.kind, n.dir, int(n.tier)]
		if slot.has(key):
			errors.append("%s: 같은 칸에 노드가 둘 (%s, %s)" % [where, slot[key], n.id])
		slot[key] = n.id
		var ef: String = n.effect
		if ef.begins_with("skill:") or ef.begins_with("skill_power:"):
			var sid := ef.split(":")[1]
			if not actions.has(sid):
				errors.append("%s: 스킬 시트에 없는 스킬 '%s'" % [n.id, sid])
		elif not ef in EFFECTS:
			errors.append("%s: 모르는 효과 '%s'" % [n.id, ef])
		if str(n.name).strip_edges() == "":
			notes.append("%s: 이름이 비었습니다" % n.id)
	# 갈래: 1단계부터 빈 단계 없이, 필요 레벨은 앞 단계 이상
	for cid in chars:
		var possible_new := 0   # 이 캐릭터가 얻을 수 있는 새 스킬 수 (두 트리 합)
		for kind in KINDS:
			var tree := nodes.filter(func(n): return n.char == cid and n.kind == kind)
			if tree.is_empty():
				continue
			if not tree.any(func(n): return n.dir == "center"):
				notes.append("%s %s: 중앙 노드가 없습니다 (1단계는 바로 배울 수 있음)" % [cid, KIND_NAME[kind]])
			var end_new := false
			for dir in ["n", "e", "s", "w"]:
				var br := tree.filter(func(n): return n.dir == dir)
				br.sort_custom(func(a, b): return int(a.tier) < int(b.tier))
				for i in br.size():
					if int(br[i].tier) != i + 1:
						errors.append("%s %s %s: %d단계가 비었습니다" % [cid, KIND_NAME[kind], DIR_NAME[dir], i + 1])
						break
					if i > 0 and int(br[i].level) < int(br[i - 1].level):
						notes.append("%s: 필요 레벨(%d)이 앞 단계(%d)보다 낮습니다" % [br[i].id, int(br[i].level), int(br[i - 1].level)])
					if str(br[i].effect).begins_with("skill:"):
						if i == br.size() - 1:
							end_new = true
						else:
							possible_new += 1
			if end_new:
				possible_new += 1   # 갈래 끝은 트리마다 하나만
		if possible_new > 0:
			var u: UnitData = chars[cid]
			var base := u.skill_ids.filter(func(s): return actions.has(s) and actions[s].kind != "ultimate").size()
			if base + possible_new > SKILL_SLOTS:
				notes.append("%s: 새 스킬을 %d개까지 얻을 수 있어 기본 스킬 칸(%d칸, 이미 %d개)을 넘을 수 있습니다 — 넘친 스킬은 전투 HUD 에 안 보임" % [
					cid, possible_new, SKILL_SLOTS, base])
	return {"errors": errors, "notes": notes}
