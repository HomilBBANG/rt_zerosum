@tool
class_name WorldClock
extends RefCounted
## 게임 세계 시계. 시작 날짜 00:00 부터 흐른 게임 분(total_minutes)만 들고, 날짜·요일·월은 달력으로 계산한다.
## 시작 날짜 2048-04-07 / 24시간마다 다음 날 [확정]. 시각·배율은 임시 설정값.
## 날짜가 바뀌는 판단은 시계만 한다 (BaseSim 이 분 단위로 물어봄).

var start_unix: int = 0          # 시작 날짜 00:00 (UTC 기준 달력 계산용)
var total_minutes: float = 0.0   # 시작 날짜 00:00 부터 흐른 게임 분


func setup(start_date: String, start_minute: int) -> void:
	var p := start_date.strip_edges().split("-")
	var y := 2048
	var mo := 4
	var d := 7
	if p.size() == 3 and p[0].is_valid_int() and p[1].is_valid_int() and p[2].is_valid_int():
		y = int(p[0])
		mo = int(p[1])
		d = int(p[2])
	start_unix = Time.get_unix_time_from_datetime_dict({"year": y, "month": mo, "day": d, "hour": 0, "minute": 0, "second": 0})
	total_minutes = float(start_minute)


func minute_int() -> int:
	return floori(total_minutes)


func day_index(minute: int = -1) -> int:
	return floori((minute_int() if minute < 0 else minute) / 1440.0)


func minute_of_day(minute: int = -1) -> int:
	var m := minute_int() if minute < 0 else minute
	return m - day_index(m) * 1440


## {year, month, day, weekday(0=월 … 6=일)}
func date_of_day(day: int) -> Dictionary:
	var dd := Time.get_datetime_dict_from_unix_time(start_unix + day * 86400)
	return {"year": int(dd.year), "month": int(dd.month), "day": int(dd.day), "weekday": (int(dd.weekday) + 6) % 7}


func date(minute: int = -1) -> Dictionary:
	return date_of_day(day_index(minute))


func weekday(minute: int = -1) -> int:
	return date(minute).weekday


func month_key(minute: int = -1) -> String:
	var d := date(minute)
	return "%04d-%02d" % [d.year, d.month]


func date_str(minute: int = -1) -> String:
	var d := date(minute)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func time_str(minute: int = -1) -> String:
	var m := minute_of_day(minute)
	return "%02d:%02d" % [floori(m / 60.0), m % 60]


func label(minute: int = -1) -> String:
	return "%s (%s) %s" % [date_str(minute), OutgameData.WEEKDAYS[weekday(minute)], time_str(minute)]


## 주 번호: 시작 날짜부터 week_days 일 단위 [임시: 결산 요일 미정]
func week_index(week_days: int, minute: int = -1) -> int:
	return floori(day_index(minute) / float(maxi(1, week_days)))


## "YYYY-MM-DD" 날짜의 day_index (시작 날짜 = 0). 형식이 틀리면 0
func day_of(date_text: String) -> int:
	var p := date_text.strip_edges().split("-")
	if p.size() != 3 or not (p[0].is_valid_int() and p[1].is_valid_int() and p[2].is_valid_int()):
		return 0
	var u := Time.get_unix_time_from_datetime_dict({"year": int(p[0]), "month": int(p[1]), "day": int(p[2]), "hour": 0, "minute": 0, "second": 0})
	return floori((u - start_unix) / 86400.0)


## 이 분이 속한 달의 첫날 00:00 / 다음 달 첫날 00:00 (게임 분)
func month_bounds(minute: int = -1) -> Vector2i:
	var d := date(minute)
	var first: int = day_index(minute) - (d.day - 1)
	var ny: int = d.year + (1 if d.month == 12 else 0)
	var nm: int = 1 if d.month == 12 else d.month + 1
	var next_u := Time.get_unix_time_from_datetime_dict({"year": ny, "month": nm, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var next_day := floori((next_u - start_unix) / 86400.0)
	return Vector2i(first * 1440, next_day * 1440)
