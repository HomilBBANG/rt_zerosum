@tool
class_name SkillTreeData
extends RefCounted
## 스킬 트리 노드 (data/skill_tree.json, Godot 에디터 '스킬 트리' 탭에서 편집).
## 캐릭터마다 액티브 · 패시브 두 트리. 모양은 자유 — 노드를 격자 칸(x, y)에 놓고 선행 노드로 잇는다 (캐릭터마다 다른 모양).
## 노드 = {id, char, kind(active|passive), x, y(격자 칸, 0,0 = 가운데, y- = 위), branch(색·갈래 이름), start(처음부터 습득),
##         req[선행 노드 id], req_all(true = 선행을 모두 배워야 / false = 하나라도), group(택일 그룹 — 같은 트리 같은 그룹은 하나만), name, level(필요 레벨), effect, value, desc}
## 효과: hp · speed · ap · ap_rec · defense · power(모든 공격 위력) · heal(회복량) +값, skill_power:<스킬 id> = 그 스킬 위력 +값, skill:<스킬 id> = 새 스킬
## 옛 십자형 파일(dir · tier)은 읽을 때 같은 모양으로 바뀜 (중앙 = 시작 노드, 앞 단계 = 선행, 갈래 끝 = 택일 그룹 '갈래 끝').

const PATH := "res://data/skill_tree.json"
const VERSION := 2
const GRID := 7                       # 칸 범위 -GRID ~ +GRID
## 전투 HUD 기본 스킬 칸 (필살기 제외)
const SKILL_SLOTS := 3
const KINDS := ["active", "passive"]
const KIND_NAME := {"active": "액티브", "passive": "패시브"}
## 갈래(색) — 이름은 보이기만, 규칙에는 안 씀
const BRANCHES := ["core", "fire", "move", "guard", "tactic", "spec"]
const BRANCH_NAME := {"core": "중앙", "fire": "화력", "move": "기동", "guard": "생존", "tactic": "전술", "spec": "특수"}
const BRANCH_COL := {"core": Color(1.0, 0.85, 0.35), "fire": Color(1.0, 0.45, 0.35), "move": Color(0.35, 0.85, 1.0),
	"guard": Color(0.45, 0.95, 0.55), "tactic": Color(0.8, 0.55, 1.0), "spec": Color(1.0, 0.62, 0.25)}
const LEGACY_END_GROUP := "갈래 끝"
## 옛 십자형 → 칸 · 갈래
const _DIR_VEC := {"center": Vector2i.ZERO, "n": Vector2i(0, -1), "e": Vector2i(1, 0), "s": Vector2i(0, 1), "w": Vector2i(-1, 0)}
const _DIR_BRANCH := {"center": "core", "n": "fire", "e": "move", "s": "guard", "w": "tactic"}
## 효과 종류 (에디터 목록 순서)
const EFFECTS := ["hp", "speed", "ap", "ap_rec", "defense", "power", "heal", "skill_power", "skill"]
const EFFECT_NAME := {"hp": "최대 HP", "speed": "속도", "ap": "최대 AP", "ap_rec": "턴마다 AP 회복", "defense": "방어 (받는 피해 -)",
	"power": "모든 공격 위력", "heal": "모든 회복량", "skill_power": "스킬 강화 (그 스킬 위력·회복·AP 지급 +)", "skill": "새 스킬 (전투 스킬 칸에 추가)"}
## 에디터 '모양 틀' — [{x, y, req: [앞 칸 번호], all, start, group, branch}] (번호 = 목록 순서)
const TEMPLATES := {
	"cross": {"name": "십자형 (4갈래 × 3단계)", "cells": [
		{"x": 0, "y": 0, "start": true, "branch": "core"},
		{"x": 0, "y": -1, "req": [0], "branch": "fire"}, {"x": 0, "y": -2, "req": [1], "branch": "fire"}, {"x": 0, "y": -3, "req": [2], "branch": "fire", "group": "갈래 끝"},
		{"x": 1, "y": 0, "req": [0], "branch": "move"}, {"x": 2, "y": 0, "req": [4], "branch": "move"}, {"x": 3, "y": 0, "req": [5], "branch": "move", "group": "갈래 끝"},
		{"x": 0, "y": 1, "req": [0], "branch": "guard"}, {"x": 0, "y": 2, "req": [7], "branch": "guard"}, {"x": 0, "y": 3, "req": [8], "branch": "guard", "group": "갈래 끝"},
		{"x": -1, "y": 0, "req": [0], "branch": "tactic"}, {"x": -2, "y": 0, "req": [10], "branch": "tactic"}, {"x": -3, "y": 0, "req": [11], "branch": "tactic", "group": "갈래 끝"}]},
	"fork": {"name": "두 갈래 (Y자)", "cells": [
		{"x": 0, "y": 2, "start": true, "branch": "core"}, {"x": 0, "y": 1, "req": [0], "branch": "core"},
		{"x": -1, "y": 0, "req": [1], "branch": "fire"}, {"x": -2, "y": -1, "req": [2], "branch": "fire"}, {"x": -2, "y": -2, "req": [3], "branch": "fire", "group": "끝"},
		{"x": 1, "y": 0, "req": [1], "branch": "guard"}, {"x": 2, "y": -1, "req": [5], "branch": "guard"}, {"x": 2, "y": -2, "req": [6], "branch": "guard", "group": "끝"}]},
	"ladder": {"name": "일자 (사다리 6단)", "cells": [
		{"x": 0, "y": 3, "start": true, "branch": "core"}, {"x": 0, "y": 2, "req": [0], "branch": "fire"}, {"x": 0, "y": 1, "req": [1], "branch": "fire"},
		{"x": 0, "y": 0, "req": [2], "branch": "fire"}, {"x": 0, "y": -1, "req": [3], "branch": "fire"}, {"x": 0, "y": -2, "req": [4], "branch": "fire"}, {"x": 0, "y": -3, "req": [5], "branch": "spec"}]},
	"tree3": {"name": "나무 (줄기 + 세 가지)", "cells": [
		{"x": 0, "y": 3, "start": true, "branch": "core"}, {"x": 0, "y": 2, "req": [0], "branch": "core"}, {"x": 0, "y": 1, "req": [1], "branch": "core"},
		{"x": -2, "y": 0, "req": [2], "branch": "fire"}, {"x": -2, "y": -1, "req": [3], "branch": "fire"}, {"x": -2, "y": -2, "req": [4], "branch": "fire", "group": "가지 끝"},
		{"x": 0, "y": 0, "req": [2], "branch": "move"}, {"x": 0, "y": -1, "req": [6], "branch": "move"}, {"x": 0, "y": -2, "req": [7], "branch": "move", "group": "가지 끝"},
		{"x": 2, "y": 0, "req": [2], "branch": "guard"}, {"x": 2, "y": -1, "req": [9], "branch": "guard"}, {"x": 2, "y": -2, "req": [10], "branch": "guard", "group": "가지 끝"}]},
	"diamond": {"name": "그물 (갈라졌다 합류)", "cells": [
		{"x": 0, "y": 3, "start": true, "branch": "core"},
		{"x": -1, "y": 2, "req": [0], "branch": "fire"}, {"x": 1, "y": 2, "req": [0], "branch": "guard"},
		{"x": -1, "y": 1, "req": [1], "branch": "fire"}, {"x": 1, "y": 1, "req": [2], "branch": "guard"},
		{"x": 0, "y": 0, "req": [3, 4], "all": true, "branch": "tactic"},
		{"x": -1, "y": -1, "req": [5], "branch": "spec", "group": "택일"}, {"x": 1, "y": -1, "req": [5], "branch": "spec", "group": "택일"}]},
}
const TEMPLATE_ORDER := ["cross", "fork", "ladder", "tree3", "diamond"]


static func new_node(cid: String, kind: String, x: int = 0, y: int = 0) -> Dictionary:
	return {"id": "", "char": cid, "kind": kind, "x": x, "y": y, "branch": "core" if x == 0 and y == 0 else "fire", "start": false,
		"req": [], "req_all": false, "group": "", "name": "새 스킬", "level": 1,
		"effect": "hp" if kind == "passive" else "skill_power:basic_attack", "value": 1, "desc": ""}


static func _norm(r: Dictionary) -> Dictionary:
	var ef := str(r.get("effect", "")).strip_edges()
	var kind := str(r.get("kind", ""))
	if not kind in KINDS:
		kind = "active" if ef.begins_with("skill") else "passive"
	var br := str(r.get("branch", "core"))
	var req := []
	for q in r.get("req", []):
		if str(q) != "" and not req.has(str(q)):
			req.append(str(q))
	return {"id": str(r.get("id", "")), "char": str(r.get("char", "")), "kind": kind,
		"x": clampi(int(r.get("x", 0)), -GRID, GRID), "y": clampi(int(r.get("y", 0)), -GRID, GRID),
		"branch": br if BRANCH_COL.has(br) else "core", "start": bool(r.get("start", false)),
		"req": req, "req_all": bool(r.get("req_all", false)), "group": str(r.get("group", "")).strip_edges(),
		"name": str(r.get("name", "")), "level": maxi(1, int(r.get("level", 1))), "effect": ef, "value": int(r.get("value", 0)), "desc": str(r.get("desc", ""))}


## 옛 십자형(dir · tier) → 자유 모양 (같은 모양 · 같은 규칙)
static func _from_cross(raw: Array) -> Array:
	var out := []
	var center := {}   # "char|kind" → 중앙 id
	var by_branch := {}   # "char|kind|dir" → {tier: id}
	var end_tier := {}
	for r in raw:
		var dir := str(r.get("dir", "center"))
		if not _DIR_VEC.has(dir):
			dir = "center"
		var t := 0 if dir == "center" else maxi(1, int(r.get("tier", 1)))
		var key := "%s|%s" % [r.get("char", ""), r.get("kind", "")]
		if dir == "center":
			center[key] = str(r.get("id", ""))
		else:
			var bk := key + "|" + dir
			if not by_branch.has(bk):
				by_branch[bk] = {}
			by_branch[bk][t] = str(r.get("id", ""))
			end_tier[bk] = maxi(int(end_tier.get(bk, 0)), t)
	for r in raw:
		var dir := str(r.get("dir", "center"))
		if not _DIR_VEC.has(dir):
			dir = "center"
		var t := 0 if dir == "center" else maxi(1, int(r.get("tier", 1)))
		var key := "%s|%s" % [r.get("char", ""), r.get("kind", "")]
		var v: Vector2i = _DIR_VEC[dir] * t
		var d: Dictionary = r.duplicate()
		d.x = v.x
		d.y = v.y
		d.branch = _DIR_BRANCH[dir]
		d.start = dir == "center"
		d.req = []
		d.group = ""
		if dir != "center":
			var bk := key + "|" + dir
			if t == 1:
				if center.has(key):
					d.req = [center[key]]
			elif (by_branch[bk] as Dictionary).has(t - 1):
				d.req = [by_branch[bk][t - 1]]
			if t == int(end_tier[bk]):
				d.group = LEGACY_END_GROUP
		d.erase("dir")
		d.erase("tier")
		out.append(_norm(d))
	return out


static func read(path: String = PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (j is Dictionary and j.get("nodes") is Array):
		return []
	var raw: Array = (j.nodes as Array).filter(func(r): return r is Dictionary)
	if raw.any(func(r): return r.has("dir") and not r.has("x")):
		return _from_cross(raw)
	var out := []
	for r in raw:
		out.append(_norm(r))
	return out


static func write(nodes: Array, path: String = PATH) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"version": VERSION, "nodes": sorted(nodes)}, "\t", false))
	return OK


## 저장 순서: 캐릭터 → 액티브/패시브 → 시작 노드 → 위에서 아래(y) → 왼쪽에서 오른쪽(x)
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
		if bool(a.start) != bool(b.start):
			return bool(a.start)
		if int(a.y) != int(b.y):
			return int(a.y) < int(b.y)
		return int(a.x) < int(b.x))
	return out


## 캐릭터 id → [노드] (GameData.skill_tree)
static func by_char(nodes: Array) -> Dictionary:
	var out := {}
	for n in nodes:
		if not out.has(n.char):
			out[n.char] = []
		out[n.char].append(n)
	return out


static func tree_of(nodes: Array, cid: String, kind: String) -> Array:
	return nodes.filter(func(n): return n.char == cid and n.kind == kind)


## 트리 노드가 차지하는 칸 범위 (노드가 없으면 0,0 한 칸)
static func bounds(tree: Array) -> Rect2i:
	if tree.is_empty():
		return Rect2i(0, 0, 1, 1)
	var lo := Vector2i(int(tree[0].x), int(tree[0].y))
	var hi := lo
	for n in tree:
		lo = Vector2i(mini(lo.x, int(n.x)), mini(lo.y, int(n.y)))
		hi = Vector2i(maxi(hi.x, int(n.x)), maxi(hi.y, int(n.y)))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## 시작 노드에서 몇 번째 단계인지 (시작 = 0, 선행 없는 노드 = 1). 순환이 있으면 그 노드는 빠짐. 반환 id → 깊이
static func depths(tree: Array) -> Dictionary:
	var by := {}
	for n in tree:
		by[n.id] = n
	var out := {}
	var changed := true
	var guard := 0
	while changed and guard < 200:
		changed = false
		guard += 1
		for n in tree:
			if out.has(n.id):
				continue
			if bool(n.start):
				out[n.id] = 0
				changed = true
				continue
			var reqs: Array = (n.req as Array).filter(func(q): return by.has(q))
			if reqs.is_empty():
				out[n.id] = 1
				changed = true
				continue
			var known := reqs.filter(func(q): return out.has(q))
			if bool(n.req_all) and known.size() == reqs.size():   # 모두 필요 = 가장 깊은 선행 + 1
				var d := 0
				for q in known:
					d = maxi(d, int(out[q]))
				out[n.id] = d + 1
				changed = true
			elif not bool(n.req_all) and not known.is_empty():   # 하나라도 = 가장 얕은 선행 + 1
				var d2 := 999
				for q in known:
					d2 = mini(d2, int(out[q]))
				out[n.id] = d2 + 1
				changed = true
	return out


## 선행 고리(순환)가 있는 노드 id
static func cycles(tree: Array) -> Array:
	var by := {}
	for n in tree:
		by[n.id] = n
	var bad := []
	for n in tree:
		var seen := {}
		var stack: Array = (n.req as Array).duplicate()
		while not stack.is_empty():
			var q := str(stack.pop_back())
			if q == n.id:
				bad.append(n.id)
				break
			if seen.has(q) or not by.has(q):
				continue
			seen[q] = true
			stack.append_array(by[q].req)
	return bad


## 효과 → 자동 설명 (actions = 스킬 id → ActionData)
static func auto_desc(effect: String, value: int, actions: Dictionary) -> String:
	if effect.begins_with("skill:"):
		var a: ActionData = actions.get(effect.substr(6))
		if a == null:
			return "새 스킬: %s" % effect.substr(6)
		var what := "위력 %d" % a.power if a.effect == "damage" else ("회복 %d" % a.power if a.effect == "heal" else "AP +%d" % a.power)
		for st in a.statuses:
			what += ", %s %d턴" % [StatusCatalog.get_def(str(st.id)).name, int(st.turns)]
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


## 검사: 오류(게임에서 틀어짐) / 주의. allies = [UnitData], actions = 스킬 id → ActionData
static func check(nodes: Array, allies: Array, actions: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var notes := PackedStringArray()
	var ids := {}
	var chars := {}
	for u in allies:
		chars[u.id] = u
	var cell := {}   # "char|kind|x|y" → id
	var by := {}
	for n in nodes:
		by[n.id] = n
	for n in nodes:
		if str(n.id) == "":
			errors.append("%s %s (%d,%d): id 가 비었습니다" % [n.char, KIND_NAME.get(n.kind, n.kind), int(n.x), int(n.y)])
		elif ids.has(n.id):
			errors.append("id '%s' 가 두 번 있습니다" % n.id)
		ids[n.id] = true
		if not chars.has(n.char):
			errors.append("%s: 캐릭터 시트에 없는 캐릭터 '%s'" % [n.id, n.char])
		var key := "%s|%s|%d|%d" % [n.char, n.kind, int(n.x), int(n.y)]
		if cell.has(key):
			errors.append("%s: 같은 칸(%d,%d)에 노드가 둘 (%s)" % [n.id, int(n.x), int(n.y), cell[key]])
		cell[key] = n.id
		var ef: String = n.effect
		if ef.begins_with("skill:") or ef.begins_with("skill_power:"):
			var sid := ef.split(":")[1]
			if not actions.has(sid):
				errors.append("%s: 스킬 시트에 없는 스킬 '%s'" % [n.id, sid])
		elif not ef in EFFECTS:
			errors.append("%s: 모르는 효과 '%s'" % [n.id, ef])
		if str(n.name).strip_edges() == "":
			notes.append("%s: 이름이 비었습니다" % n.id)
		for q in n.req:
			if q == n.id:
				errors.append("%s: 자기 자신이 선행" % n.id)
			elif not by.has(q):
				errors.append("%s: 없는 선행 노드 '%s'" % [n.id, q])
			elif by[q].char != n.char or by[q].kind != n.kind:
				errors.append("%s: 선행 '%s' 가 다른 트리에 있습니다" % [n.id, q])
			elif int(n.level) < int(by[q].level):
				notes.append("%s: 필요 레벨(%d)이 선행 %s(%d)보다 낮습니다" % [n.id, int(n.level), q, int(by[q].level)])
		if bool(n.start) and not (n.req as Array).is_empty():
			notes.append("%s: 시작 노드는 처음부터 배운 상태라 선행이 무시됩니다" % n.id)
	for cid in chars:
		var possible_new := 0   # 이 캐릭터가 얻을 수 있는 새 스킬 수 (두 트리 합, 택일 그룹은 하나로)
		for kind in KINDS:
			var tree := tree_of(nodes, cid, kind)
			if tree.is_empty():
				continue
			for bad in cycles(tree):
				errors.append("%s: 선행이 돌고 돕니다 (배울 수 없음)" % bad)
			if not tree.any(func(n): return bool(n.start)):
				notes.append("%s %s: 시작 노드가 없습니다 (선행 없는 노드는 바로 배울 수 있음)" % [cid, KIND_NAME[kind]])
			var groups := {}
			for n in tree:
				if str(n.group) != "":
					groups[n.group] = int(groups.get(n.group, 0)) + 1
			for g in groups:
				if int(groups[g]) < 2:
					notes.append("%s %s: 택일 그룹 '%s' 에 노드가 하나뿐 (택일이 안 됨)" % [cid, KIND_NAME[kind], g])
			var grp_new := {}
			for n in tree:
				if str(n.effect).begins_with("skill:") and not bool(n.start):
					if str(n.group) != "":
						grp_new[n.group] = true
					else:
						possible_new += 1
			possible_new += grp_new.size()
		if possible_new > 0:
			var u: UnitData = chars[cid]
			var base := u.skill_ids.filter(func(s): return actions.has(s) and actions[s].kind != "ultimate").size()
			if base + possible_new > SKILL_SLOTS:
				notes.append("%s: 새 스킬을 %d개까지 얻을 수 있어 기본 스킬 칸(%d칸, 이미 %d개)을 넘을 수 있습니다 — 넘친 스킬은 전투 HUD 에 안 보임" % [
					cid, possible_new, SKILL_SLOTS, base])
	return {"errors": errors, "notes": notes}
