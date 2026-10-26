@tool
class_name RoomRouteService
extends RefCounted
## 시설 연결 그래프 경로 탐색.
## 같은 층에서 맞닿은 시설끼리 연결, 계단(기능=계단)은 같은 칸의 위아래 층 계단과 연결.
## 잠긴 시설은 지나갈 수 없다 (방을 통과해 다니는 단면 구조). 경로는 목적지가 바뀔 때만 계산한다.


static func neighbors(data: OutgameData, fid: String) -> Array[String]:
	var out: Array[String] = []
	var a: Dictionary = data.facilities.get(fid, {})
	if a.is_empty():
		return out
	for id in data.facility_order:
		if id == fid:
			continue
		var b: Dictionary = data.facilities[id]
		if b.order == a.order and (a.col + a.width == b.col or b.col + b.width == a.col):
			out.append(id)
		elif a.tag == "계단" and b.tag == "계단" and absi(b.order - a.order) == 1 and b.col == a.col:
			out.append(id)
	return out


## from → to 시설 목록 (from, …, to). is_open(fid) 가 false 인 시설은 지나가지 않음 (출발지는 예외).
## 갈 수 없으면 빈 배열, 같은 곳이면 [from].
static func find_path(data: OutgameData, from: String, to: String, is_open: Callable) -> Array[String]:
	var out: Array[String] = []
	if not data.facilities.has(from) or not data.facilities.has(to):
		return out
	if from == to:
		out.append(from)
		return out
	if not is_open.call(to):
		return out
	var prev := {from: ""}
	var queue: Array[String] = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to:
			break
		for n in neighbors(data, cur):
			if prev.has(n) or not is_open.call(n):
				continue
			prev[n] = cur
			queue.append(n)
	if not prev.has(to):
		return out
	var c := to
	while c != "":
		out.push_front(c)
		c = prev[c]
	return out


static func reachable(data: OutgameData, from: String, to: String, is_open: Callable) -> bool:
	return not find_path(data, from, to, is_open).is_empty()


## 계단 한 층 구간(아래층 계단 방 order k → 위층 k-1)이 오르는 방향: k 가 홀수면 왼쪽→오른쪽, 짝수면 오른쪽→왼쪽 (꺾인 계단)
static func flight_left_to_right(lower_order: int) -> bool:
	return lower_order % 2 == 1


## 아래층 계단 방 안에서 계단 아래 끝 / 위 끝 x (px)
static func flight_ends(data: OutgameData, lower_fid: String) -> Vector2:
	var r := data.facility_rect(lower_fid)
	var l := r.position.x + 30.0
	var rr := r.end.x - 30.0
	return Vector2(l, rr) if flight_left_to_right(int(data.facilities[lower_fid].order)) else Vector2(rr, l)


## 시설 경로 → 걸어갈 지점들. 층이 바뀌는 곳은 계단을 실제로 오르내림:
## 아래층 계단 아래 끝(바닥) → 비스듬히 → 위층 바닥의 계단 위 끝. 마지막 = 목적지 안의 end_x
static func waypoints(data: OutgameData, path: Array[String], end_x: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var oa := int(data.facilities[a].order)
		var ob := int(data.facilities[b].order)
		if oa == ob:
			continue
		var lower := a if oa > ob else b
		var ends := flight_ends(data, lower)   # x = 아래 끝, y = 위 끝
		if oa > ob:   # 올라감
			pts.append(Vector2(ends.x, data.floor_line(a)))
			pts.append(Vector2(ends.y, data.floor_line(b)))
		else:         # 내려감
			pts.append(Vector2(ends.y, data.floor_line(a)))
			pts.append(Vector2(ends.x, data.floor_line(b)))
	if not path.is_empty():
		pts.append(Vector2(end_x, data.floor_line(path[-1])))
	return pts
