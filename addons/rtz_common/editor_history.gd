@tool
class_name EditorHistory
extends RefCounted
## 에디터 탭 공용 뒤로 감기 / 앞으로 감기 (Ctrl+Z / Ctrl+Y · Ctrl+Shift+Z, Mac 은 Cmd).
## 패널이 '지금 편집 중인 데이터 전체' 를 글자로 떠 주는 snap() 과 그 글자로 되돌리는 apply(s) 만 주면 됨.
## 패널의 _process 에서 tick() → 데이터가 바뀌고 잠깐(SETTLE 초) 그대로면 한 단계로 기록 (글자를 이어 치면 한 단계로 묶임).
## 파일을 새로 읽으면(되돌리기 · 다른 파일 열기) reset() — 그 전 단계로는 못 돌아감.

const MAX := 200          # 기록하는 단계 수
const SETTLE := 0.35      # 바뀐 뒤 이만큼 그대로면 한 단계
const POLL := 0.12        # 데이터를 떠 보는 간격 (초)

var _snap: Callable       # () -> String
var _apply: Callable      # (String) -> void
var _stack: Array[String] = []
var _i := -1
var _pending := ""
var _still := 0.0
var _poll := 0.0


func _init(snap: Callable, apply: Callable) -> void:
	_snap = snap
	_apply = apply


## 지금 상태를 처음 단계로 (파일을 읽은 뒤)
func reset() -> void:
	var s: String = _snap.call()
	_stack = [s]
	_i = 0
	_pending = s
	_still = 0.0


func tick(delta: float) -> void:
	_poll += delta
	if _poll < POLL:
		return
	var dt := _poll
	_poll = 0.0
	if _stack.is_empty():
		reset()
		return
	var s: String = _snap.call()
	if s != _pending:
		_pending = s
		_still = 0.0
		return
	if s == _stack[_i]:
		return
	_still += dt
	if _still >= SETTLE:
		_push(s)


func _push(s: String) -> void:
	_stack.resize(_i + 1)
	_stack.append(s)
	while _stack.size() > MAX:
		_stack.pop_front()
	_i = _stack.size() - 1
	_pending = s
	_still = 0.0


## 아직 기록 안 된 바뀜이 있으면 기록 (뒤로 감기 직전)
func flush() -> void:
	if _stack.is_empty():
		reset()
		return
	var s: String = _snap.call()
	if s != _stack[_i]:
		_push(s)


func undo() -> bool:
	flush()
	if _i <= 0:
		return false
	_i -= 1
	_restore()
	return true


func redo() -> bool:
	flush()
	if _i >= _stack.size() - 1:
		return false
	_i += 1
	_restore()
	return true


func _restore() -> void:
	_apply.call(_stack[_i])
	var s: String = _snap.call()   # 되돌린 뒤 화면이 정리한 모양으로 맞춤 (다시 기록되지 않게)
	_stack[_i] = s
	_pending = s
	_still = 0.0


func undo_count() -> int:
	return maxi(0, _i)


func redo_count() -> int:
	return maxi(0, _stack.size() - 1 - _i)


## Ctrl/Cmd+Z → -1 (뒤로), Ctrl/Cmd+Y · Ctrl/Cmd+Shift+Z → +1 (앞으로), 아니면 0
static func key_dir(event: InputEvent) -> int:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return 0
	var k := event as InputEventKey
	if not (k.ctrl_pressed or k.meta_pressed):
		return 0
	if k.keycode == KEY_Z:
		return 1 if k.shift_pressed else -1
	if k.keycode == KEY_Y:
		return 1
	return 0


## 패널의 _input 에서 부름. 글자 칸(LineEdit · TextEdit)에 커서가 있으면 그 칸의 글자 되돌리기에 맡김.
## 다른 창(인스펙터 등)에 커서가 있고 마우스도 패널 밖이면 Godot 에디터의 되돌리기에 맡김.
static func handle_input(panel: Control, event: InputEvent, h: EditorHistory, status: Label = null) -> void:
	if h == null or not panel.is_visible_in_tree():
		return
	var dir := key_dir(event)
	if dir == 0:
		return
	var f := panel.get_viewport().gui_get_focus_owner()
	if f is LineEdit or f is TextEdit:
		return
	var inside := f == null or panel.is_ancestor_of(f) or panel.get_global_rect().has_point(panel.get_global_mouse_position())
	if not inside:
		return
	var ok := h.undo() if dir < 0 else h.redo()
	if status != null:
		if ok:
			status.text = "%s (뒤로 %d · 앞으로 %d) — 저장 안 함" % ["↶ 뒤로 감기" if dir < 0 else "↷ 앞으로 감기", h.undo_count(), h.redo_count()]
		else:
			status.text = "더 뒤로 갈 것이 없습니다" if dir < 0 else "더 앞으로 갈 것이 없습니다"
	panel.get_viewport().set_input_as_handled()
