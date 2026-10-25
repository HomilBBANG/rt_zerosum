class_name BattleViewBase
extends Node
## 2D/3D 공통 표현 인터페이스. 규칙(BattleController)은 표현을 모른다.

signal unit_clicked(unit: UnitRuntime)
signal slot_clicked(key: String)

var controller: BattleController
var preset: Dictionary = {}
var busy: bool = false       # 연출 중 입력 잠금
var _busy_count: int = 0


func setup(p_controller: BattleController, p_preset: Dictionary) -> void:
	controller = p_controller
	preset = p_preset


func apply_preset(_p: Dictionary) -> void:
	pass


func get_unit_screen_pos(_unit: UnitRuntime) -> Vector2:
	return Vector2.ZERO


func get_slot_screen_pos(_key: String) -> Vector2:
	return Vector2.ZERO


func set_highlight(_unit: UnitRuntime, _kind: String) -> void:
	pass


func clear_highlights() -> void:
	pass


func show_slot_markers(_options: Array[Dictionary]) -> void:
	pass


func clear_slot_markers() -> void:
	pass


func _begin_busy() -> void:
	_busy_count += 1
	busy = true


func _end_busy() -> void:
	_busy_count = maxi(0, _busy_count - 1)
	busy = _busy_count > 0
