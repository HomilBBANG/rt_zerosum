class_name StatusRules
extends RefCounted
## 전투 상태 이상 적용 (규칙 설명은 StatusCatalog 맨 위).
## 결과 = 행동 결과와 같은 모양 [{target, kind: "damage", amount, killed, status}] → HUD 숫자·피격 연출이 그대로 씀.


## 스킬로 상태 이상을 거는 순간: 걸고, 바로 한 번 적용 (출혈·화상 피해). 반환 = 결과 목록
static func apply(target: UnitRuntime, sid: String, turns: int, value: int) -> Array:
	if not target.alive or sid == "":
		return []
	target.add_status(sid, maxi(1, turns), value)
	match sid:
		"bleed", "burn":
			return [_damage(target, sid)]
	return []


## 그 유닛의 차례가 시작할 때 (행동보다 먼저). 반환 {results, skip(기절), texts}
static func turn_start(u: UnitRuntime) -> Dictionary:
	var out := {"results": [], "skip": false, "texts": PackedStringArray()}
	for sid in u.statuses.duplicate():
		if not u.alive:
			break
		var info: Dictionary = u.status_info.get(sid, {})
		match sid:
			"bleed", "burn":
				var r := _damage(u, sid)
				out.results.append(r)
				out.texts.append("%s: %s %d 피해%s" % [u.display_name(), StatusCatalog.get_def(sid).name, r.amount, " (전투 불능)" if r.killed else ""])
			"frost":
				info.turns = int(info.get("turns", 1)) - 1
				if int(info.turns) <= 0:
					var r2 := _damage(u, sid)
					out.results.append(r2)
					out.texts.append("%s: 동상이 터짐 — %d 피해%s, 동상 풀림" % [u.display_name(), r2.amount, " (전투 불능)" if r2.killed else ""])
					u.remove_status(sid)
			"stun":
				out.skip = true
	if out.skip and u.alive:
		out.texts.append("%s: 기절 — 이번 차례 행동 불가" % u.display_name())
	return out


## 그 유닛의 차례가 끝날 때: 지속 턴 1 줄이고 0 이면 풀림 (동상은 turn_start 에서 셈). 반환 = 풀린 상태 id
static func turn_end(u: UnitRuntime) -> Array:
	var gone := []
	for sid in u.statuses.duplicate():
		if not StatusCatalog.get_def(sid).get("battle", false) or sid == "frost":
			continue
		var info: Dictionary = u.status_info.get(sid, {})
		info.turns = int(info.get("turns", 1)) - 1
		if int(info.turns) <= 0:
			u.remove_status(sid)
			gone.append(sid)
	return gone


## 출혈·동상 = 최대 HP 의 value% (올림, 최소 1) / 화상 = 고정 value (방어 무시)
static func tick_amount(u: UnitRuntime, sid: String) -> int:
	var v := int(u.status_info.get(sid, {}).get("value", 0))
	if sid == "burn":
		return maxi(1, v)
	return maxi(1, ceili(u.data.max_hp * v / 100.0))


static func _damage(u: UnitRuntime, sid: String) -> Dictionary:
	var dmg := tick_amount(u, sid)
	u.hp = maxi(0, u.hp - dmg)
	var killed := u.hp == 0
	if killed:
		u.alive = false
	return {"target": u, "kind": "damage", "amount": dmg, "killed": killed, "status": sid,
		"element": str(StatusCatalog.get_def(sid).get("element", ""))}


## 실명: 원래 대상 대신 같은 규칙의 유효 대상 중 무작위 (아군 대상 스킬 → 아군 중, 적 대상 → 적 중)
static func blind_target(action: ActionData, actor: UnitRuntime, target: UnitRuntime, slots: SlotManager, rng: RandomNumberGenerator) -> UnitRuntime:
	if not actor.statuses.has("blind") or target == null:
		return target
	var rule := TargetValidator.effective_rule(action, actor)
	if rule in ["self", "slot", "none"]:
		return target
	var pool := TargetValidator.valid_targets(action, actor, slots)
	if pool.is_empty():
		return target
	return pool[rng.randi_range(0, pool.size() - 1)] if rng != null else pool[0]
