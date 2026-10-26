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
## 부상·상태이상 등으로 자리를 옮길 수 없음 (자리 이동·교환 대상에서 빠짐). 상태이상 시스템이 생기면 여기서 판단
var move_locked: bool = false
## 상태 이상 id 목록 (정의는 StatusCatalog)
var statuses: Array[String] = []


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
	move_locked = false
	statuses.clear()


func slot_key() -> String:
	return SlotManager.make_key(team, row, index)


## 차지한 모든 슬롯 (큰 몸집은 row 부터 row_span 칸)
func slot_keys() -> Array[String]:
	var out: Array[String] = []
	for r in range(row, row + data.row_span):
		out.append(SlotManager.make_key(team, r, index))
	return out


func occupies_row(r: int) -> bool:
	return r >= row and r < row + data.row_span


func is_large() -> bool:
	return data.row_span > 1


## 자리 이동·교환이 가능한가 (큰 몸집·부상·상태이상이면 불가)
func can_be_moved() -> bool:
	if not alive or is_large() or move_locked:
		return false
	for sid in statuses:
		if StatusCatalog.get_def(sid).get("blocks_move", false):
			return false
	return true


func add_status(id: String) -> void:
	if not statuses.has(id):
		statuses.append(id)


func remove_status(id: String) -> void:
	statuses.erase(id)


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
