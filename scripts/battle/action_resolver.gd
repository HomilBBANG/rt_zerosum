class_name ActionResolver
extends RefCounted
## 행동 해결. 모든 행동은 can_execute → pay_ap → resolve → emit_event 경로를 따른다(컨트롤러에서 호출).


static func compute_damage(action: ActionData, actor: UnitRuntime, target: UnitRuntime, rng: RandomNumberGenerator) -> int:
	var weapon := actor.current_weapon()
	var base: int = action.power + int(weapon.get("power_bonus", 0)) + int(actor.data.level / 2) \
		+ actor.data.power_bonus + int(actor.data.skill_power.get(action.id, 0))
	if not is_equal_approx(actor.data.damage_mult, 1.0):
		base = int(roundf(base * actor.data.damage_mult))
	var mark := target.effect_value("mark")   # 표식: 이 대상을 노리는 공격 위력 +value%
	if mark != 0:
		base = int(roundf(base * (100 + mark) / 100.0))
	var variance := rng.randi_range(-1, 1) if rng != null else 0
	return maxi(1, base - target.data.defense + variance)


const HIT_MIN := 5
const HIT_MAX := 100


## 명중을 굴리는 행동인가: 적에게 쓰는 공격 · 상태 스킬 (회복·AP 지급·자기·이동은 늘 성공)
static func rolls_hit(action: ActionData, actor: UnitRuntime, target: UnitRuntime) -> bool:
	return target != null and actor != null and target.team != actor.team and action.effect in ["damage", "status"]


## 명중률 (%) = 스킬 명중 + 쓰는 쪽 명중 보너스 - 맞는 쪽 회피 (5~100). 굴리지 않는 행동은 100
static func hit_chance(action: ActionData, actor: UnitRuntime, target: UnitRuntime) -> int:
	if not rolls_hit(action, actor, target):
		return 100
	return clampi(action.accuracy + actor.accuracy_now() - target.evasion_now(), HIT_MIN, HIT_MAX)


static func resolve(action: ActionData, actor: UnitRuntime, target: UnitRuntime, rng: RandomNumberGenerator) -> Dictionary:
	var event := {
		"actor": actor, "action": action, "targets": [], "results": [], "text": "", "hit": true, "hit_chance": 100
	}
	# 명중 굴림 (100% 면 굴리지 않음 → 난수 순서가 그대로)
	var chance := hit_chance(action, actor, target)
	event.hit_chance = chance
	if chance < 100:
		var roll := rng.randi_range(1, 100) if rng != null else 1
		if roll > chance:
			event.hit = false
			event.targets = [target]
			event.results = [{"target": target, "kind": "miss", "amount": 0, "killed": false, "chance": chance}]
			event.applied = []
			event.text = "%s → %s: %s — 빗나감 (명중 %d%%)" % [actor.display_name(), target.display_name(), action.display_name, chance]
			return event
	match action.effect:
		"damage":
			var dr := StatusRules.deal(target, compute_damage(action, actor, target, rng))   # 취약·보호막 반영
			event.targets = [target]
			event.results = [{"target": target, "kind": "damage", "amount": dr.amount, "absorbed": dr.absorbed, "killed": dr.killed}]
			event.text = "%s → %s: %s %d 피해%s%s" % [
				actor.display_name(), target.display_name(), action.display_name, dr.amount,
				" (보호막 %d 막음)" % dr.absorbed if dr.absorbed > 0 else "", " (전투 불능)" if dr.killed else ""]
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


## 스킬의 상태 이상: 맞은 대상이 살아 있으면 하나씩 확률로 걸고 바로 한 번 적용 (event.applied, 틱 피해·회복은 event.results 에 덧붙임).
## 넉백·끌어당김은 event.applied 만 — 자리는 컨트롤러가 옮김
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
		event.applied.append({"target": target, "status": sid, "value": int(st.get("value", 0))})
		event.text += (" → %s" % nm) if StatusCatalog.is_instant(sid) else (" → %s %d턴" % [nm, int(st.get("turns", 1))])
		for r in ticks:
			event.results.append(r)
			if r.kind == "heal":
				event.text += " (%s HP %d 회복)" % [nm, r.amount]
			else:
				event.text += " (%s %d 피해%s)" % [nm, r.amount, ", 전투 불능" if r.killed else ""]
