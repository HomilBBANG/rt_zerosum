class_name EnemyAI
extends RefCounted
## 적 AI (프로토타입): 자기 차례에 가능한 행동을 최대 2회 실행하고 종료.
## 전투 템포 검증용 단순 규칙 — 가장 비싼 유효 공격을 체력이 가장 낮은 대상에게.

const MAX_ACTIONS_PER_TURN := 2


## 반환: {"action": ActionData, "target": UnitRuntime} 또는 빈 Dictionary(턴 종료)
static func decide(actor: UnitRuntime, actions: Dictionary, slots: SlotManager) -> Dictionary:
	if actor.actions_this_turn >= MAX_ACTIONS_PER_TURN:
		return {}
	var candidates: Array[ActionData] = []
	for sid in actor.data.skill_ids:
		var a: ActionData = actions.get(sid, null)
		if a != null and APComponent.can_pay(actor, a.ap_cost):
			candidates.append(a)
	# 지원형: 다친 아군이 있으면 회복 우선
	for a in candidates:
		if a.effect == "heal":
			var best: UnitRuntime = null
			for u in TargetValidator.valid_targets(a, actor, slots):
				if u.hp * 2 < u.data.max_hp and (best == null or u.hp < best.hp):
					best = u
			if best != null:
				return {"action": a, "target": best}
	# 공격: AP 비용 높은 순
	var attacks: Array[ActionData] = []
	for a in candidates:
		if a.effect == "damage":
			attacks.append(a)
	attacks.sort_custom(func(x: ActionData, y: ActionData) -> bool: return x.ap_cost > y.ap_cost)
	for a in attacks:
		var targets := TargetValidator.valid_targets(a, actor, slots)
		if targets.is_empty():
			continue
		# 필살기(4AP)는 한 방에 잡을 수 있을 때만, 아니면 비용 대비 낭비 방지
		if a.kind == "ultimate":
			var kill: UnitRuntime = null
			for t in targets:
				if t.hp <= a.power and (kill == null or t.hp < kill.hp):
					kill = t
			if kill == null:
				continue
			return {"action": a, "target": kill}
		var best: UnitRuntime = targets[0]
		for t in targets:
			if t.hp < best.hp:
				best = t
		return {"action": a, "target": best}
	return {}
