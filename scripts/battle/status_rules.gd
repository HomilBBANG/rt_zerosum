class_name StatusRules
extends RefCounted
## 전투 상태 이상 적용 (규칙 설명은 StatusCatalog 맨 위). 규칙은 상태 이름이 아니라 상태가 쓰는 효과(StatusCatalog.effect_of)로 정함.
## 결과 = 행동 결과와 같은 모양 [{target, kind: "damage"|"heal", amount, killed, status}] → HUD 숫자·피격 연출이 그대로 씀.


## 스킬로 상태 이상을 거는 순간: 걸고, 바로 한 번 적용 (출혈·화상 피해, 재생 회복). 반환 = 결과 목록.
## 넉백·끌어당김(instant)은 상태로 남지 않음 — 자리는 컨트롤러가 displace 로 옮김
static func apply(target: UnitRuntime, sid: String, turns: int, value: int) -> Array:
	if not target.alive or sid == "" or StatusCatalog.is_instant(sid):
		return []
	target.add_status(sid, maxi(1, turns), value)
	match StatusCatalog.effect_of(sid):
		"bleed", "burn":
			return [_damage(target, sid)]
		"regen":
			return [_heal(target, sid)]
	return []


## 그 유닛의 차례가 시작할 때 (행동보다 먼저). 반환 {results, skip(기절), texts}
static func turn_start(u: UnitRuntime) -> Dictionary:
	var out := {"results": [], "skip": false, "texts": PackedStringArray()}
	for sid in u.statuses.duplicate():
		if not u.alive:
			break
		var info: Dictionary = u.status_info.get(sid, {})
		var nm: String = StatusCatalog.get_def(sid).name
		match StatusCatalog.effect_of(sid):
			"bleed", "burn":
				var r := _damage(u, sid)
				out.results.append(r)
				out.texts.append("%s: %s %d 피해%s%s" % [u.display_name(), nm, r.amount, _absorb_text(r), " (전투 불능)" if r.killed else ""])
			"regen":
				var h := _heal(u, sid)
				out.results.append(h)
				out.texts.append("%s: %s HP %d 회복" % [u.display_name(), nm, h.amount])
			"frost":
				info.turns = int(info.get("turns", 1)) - 1
				if int(info.turns) <= 0:
					var r2 := _damage(u, sid)
					out.results.append(r2)
					out.texts.append("%s: %s 터짐 — %d 피해%s%s, 풀림" % [u.display_name(), nm, r2.amount, _absorb_text(r2), " (전투 불능)" if r2.killed else ""])
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
		if not StatusCatalog.get_def(sid).get("battle", false) or StatusCatalog.effect_of(sid) == "frost":
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
	if StatusCatalog.effect_of(sid) == "burn":
		return maxi(1, v)
	return maxi(1, ceili(u.data.max_hp * v / 100.0))


## 피해 받기 (공격·상태 이상 공용): 취약 = 받는 피해 +value% (올림) → 보호막이 먼저 막음(걸린 순서대로, 다 막은 보호막은 사라짐) → 남은 만큼 HP.
## 반환 {amount(HP 가 준 양), absorbed(보호막이 막은 양), killed}
static func deal(u: UnitRuntime, dmg: int) -> Dictionary:
	var vul := u.effect_value("vulnerable")
	if vul != 0:
		dmg = maxi(0, ceili(dmg * (100 + vul) / 100.0))
	var absorbed := 0
	for sid in u.statuses_with("shield"):
		if dmg <= 0:
			break
		var info: Dictionary = u.status_info.get(sid, {})
		var take := mini(dmg, int(info.get("value", 0)))
		info.value = int(info.get("value", 0)) - take
		dmg -= take
		absorbed += take
		if int(info.value) <= 0:
			u.remove_status(sid)
	u.hp = maxi(0, u.hp - dmg)
	if u.hp == 0:
		u.alive = false
	return {"amount": dmg, "absorbed": absorbed, "killed": u.hp == 0}


static func _damage(u: UnitRuntime, sid: String) -> Dictionary:
	var r := deal(u, tick_amount(u, sid))
	return {"target": u, "kind": "damage", "amount": r.amount, "absorbed": r.absorbed, "killed": r.killed, "status": sid,
		"element": str(StatusCatalog.get_def(sid).get("element", ""))}


## 재생: 최대 HP 의 value% (올림, 최소 1), 최대 HP 까지
static func _heal(u: UnitRuntime, sid: String) -> Dictionary:
	var v := int(u.status_info.get(sid, {}).get("value", 0))
	var before := u.hp
	u.hp = mini(u.data.max_hp, u.hp + maxi(1, ceili(u.data.max_hp * v / 100.0)))
	return {"target": u, "kind": "heal", "amount": u.hp - before, "killed": false, "status": sid}


static func _absorb_text(r: Dictionary) -> String:
	return " (보호막 %d 막음)" % int(r.absorbed) if int(r.get("absorbed", 0)) > 0 else ""


## 넉백(뒤로) · 끌어당김(앞으로) value 칸. 그 칸에 같은 편이 있으면 자리를 바꿈.
## 반환 {ok, kind: "move"|"swap", from, to, other, reason}
static func displace(u: UnitRuntime, sid: String, value: int, slots: SlotManager) -> Dictionary:
	var back := StatusCatalog.effect_of(sid) == "knockback"
	var nm: String = StatusCatalog.get_def(sid).name
	if not u.alive:
		return {"ok": false, "reason": ""}
	if not u.can_be_moved():
		return {"ok": false, "reason": "%s: %s 안 됨 (구속·부상·큰 몸집)" % [u.display_name(), nm]}
	var to_row := clampi(u.row + (maxi(1, value) if back else -maxi(1, value)), 0, SlotManager.ROWS - 1)
	if to_row == u.row:
		return {"ok": false, "reason": "%s: %s 안 됨 (%s 열)" % [u.display_name(), nm, "맨 뒤" if back else "맨 앞"]}
	var key := SlotManager.make_key(u.team, to_row, u.index)
	var from := u.slot_key()
	var res := slots.move_or_swap(u, key)
	if not res.ok:
		return {"ok": false, "reason": "%s: %s 안 됨 (%s)" % [u.display_name(), nm, res.get("reason", "")]}
	res["from"] = from
	res["to"] = key
	return res


## 실명: 원래 대상 대신 같은 규칙의 유효 대상 중 무작위 (아군 대상 스킬 → 아군 중, 적 대상 → 적 중)
static func blind_target(action: ActionData, actor: UnitRuntime, target: UnitRuntime, slots: SlotManager, rng: RandomNumberGenerator) -> UnitRuntime:
	if not actor.has_effect("blind") or target == null:
		return target
	var rule := TargetValidator.effective_rule(action, actor)
	if rule in ["self", "slot", "none"]:
		return target
	var pool := TargetValidator.valid_targets(action, actor, slots)
	if pool.is_empty():
		return target
	return pool[rng.randi_range(0, pool.size() - 1)] if rng != null else pool[0]
