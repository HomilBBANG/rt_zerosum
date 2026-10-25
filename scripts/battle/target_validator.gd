class_name TargetValidator
extends RefCounted
## 대상 유효성 (GDD 3절 위치 제한 첫 버전).
## 근접: 상대 전방 우선, 전방이 비면 다음 열. 원거리: 어느 열이나. 지원: 아군 전 열.
## 두 칸(전방+중앙) 큰 몸집은 두 열 모두에 있는 것으로 본다 → 살아 있는 동안 전방을 막는다.


static func enemy_team_of(team: String) -> String:
	return "enemy" if team == "ally" else "ally"


static func effective_rule(action: ActionData, actor: UnitRuntime) -> String:
	if action.target_rule == "weapon":
		return "enemy_any" if actor.is_ranged_now() else "enemy_melee"
	return action.target_rule


## 근접 공격이 닿는 열(가장 앞의 생존 열)
static func melee_reachable_row(actor: UnitRuntime, slots: SlotManager) -> int:
	var enemy := enemy_team_of(actor.team)
	for r in SlotManager.ROWS:
		if not slots.units_in_row(enemy, r).is_empty():
			return r
	return -1


static func valid_targets(action: ActionData, actor: UnitRuntime, slots: SlotManager) -> Array[UnitRuntime]:
	var out: Array[UnitRuntime] = []
	var rule := effective_rule(action, actor)
	match rule:
		"enemy_melee":
			var r := melee_reachable_row(actor, slots)
			if r >= 0:
				out = slots.units_in_row(enemy_team_of(actor.team), r)
		"enemy_any":
			out = slots.living_units(enemy_team_of(actor.team))
		"ally_any":
			out = slots.living_units(actor.team)
		"ally_other":
			for u in slots.living_units(actor.team):
				if u != actor:
					out.append(u)
		"self":
			out = [actor]
	return out


## "" 이면 유효. 아니면 툴팁용 사유.
static func block_reason(action: ActionData, actor: UnitRuntime, target: UnitRuntime, slots: SlotManager) -> String:
	if target == null:
		return "대상이 없습니다."
	if not target.alive:
		return "이미 전투 불능입니다."
	var rule := effective_rule(action, actor)
	var enemy := enemy_team_of(actor.team)
	match rule:
		"enemy_melee":
			if target.team != enemy:
				return "적만 공격할 수 있습니다."
			var r := melee_reachable_row(actor, slots)
			if not target.occupies_row(r):
				return "근접 무기는 %s열 적만 공격할 수 있습니다. (앞열 먼저)" % SlotManager.ROW_NAMES[r]
		"enemy_any":
			if target.team != enemy:
				return "적만 공격할 수 있습니다."
		"ally_any":
			if target.team != actor.team:
				return "아군만 대상으로 할 수 있습니다."
		"ally_other":
			if target.team != actor.team:
				return "아군만 대상으로 할 수 있습니다."
			if target == actor:
				return "자신에게는 사용할 수 없습니다."
		"self":
			if target != actor:
				return "자신에게만 사용할 수 있습니다."
	return ""
