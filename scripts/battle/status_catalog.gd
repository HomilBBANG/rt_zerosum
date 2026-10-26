class_name StatusCatalog
extends RefCounted
## 상태 이상 정의 (프로토타입). positive = 긍정(녹색) / 부정(붉은색).
## expires: "own_turn_end" = 그 유닛의 다음 턴이 끝나면 사라짐, "" = 직접 지울 때까지.
## blocks_move: 자리 이동·교체 대상에서 빠짐.

const DEFS := {
	"rallied": {"name": "독려", "positive": true, "expires": "own_turn_end",
		"desc": "아군의 독려로 AP 를 추가로 받았습니다. 이 유닛의 다음 턴이 끝나면 사라집니다."},
	"injured": {"name": "부상", "positive": false, "expires": "", "blocks_move": true,
		"desc": "다쳐서 자리 이동·교체를 할 수 없습니다."},
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {"name": id, "positive": false, "expires": "", "desc": ""})
