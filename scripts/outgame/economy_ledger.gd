class_name EconomyLedger
extends RefCounted
## 달러 원장. 모든 입출금은 고유 id 를 가진 항목으로만 반영 → 같은 거래(해금·작업 수익·지원금·점검 보너스)가 두 번 들어가지 않는다.
## 작업·의뢰 수익과 점검 보너스는 '미지급(pending)'으로 쌓였다가 주간 결산 때 현금으로 들어온다 [임시 권장 방식].

var cash: int = 0
var entries: Array = []          # [{id, minute, date, source, amount, ref, label, week}]
var pending: Array = []          # [{id, source, amount, ref, label, week}]
var settled_weeks: Array = []    # 결산을 마친 주 번호
var statements: Array = []       # [{week, items, total, cash, date}]
var _ids: Dictionary = {}


func has_entry(id: String) -> bool:
	return _ids.has(id)


func has_pending(id: String) -> bool:
	for p in pending:
		if p.id == id:
			return true
	return false


## 즉시 입출금. 이미 있는 id 면 반영하지 않고 false
func post(id: String, minute: int, date: String, source: String, amount: int, ref: String, label: String, week: int) -> bool:
	if _ids.has(id):
		return false
	entries.append({"id": id, "minute": minute, "date": date, "source": source, "amount": amount, "ref": ref, "label": label, "week": week})
	_ids[id] = true
	cash += amount
	return true


## 다음 결산 때 받을 돈
func add_pending(id: String, source: String, amount: int, ref: String, label: String, week: int) -> bool:
	if _ids.has(id) or has_pending(id):
		return false
	pending.append({"id": id, "source": source, "amount": amount, "ref": ref, "label": label, "week": week})
	return true


func pending_total() -> int:
	var t := 0
	for p in pending:
		t += int(p.amount)
	return t


## week 주 결산: 행정 지원금 + 그 주까지 쌓인 미지급. 이미 결산한 주면 {}
func settle(week: int, subsidy: int, minute: int, date: String) -> Dictionary:
	if week in settled_weeks:
		return {}
	var items := []
	var sid := "subsidy:w%d" % week
	if post(sid, minute, date, "subsidy", subsidy, "w%d" % week, "주간 행정 지원금", week):
		items.append({"id": sid, "label": "주간 행정 지원금", "amount": subsidy, "source": "subsidy"})
	var keep := []
	for p in pending:
		if int(p.week) <= week:
			if post(p.id, minute, date, p.source, int(p.amount), p.ref, p.label, week):
				items.append({"id": p.id, "label": p.label, "amount": int(p.amount), "source": p.source})
		else:
			keep.append(p)
	pending = keep
	settled_weeks.append(week)
	var total := 0
	for it in items:
		total += int(it.amount)
	var st := {"week": week, "items": items, "total": total, "cash": cash, "date": date}
	statements.append(st)
	return st


func to_dict() -> Dictionary:
	return {"cash": cash, "entries": entries, "pending": pending, "settled_weeks": settled_weeks, "statements": statements}


func from_dict(d: Dictionary) -> void:
	cash = int(d.get("cash", 0))
	entries = d.get("entries", [])
	pending = d.get("pending", [])
	settled_weeks = (d.get("settled_weeks", []) as Array).map(func(w): return int(w))
	statements = d.get("statements", [])
	_ids.clear()
	for e in entries:
		e.amount = int(e.amount)
		e.week = int(e.week)
		_ids[e.id] = true
	for p in pending:
		p.amount = int(p.amount)
		p.week = int(p.week)
