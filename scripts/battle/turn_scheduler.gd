class_name TurnScheduler
extends RefCounted
## 행동 순서 계산 (GDD 2.2 / 3절).
## 1라운드: 선공 진영 최고 속도 1명 → 나머지 전체 속도 내림차순.
## 2라운드+: 전체 속도 내림차순.
## 동률: 아군 우선 → 레벨 높은 쪽 → 원거리(병과) 우선 → 슬롯 순서(열, 번호) → 인스턴스 ID.


static func compare(a: UnitRuntime, b: UnitRuntime) -> bool:
	if a.data.speed != b.data.speed:
		return a.data.speed > b.data.speed
	if a.team != b.team:
		return a.team == "ally"
	if a.data.level != b.data.level:
		return a.data.level > b.data.level
	var ar := a.data.range_type == "ranged"
	var br := b.data.range_type == "ranged"
	if ar != br:
		return ar
	if a.row != b.row:
		return a.row < b.row
	if a.index != b.index:
		return a.index < b.index
	return a.instance_id < b.instance_id


static func sort_by_speed(units: Array[UnitRuntime]) -> Array[UnitRuntime]:
	var arr: Array[UnitRuntime] = units.duplicate()
	arr.sort_custom(compare)
	return arr


static func build_round_queue(units: Array[UnitRuntime], round_no: int, first_team: String) -> Array[UnitRuntime]:
	var living: Array[UnitRuntime] = []
	for u in units:
		if u.alive:
			living.append(u)
	var sorted := sort_by_speed(living)
	if round_no != 1 or first_team == "":
		return sorted
	# 선공 진영 최고속 1명을 맨 앞으로
	var leader: UnitRuntime = null
	for u in sorted:
		if u.team == first_team:
			leader = u
			break
	if leader == null:
		return sorted
	var queue: Array[UnitRuntime] = [leader]
	for u in sorted:
		if u != leader:
			queue.append(u)
	return queue
