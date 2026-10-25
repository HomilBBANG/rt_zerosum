class_name APComponent
extends RefCounted
## AP 규칙 (GDD 2.3): 차례 시작 회복, 상한 버림, 이월, 0이면 자동 종료.


static func start_turn_recover(unit: UnitRuntime) -> int:
	var before := unit.ap
	unit.ap = mini(unit.ap + unit.data.ap_recovery, unit.data.max_ap)
	return unit.ap - before


static func can_pay(unit: UnitRuntime, cost: int) -> bool:
	return unit.ap >= cost


static func pay(unit: UnitRuntime, cost: int) -> bool:
	if not can_pay(unit, cost):
		return false
	unit.ap -= cost
	return true


static func grant(unit: UnitRuntime, amount: int) -> int:
	var before := unit.ap
	unit.ap = mini(unit.ap + amount, unit.data.max_ap)
	return unit.ap - before
