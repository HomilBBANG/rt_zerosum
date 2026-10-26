class_name AIGraph
extends RefCounted
## 노드 그래프 AI (AI 에디터로 만든 data/ai/<id>.json 을 실행).
## 시작 노드에서 출력 연결을 따라가며: 조건 노드는 예(0)/아니오(1), 스킬 노드는 성공하면 그 행동을 반환하고
## 실패(AP 부족·대상 없음·스킬 없음)면 "실패 시"(0) 로, 턴 종료 노드나 연결 없는 출력은 턴 종료.
## 행동 하나를 실행할 때마다 처음(시작)부터 다시 평가한다.

const AI_DIR := "res://data/ai"

## 노드 종류: title, kind(start/cond/act), params[{key,label,type(int/pct/skill/target),default}], outputs(출력 이름)
const TYPES := {
	"start": {"title": "시작", "kind": "start", "params": [], "outputs": ["다음"]},
	"cond_actions_lt": {"title": "이번 턴 행동 수 < N", "kind": "cond", "params": [{"key": "n", "label": "N", "type": "int", "default": 2}], "outputs": ["예", "아니오"]},
	"cond_ap_gte": {"title": "내 AP ≥ N", "kind": "cond", "params": [{"key": "n", "label": "N", "type": "int", "default": 2}], "outputs": ["예", "아니오"]},
	"cond_self_hp_lte": {"title": "내 HP ≤ N%", "kind": "cond", "params": [{"key": "pct", "label": "N%", "type": "pct", "default": 50}], "outputs": ["예", "아니오"]},
	"cond_ally_hp_lte": {"title": "우리 편 중 HP ≤ N% 있음", "kind": "cond", "params": [{"key": "pct", "label": "N%", "type": "pct", "default": 50}], "outputs": ["예", "아니오"]},
	"cond_foe_count_lte": {"title": "상대 생존 수 ≤ N", "kind": "cond", "params": [{"key": "n", "label": "N", "type": "int", "default": 2}], "outputs": ["예", "아니오"]},
	"cond_can_use": {"title": "스킬 사용 가능", "kind": "cond", "params": [{"key": "skill", "label": "스킬", "type": "skill", "default": "basic_attack"}], "outputs": ["예", "아니오"]},
	"cond_can_kill": {"title": "스킬로 처치 가능한 대상 있음", "kind": "cond", "params": [{"key": "skill", "label": "스킬", "type": "skill", "default": "ultimate"}], "outputs": ["예", "아니오"]},
	"cond_random": {"title": "확률 N%", "kind": "cond", "params": [{"key": "pct", "label": "N%", "type": "pct", "default": 50}], "outputs": ["예", "아니오"]},
	"act_skill": {"title": "스킬 사용", "kind": "act", "params": [
		{"key": "skill", "label": "스킬", "type": "skill", "default": "basic_attack"},
		{"key": "target", "label": "대상", "type": "target", "default": "hp_low"}], "outputs": ["실패 시"]},
	"act_end": {"title": "턴 종료", "kind": "act", "params": [], "outputs": []},
}

## 대상 고르기 규칙
const TARGETS := {
	"hp_low": "HP 가장 낮은",
	"hp_pct_low": "HP 비율 가장 낮은",
	"hp_high": "HP 가장 높은",
	"kill": "처치 가능한 (HP 낮은 순)",
	"front": "가장 앞 열",
	"random": "무작위",
}

static var _cache: Dictionary = {}   # id → {mtime, graph}


static func path_of(id: String) -> String:
	return "%s/%s.json" % [AI_DIR, id]


static func list_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	var d := DirAccess.open(AI_DIR)
	if d != null:
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(f.get_basename())
	out.sort()
	return out


## 그래프 읽기 (파일이 바뀌면 다시 읽음 → AI 에디터에서 저장하면 실행 중인 게임에 바로 반영)
static func load_graph(id: String) -> Dictionary:
	var p := path_of(id)
	var mt := FileAccess.get_modified_time(p)
	if _cache.has(id) and _cache[id].mtime == mt:
		return _cache[id].graph
	var g := {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f != null:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			g = j
	_cache[id] = {"mtime": mt, "graph": g}
	return g


static func save_graph(id: String, g: Dictionary) -> Error:
	DirAccess.make_dir_recursive_absolute(AI_DIR)
	var f := FileAccess.open(path_of(id), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(g, "\t"))
	f.close()
	_cache.erase(id)
	return OK


## 그래프 실행 → {"action", "target"} 또는 {} (턴 종료). 그래프가 비면 null (호출 측이 기본 AI 사용)
static func decide(g: Dictionary, actor: UnitRuntime, actions: Dictionary, slots: SlotManager, rng: RandomNumberGenerator) -> Variant:
	var nodes := {}
	var start := ""
	for n in g.get("nodes", []):
		nodes[str(n.id)] = n
		if n.type == "start":
			start = str(n.id)
	if start == "":
		return null
	var links := {}   # "from:port" → to
	for c in g.get("connections", []):
		links["%s:%d" % [c.from, int(c.port)]] = str(c.to)
	var cur := start
	for _step in 64:
		var n: Dictionary = nodes.get(cur, {})
		if n.is_empty():
			return {}
		var p: Dictionary = n.get("params", {})
		var port := 0
		match str(n.type):
			"start":
				port = 0
			"act_end":
				return {}
			"act_skill":
				var r := _try_skill(str(p.get("skill", "")), str(p.get("target", "hp_low")), actor, actions, slots, rng)
				if not r.is_empty():
					return r
				port = 0
			_:
				port = 0 if _cond(str(n.type), p, actor, actions, slots, rng) else 1
		var key := "%s:%d" % [cur, port]
		if not links.has(key):
			return {}
		cur = links[key]
	return {}


static func _cond(t: String, p: Dictionary, actor: UnitRuntime, actions: Dictionary, slots: SlotManager, rng: RandomNumberGenerator) -> bool:
	match t:
		"cond_actions_lt":
			return actor.actions_this_turn < int(p.get("n", 2))
		"cond_ap_gte":
			return actor.ap >= int(p.get("n", 2))
		"cond_self_hp_lte":
			return actor.hp * 100 <= actor.data.max_hp * int(p.get("pct", 50))
		"cond_ally_hp_lte":
			for u in slots.living_units(actor.team):
				if u.hp * 100 <= u.data.max_hp * int(p.get("pct", 50)):
					return true
			return false
		"cond_foe_count_lte":
			return slots.living_units(TargetValidator.enemy_team_of(actor.team)).size() <= int(p.get("n", 2))
		"cond_can_use":
			return not _usable_targets(str(p.get("skill", "")), actor, actions, slots).is_empty()
		"cond_can_kill":
			var a: ActionData = actions.get(str(p.get("skill", "")), null)
			for t2 in _usable_targets(str(p.get("skill", "")), actor, actions, slots):
				if a.effect == "damage" and t2.team != actor.team and t2.hp <= ActionResolver.compute_damage(a, actor, t2, null):
					return true
			return false
		"cond_random":
			return (rng.randi() % 100 if rng != null else 0) < int(p.get("pct", 50))
	return false


## 이 유닛이 가진 스킬이고 AP 가 되며 유효한 대상이 있으면 그 대상들
static func _usable_targets(skill: String, actor: UnitRuntime, actions: Dictionary, slots: SlotManager) -> Array[UnitRuntime]:
	var none: Array[UnitRuntime] = []
	var a: ActionData = actions.get(skill, null)
	if a == null or not actor.data.skill_ids.has(skill) or not APComponent.can_pay(actor, a.ap_cost):
		return none
	return TargetValidator.valid_targets(a, actor, slots)


static func _try_skill(skill: String, rule: String, actor: UnitRuntime, actions: Dictionary, slots: SlotManager, rng: RandomNumberGenerator) -> Dictionary:
	var targets := _usable_targets(skill, actor, actions, slots)
	if targets.is_empty():
		return {}
	var a: ActionData = actions[skill]
	var best: UnitRuntime = null
	match rule:
		"kill":
			for t in targets:
				if t.hp <= ActionResolver.compute_damage(a, actor, t, null) and (best == null or t.hp < best.hp):
					best = t
			if best == null:
				return {}   # 처치 가능한 대상이 없으면 실패
		"hp_high":
			for t in targets:
				if best == null or t.hp > best.hp:
					best = t
		"hp_pct_low":
			for t in targets:
				if best == null or float(t.hp) / t.data.max_hp < float(best.hp) / best.data.max_hp:
					best = t
		"front":
			for t in targets:
				if best == null or t.row < best.row or (t.row == best.row and t.hp < best.hp):
					best = t
		"random":
			best = targets[(rng.randi() % targets.size()) if rng != null else 0]
		_:
			for t in targets:
				if best == null or t.hp < best.hp:
					best = t
	return {"action": a, "target": best}
