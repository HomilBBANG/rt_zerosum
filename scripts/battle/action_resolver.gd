class_name ActionResolver
extends RefCounted
## 행동 해결. 모든 행동은 can_execute → pay_ap → resolve → emit_event 경로를 따른다(컨트롤러에서 호출).


static func compute_damage(action: ActionData, actor: UnitRuntime, target: UnitRuntime, rng: RandomNumberGenerator) -> int:
	var weapon := actor.current_weapon()
	var base: int = action.power + int(weapon.get("power_bonus", 0)) + int(actor.data.level / 2)
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
			var amount: int = action.power + int(actor.data.level / 2)
			var before := target.hp
			target.hp = mini(target.data.max_hp, target.hp + amount)
			var healed := target.hp - before
			event.targets = [target]
			event.results = [{"target": target, "kind": "heal", "amount": healed, "killed": false}]
			event.text = "%s → %s: %s HP %d 회복" % [actor.display_name(), target.display_name(), action.display_name, healed]
		"ap_grant":
			var granted := APComponent.grant(target, action.power)
			target.add_status("rallied")
			event.targets = [target]
			event.results = [{"target": target, "kind": "ap", "amount": granted, "killed": false}]
			event.text = "%s → %s: %s AP %d 부여" % [actor.display_name(), target.display_name(), action.display_name, granted]
		_:
			event.text = "%s: %s" % [actor.display_name(), action.display_name]
	return event
