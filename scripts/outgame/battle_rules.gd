@tool
class_name BattleRules
extends RefCounted
## 전투 발생 규칙 (data/outgame/battle_rules.json, Godot 에디터 '전투 발생' 탭). 게임(BaseSim)과 에디터 미리보기가 같이 쓴다.
## mode:
##   interval = anchor(HH:MM) 부터 interval_minutes 마다 (예: 06:00 기준 360분 → 00·06·12·18시)
##   daily    = times(["HH:MM", ...]) 시각마다
##   once     = date("YYYY-MM-DD") 의 times[0] 한 번
## weekdays(0=월…6=일) 에 포함된 요일만, start_day("YYYY-MM-DD") 이후만. stages 중 하나를 골라 전투.

const MODES := {"interval": "일정 간격", "daily": "매일 정한 시각", "once": "한 번 (날짜·시각)"}


static func _hm(s: String) -> int:
	return OutgameData.parse_hm(s, 0)


## 게임 분 m 에 이 규칙이 발동하는가
static func fires_at(rule: Dictionary, m: int, clock: WorldClock) -> bool:
	if not rule.get("enabled", true):
		return false
	var day := clock.day_index(m)
	var wd := clock.weekday(m)
	if not wd in (rule.get("weekdays", [0, 1, 2, 3, 4, 5, 6]) as Array):
		return false
	if str(rule.get("start_day", "")) != "" and day < clock.day_of(str(rule.start_day)):
		return false
	var mod := clock.minute_of_day(m)
	match str(rule.get("mode", "interval")):
		"interval":
			var iv := maxi(10, int(rule.get("interval_minutes", 360)))
			return posmod(m - _hm(str(rule.get("anchor", "00:00"))), iv) == 0
		"daily":
			for t in rule.get("times", []):
				if _hm(str(t)) == mod:
					return true
			return false
		"once":
			var times: Array = rule.get("times", [])
			var t := _hm(str(times[0])) if not times.is_empty() else 0
			return str(rule.get("date", "")) != "" and day == clock.day_of(str(rule.date)) and mod == t
	return false


## from_m 이후(포함 안 함) 처음 발동하는 게임 분, 없으면 -1 (limit_days 안에서)
static func next_fire(rule: Dictionary, from_m: int, clock: WorldClock, limit_days: int = 14) -> int:
	if not rule.get("enabled", true):
		return -1
	var cands: Array[int] = []
	var first_day := clock.day_index(from_m)
	match str(rule.get("mode", "interval")):
		"interval":
			var iv := maxi(10, int(rule.get("interval_minutes", 360)))
			var a := _hm(str(rule.get("anchor", "00:00")))
			var m := a + (floori(float(from_m - a) / iv) + 1) * iv
			var end := (first_day + limit_days) * 1440
			while m <= end:
				if fires_at(rule, m, clock):
					return m
				m += iv
			return -1
		"daily":
			for d in range(first_day, first_day + limit_days + 1):
				for t in rule.get("times", []):
					cands.append(d * 1440 + _hm(str(t)))
		"once":
			var times: Array = rule.get("times", [])
			if str(rule.get("date", "")) != "":
				cands.append(clock.day_of(str(rule.date)) * 1440 + (_hm(str(times[0])) if not times.is_empty() else 0))
	cands.sort()
	for c in cands:
		if c > from_m and fires_at(rule, c, clock):
			return c
	return -1


## 규칙들 중 가장 먼저 발동하는 것 {minute, rule} (없으면 {})
static func next_of(rules: Array, from_m: int, clock: WorldClock) -> Dictionary:
	var best := {}
	for r in rules:
		var m := next_fire(r, from_m, clock)
		if m >= 0 and (best.is_empty() or m < int(best.minute)):
			best = {"minute": m, "rule": r}
	return best


static func describe(rule: Dictionary) -> String:
	match str(rule.get("mode", "interval")):
		"interval":
			var iv := int(rule.get("interval_minutes", 360))
			var span := ("%d시간" % floori(iv / 60.0) if iv >= 60 else "") + (" %d분" % (iv % 60) if iv % 60 else "")
			return "%s 기준 %s마다" % [rule.get("anchor", "00:00"), span.strip_edges()]
		"daily":
			return "매일 " + ", ".join(rule.get("times", []))
		"once":
			var times: Array = rule.get("times", [])
			return "%s %s 한 번" % [rule.get("date", "?"), times[0] if not times.is_empty() else "00:00"]
	return "?"
