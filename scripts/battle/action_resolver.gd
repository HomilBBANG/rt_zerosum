class_name ActionResolver
extends RefCounted
## 행동 해결. 모든 행동은 can_execute → pay_ap → resolve → emit_event 경로를 따른다(컨트롤러에서 호출).


static func compute_damage(action: ActionData, actor: UnitRuntime, target: UnitRuntime, rng: RandomNumberGenerator) -> int:
	var weapon := actor.current_weapon()
	var base: int = action.power + int(weapon.get("power_bonus", 0)) + int(actor.data.level / 2) \
		+ actor.data.power_bonus + int(actor.data.skill_power.get(action.id, 0))
	if not is_equal_approx(actor.data.damage_mult, 1.0):
		base = int(roundf(base * actor.data.damage_mult))
	var variance := rng.randi_range(-1, 1) if rng != null else 0
	return maxi(1, base - target.data.defense + variance)


static func resolve(action: ActionData, actor: UnitRuntime, target: UnitRuntime, rng: RandomNumberGenerator) -> Dictionary:
	var event := {
		"actor": actor, "action": action, "targets": [], "results": [], "text": ""
	}
	match action.effect:
		"damage":
			var dmg := compute_damage(action, actor, target, rng)
			target.hp = maxi(0, target.hp - dmg)
			var killed := target.hp == 0
			if killed:
				target.alive = false
			event.targets = [target]
			event.results = [{"target": target, "kind": "damage", "amount": dmg, "killed": killed}]
			event.text = "%s → %s: %s %d 피해%s" % [
				actor.display_name(), target.display_name(), action.display_name, dmg,
				" (전투 불능)" if killed else ""]
		"heal":
			var amount: int = action.power + int(actor.data.level / 2) + actor.data.heal_bonus + int(actor.data.skill_power.get(action.id, 0))
			var before := target.hp
			target.hp = mini(target.data.max_hp, target.hp + amount)
			var healed := target.hp - before
			event.targets = [target]
			event.results = [{"target": target, "kind": "heal", "amount": healed, "killed": false}]
			event.text = "%s → %s: %s HP %d 회복" % [actor.display_name(), target.display_name(), action.display_name, healed]
		"ap_grant":
			var granted := APComponent.grant(target, action.power + int(actor.data.skill_power.get(action.id, 0)))
			target.add_status("rallied")
			event.targets = [target]
			event.results = [{"target": target, "kind": "ap", "amount": granted, "killed": false}]
			event.text = "%s → %s: %s AP %d 부여" % [actor.display_name(), target.display_name(), action.display_name, granted]
		"status":
			event.targets = [target]
			event.text = "%s → %s: %s" % [actor.display_name(), target.display_name(), action.display_name]
		_:
			event.text = "%s: %s" % [actor.display_name(), action.display_name]
	_apply_status(action, target, rng, event)
	return event


## 스킬의 상태 이상: 맞은 대상이 살아 있으면 하나씩 확률로 걸고 바로 한 번 적용 (event.applied, 틱 피해는 event.results 에 덧붙임)
static func _apply_status(action: ActionData, target: UnitRuntime, rng: RandomNumberGenerator, event: Dictionary) -> void:
	event["applied"] = []
	if action.statuses.is_empty() or target == null or action.effect in ["move", "weapon_swap"]:
		return
	for st in action.statuses:
		if not target.alive:
			return
		var sid := str(st.id)
		var roll := rng.randi_range(1, 100) if rng != null else 1
		var nm: String = StatusCatalog.get_def(sid).name
		if roll > int(st.get("chance", 100)):
			event.text += " (%s 실패)" % nm
			continue
		var ticks := StatusRules.apply(target, sid, int(st.get("turns", 1)), int(st.get("value", 0)))
		event.applied.append({"target": target, "status": sid})
		event.text += " → %s %d턴" % [nm, int(st.get("turns", 1))]
		for r in ticks:
			event.results.append(r)
			event.text += " (%s %d 피해%s)" % [nm, r.amount, ", 전투 불능" if r.killed else ""]
