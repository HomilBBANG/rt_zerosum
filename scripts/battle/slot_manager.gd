class_name SlotManager
extends RefCounted
## (team,row,index) 슬롯 관리. 이동/교환은 원자적으로 갱신한다.

const ROWS := 3
const PER_ROW := 2
const ROW_NAMES := ["전방", "중앙", "후방"]

var _slots: Dictionary = {}          # key -> UnitRuntime
var _units: Array[UnitRuntime] = []


static func make_key(team: String, row: int, index: int) -> String:
	return "%s:%d:%d" % [team, row, index]


static func parse_key(key: String) -> Dictionary:
	var parts := key.split(":")
	return {"team": parts[0], "row": int(parts[1]), "index": int(parts[2])}


func clear() -> void:
	_slots.clear()
	_units.clear()


func add_unit(unit: UnitRuntime) -> bool:
	if unit.row + unit.data.row_span > ROWS:
		push_error("Slot out of range: %s span %d" % [unit.slot_key(), unit.data.row_span])
		return false
	for key in unit.slot_keys():
		if _slots.has(key):
			push_error("Slot occupied: %s" % key)
			return false
	for key in unit.slot_keys():
		_slots[key] = unit   # 큰 몸집은 차지한 칸 모두 같은 유닛을 가리킴
	_units.append(unit)
	return true


func all_units() -> Array[UnitRuntime]:
	return _units.duplicate()


func living_units(team: String = "") -> Array[UnitRuntime]:
	var out: Array[UnitRuntime] = []
	for u in _units:
		if u.alive and (team == "" or u.team == team):
			out.append(u)
	return out


func unit_at(key: String) -> UnitRuntime:
	return _slots.get(key, null)


func units_in_row(team: String, row: int, only_alive: bool = true) -> Array[UnitRuntime]:
	var out: Array[UnitRuntime] = []
	for i in PER_ROW:
		var u: UnitRuntime = _slots.get(make_key(team, row, i), null)
		if u != null and (not only_alive or u.alive):
			out.append(u)
	return out


func team_slot_keys(team: String) -> Array[String]:
	var out: Array[String] = []
	for r in ROWS:
		for i in PER_ROW:
			out.append(make_key(team, r, i))
	return out


## 빈 슬롯이면 이동, 점유 슬롯이면 교환. 반환: {"ok", "kind": "move"|"swap", "other"}
func move_or_swap(unit: UnitRuntime, target_key: String) -> Dictionary:
	var info := parse_key(target_key)
	if info.team != unit.team:
		return {"ok": false, "reason": "아군 슬롯만 선택할 수 있습니다."}
	if target_key == unit.slot_key():
		return {"ok": false, "reason": "현재 위치입니다."}
	var other: UnitRuntime = _slots.get(target_key, null)
	if not unit.can_be_moved() or (other != null and not other.can_be_moved()):
		return {"ok": false, "reason": "자리를 옮기거나 바꿀 수 없는 상태입니다."}
	var from_key := unit.slot_key()
	if other == null:
		_slots.erase(from_key)
		unit.row = info.row
		unit.index = info.index
		_slots[target_key] = unit
		return {"ok": true, "kind": "move", "from": from_key, "to": target_key}
	# swap: 양쪽 참조를 원자적으로 갱신
	_slots[from_key] = other
	_slots[target_key] = unit
	var ur := unit.row
	var ui := unit.index
	unit.row = other.row
	unit.index = other.index
	other.row = ur
	other.index = ui
	return {"ok": true, "kind": "swap", "from": from_key, "to": target_key, "other": other}


func remove_dead_from_slots() -> void:
	# 사망 유닛도 슬롯은 유지(시체가 자리 차지하지 않도록 비움)
	for key in _slots.keys():
		var u: UnitRuntime = _slots[key]
		if not u.alive:
			_slots.erase(key)
