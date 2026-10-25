class_name UnitRuntime
extends RefCounted
## 전투 중 가변 상태 (GDD 7절 UnitRuntime).

var data: UnitData
var instance_id: int = 0
var team: String = "ally"
var row: int = 0
var index: int = 0
var hp: int = 0
var ap: int = 0
var weapon_index: int = 0
var alive: bool = true
## 이번 턴 누적 행동 수 (디버그/AI 용)
var actions_this_turn: int = 0


static func create(p_data: UnitData, p_instance_id: int, p_row: int, p_index: int) -> UnitRuntime:
	var u := UnitRuntime.new()
	u.data = p_data
	u.instance_id = p_instance_id
	u.team = p_data.team
	u.row = p_row
	u.index = p_index
	u.reset()
	return u


func reset() -> void:
	hp = data.max_hp
	ap = data.max_ap # 전투 시작 시 최대 AP
	weapon_index = 0
	alive = true
	actions_this_turn = 0


func slot_key() -> String:
	return SlotManager.make_key(team, row, index)


func current_weapon() -> Dictionary:
	if data.weapons.is_empty():
		return {"id": "none", "name": "맨손", "range_type": data.range_type, "power_bonus": 0}
	return data.weapons[clampi(weapon_index, 0, data.weapons.size() - 1)]


func is_ranged_now() -> bool:
	return current_weapon().get("range_type", data.range_type) == "ranged"


func display_name() -> String:
	return data.display_name


func debug_string() -> String:
	return "%s(spd%d lv%d hp%d/%d ap%d/%d %s)" % [
		data.display_name, data.speed, data.level, hp, data.max_hp, ap, data.max_ap, slot_key()]
