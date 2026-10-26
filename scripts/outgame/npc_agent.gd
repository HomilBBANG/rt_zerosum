class_name NpcAgent
extends RefCounted
## 기지 대원 한 명의 실행 상태 (화면 노드와 분리된 데이터). BaseSim 이 매 게임 분 갱신한다.
## 상태: IDLE / MOVING / STAYING / CHATTING / PLAYER_DIALOGUE / ASSIGNED_WORK / CLEANING / TRAINING / UNAVAILABLE

const IDLE := "IDLE"
const MOVING := "MOVING"
const STAYING := "STAYING"
const CHATTING := "CHATTING"
const PLAYER_DIALOGUE := "PLAYER_DIALOGUE"
const ASSIGNED_WORK := "ASSIGNED_WORK"
const CLEANING := "CLEANING"
const TRAINING := "TRAINING"
const UNAVAILABLE := "UNAVAILABLE"   # 외부 의뢰로 기지 밖
const TREATMENT := "TREATMENT"       # 의무실에서 치료 중 (상태 이상 제거)
const RECOVERING := "RECOVERING"     # 의무실 침대에서 휴식 (체력 회복)
const STATE_NAMES := {IDLE: "대기", MOVING: "이동 중", STAYING: "머무는 중", CHATTING: "대화 중", PLAYER_DIALOGUE: "지휘관과 대화",
	ASSIGNED_WORK: "업무 중", CLEANING: "청소 중", TRAINING: "훈련 중", UNAVAILABLE: "외부 의뢰 중", TREATMENT: "치료 중", RECOVERING: "의무실 휴식"}

var id: String = ""
var name: String = ""
var character_id: String = ""
var sprite: String = ""
var height_cm: float = 175.0
var pos: Vector2 = Vector2.ZERO
var facing: int = 1
var facility: String = ""          # 지금 있는 시설
var state: String = IDLE
var activity: String = "idle"      # 일정 행동 (sleep/rest/eat/work/train/chat/idle)
var dest: String = ""              # 가는 중이거나 도착한 목적지 시설
var dest_x: float = 0.0
var dest_reason: String = ""       # 목적지를 고른 이유 (디버그 표시)
var path: PackedVector2Array = PackedVector2Array()
var command: Dictionary = {}       # 플레이어 지시 {type: clean|job|train, target, issuer, uid?, contract?}
var busy: float = 0.0              # 지시 작업 남은 게임 분
var resume_state: String = ""      # 지휘관 대화가 끝나면 돌아갈 상태
var chat_key: String = ""
var last_chat: int = -100000
var need_think: bool = true        # 일정을 다시 볼 필요 (해금·지시 완료·대화 종료 등)
var seat: String = ""              # 차지한 오브젝트 (침대·소파·의자·의무침대) id
var meal_key: String = ""          # 마지막으로 식사한 끼 (중복 소모 방지)
var running: bool = false          # 플레이어가 더블클릭으로 보낸 이동 = 뛰기 (도착하면 해제)


func is_free() -> bool:
	return (command.is_empty() or is_holding()) and state != PLAYER_DIALOGUE and state != UNAVAILABLE


## 플레이어가 직접 보낸 이동·행동(이동, 잠자기, 쉬기, 식사) — 다른 지시로 바로 바꿀 수 있음
func is_holding() -> bool:
	return str(command.get("type", "")) == "move"


func is_working() -> bool:
	return state in [ASSIGNED_WORK, CLEANING, TRAINING, UNAVAILABLE, TREATMENT, RECOVERING]


func state_name() -> String:
	return STATE_NAMES.get(state, state)


func to_dict() -> Dictionary:
	return {"id": id, "pos": [pos.x, pos.y], "facing": facing, "facility": facility, "state": state, "activity": activity,
		"dest": dest, "dest_x": dest_x, "command": command, "busy": busy, "resume_state": resume_state, "last_chat": last_chat,
		"seat": seat, "meal_key": meal_key, "running": running}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [pos.x, pos.y])
	pos = Vector2(float(p[0]), float(p[1]))
	facing = int(d.get("facing", 1))
	facility = str(d.get("facility", facility))
	state = str(d.get("state", STAYING))
	activity = str(d.get("activity", "idle"))
	dest = str(d.get("dest", facility))
	dest_x = float(d.get("dest_x", pos.x))
	command = d.get("command", {})
	busy = float(d.get("busy", 0.0))
	resume_state = str(d.get("resume_state", ""))
	last_chat = int(d.get("last_chat", -100000))
	chat_key = ""
	seat = str(d.get("seat", ""))
	meal_key = str(d.get("meal_key", ""))
	running = bool(d.get("running", false))
	need_think = true
