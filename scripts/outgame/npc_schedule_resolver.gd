@tool
class_name NpcScheduleResolver
extends RefCounted
## 주간 일정(7일 × 시간 구간) → 지금 가야 할 시설·행동. 게임(BaseSim)과 Godot 에디터 '일정' 탭이 같이 쓴다.
## 블록: {weekday 0=월…6=일, start_minute, end_minute, target_facility_id, activity_id, required_unlocks?, fallback_facility_id?}
## 같은 시각에 블록이 겹치면 해금 조건(required_unlocks)이 모두 충족된 것 중 조건이 가장 많은 블록 → 시설 해금에 따른 생활 변화.
## 목적지가 잠겨 있거나 갈 수 없으면 fallback → 자주 머무는 장소(preferred) 순으로 대체.


## 지금 시각을 덮고 해금 조건이 충족된 블록들 (조건이 많은 것 = 더 구체적인 것 먼저, 같으면 목록 순)
static func blocks_at(sched: Dictionary, weekday: int, minute: int, is_unlocked: Callable) -> Array:
	var out := []
	for b in sched.get("weekly_schedule", []):
		if int(b.get("weekday", -1)) != weekday:
			continue
		if minute < int(b.get("start_minute", 0)) or minute >= int(b.get("end_minute", 0)):
			continue
		var ok := true
		for r in b.get("required_unlocks", []):
			if not is_unlocked.call(str(r)):
				ok = false
				break
		if ok:
			out.append(b)
	# 안정 정렬 (sort_custom 은 안정 정렬이 아니므로 원래 순서를 같이 비교)
	var idx := {}
	for i in out.size():
		idx[out[i]] = i
	out.sort_custom(func(a, b):
		var na: int = (a.get("required_unlocks", []) as Array).size()
		var nb: int = (b.get("required_unlocks", []) as Array).size()
		return na > nb if na != nb else idx[a] < idx[b])
	return out


static func block_at(sched: Dictionary, weekday: int, minute: int, is_unlocked: Callable) -> Dictionary:
	var bs := blocks_at(sched, weekday, minute, is_unlocked)
	return bs[0] if not bs.is_empty() else {}


## {facility, activity, block, reason}. can_use(fid) = 열려 있고 갈 수 있는가. 갈 곳이 없으면 facility = ""
## 블록 목적지 → 그 블록의 대체 장소 → (다음 블록) → 자주 머무는 장소 순
static func destination(sched: Dictionary, weekday: int, minute: int, is_unlocked: Callable, can_use: Callable) -> Dictionary:
	var bs := blocks_at(sched, weekday, minute, is_unlocked)
	for b in bs:
		var t := str(b.get("target_facility_id", ""))
		if t != "" and can_use.call(t):
			return {"facility": t, "activity": str(b.get("activity_id", "idle")), "block": b, "reason": "일정"}
		var fb := str(b.get("fallback_facility_id", ""))
		if fb != "" and can_use.call(fb):
			return {"facility": fb, "activity": str(b.get("activity_id", "idle")), "block": b, "reason": "대체 장소 (%s 잠김/경로 없음)" % t}
	var first: Dictionary = bs[0] if not bs.is_empty() else {}
	for p in sched.get("preferred_facility_ids", []):
		if can_use.call(str(p)):
			return {"facility": str(p), "activity": "idle", "block": first, "reason": "자주 머무는 장소" if bs.is_empty() else "자주 머무는 장소 (일정 장소 사용 불가)"}
	return {"facility": "", "activity": "idle", "block": first, "reason": "갈 수 있는 곳 없음"}


## 일정 검사: [{level: "error"|"warn", weekday, text}]. open_set = 해금된 시설 id (초기 상태 등)
static func validate(sched: Dictionary, data: OutgameData, open_set: Dictionary) -> Array:
	var out := []
	var is_open := func(fid: String) -> bool: return open_set.has(fid)
	var blocks: Array = sched.get("weekly_schedule", [])
	for p in sched.get("preferred_facility_ids", []):
		if not data.facilities.has(str(p)):
			out.append({"level": "error", "weekday": -1, "text": "자주 머무는 장소: 없는 시설 '%s'" % p})
	var dr: Dictionary = sched.get("delegation_rules", {})
	for n in dr.get("delegate_to", []):
		if not data.npcs.has(str(n)):
			out.append({"level": "error", "weekday": -1, "text": "청소 위임 대상: 없는 대원 '%s'" % n})
	var home := str(data.npcs.get(str(sched.get("npc_id", "")), {}).get("start", ""))
	for wd in 7:
		var day: Array = blocks.filter(func(b): return int(b.weekday) == wd)
		day.sort_custom(func(a, b): return int(a.start_minute) < int(b.start_minute))
		var prev_place := home
		for i in day.size():
			var b: Dictionary = day[i]
			var tag := "%s %s~%s" % [OutgameData.WEEKDAYS[wd], OutgameData.hm(int(b.start_minute)), OutgameData.hm(int(b.end_minute))]
			if int(b.end_minute) <= int(b.start_minute):
				out.append({"level": "error", "weekday": wd, "text": "%s: 끝 시각이 시작보다 빠름" % tag})
			var t := str(b.get("target_facility_id", ""))
			var fb := str(b.get("fallback_facility_id", ""))
			for r in b.get("required_unlocks", []):
				if not data.facilities.has(str(r)):
					out.append({"level": "error", "weekday": wd, "text": "%s: 해금 조건에 없는 시설 '%s'" % [tag, r]})
			if not data.facilities.has(t):
				out.append({"level": "error", "weekday": wd, "text": "%s: 없는 시설 '%s'" % [tag, t]})
				continue
			if fb != "" and not data.facilities.has(fb):
				out.append({"level": "error", "weekday": wd, "text": "%s: 대체 장소에 없는 시설 '%s'" % [tag, fb]})
			if not _activity_ok(b):
				out.append({"level": "warn", "weekday": wd, "text": "%s: 모르는 행동 '%s'" % [tag, b.get("activity_id", "")]})
			var conditional := not (b.get("required_unlocks", []) as Array).is_empty()
			if not conditional and not open_set.has(t):
				if fb == "":
					out.append({"level": "warn", "weekday": wd, "text": "%s: '%s' 잠김 + 대체 장소 없음 → 자주 머무는 장소로" % [tag, data.facility_name(t)]})
				elif not open_set.has(fb):
					out.append({"level": "warn", "weekday": wd, "text": "%s: 대체 장소 '%s' 도 잠김" % [tag, data.facility_name(fb)]})
			# 경로 검사 (현재 해금 상태 기준, 조건부 블록은 조건 시설이 열렸다고 보고 생략)
			if not conditional:
				var dest := t if open_set.has(t) else fb
				if dest != "" and open_set.has(dest) and data.facilities.has(prev_place) and not RoomRouteService.reachable(data, prev_place, dest, is_open):
					out.append({"level": "warn", "weekday": wd, "text": "%s: %s → %s 경로 없음 (잠긴 방에 막힘)" % [tag, data.facility_name(prev_place), data.facility_name(dest)]})
				if dest != "" and open_set.has(dest):
					prev_place = dest
			# 시간 겹침: 해금 조건이 같은 블록끼리만 (조건이 다르면 의도된 분기)
			for j in range(i + 1, day.size()):
				var c: Dictionary = day[j]
				if int(c.start_minute) >= int(b.end_minute):
					break
				if _same_req(b, c):
					out.append({"level": "error", "weekday": wd, "text": "%s: %s~%s 블록과 시간 겹침" % [tag, OutgameData.hm(int(c.start_minute)), OutgameData.hm(int(c.end_minute))]})
	return out


static func _activity_ok(b: Dictionary) -> bool:
	return OutgameData.ACTIVITIES.has(str(b.get("activity_id", "")))


static func _same_req(a: Dictionary, b: Dictionary) -> bool:
	var ra: Array = a.get("required_unlocks", []).duplicate()
	var rb: Array = b.get("required_unlocks", []).duplicate()
	ra.sort()
	rb.sort()
	return ra == rb
