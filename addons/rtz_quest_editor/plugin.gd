@tool
extends EditorPlugin
## Godot 에디터 상단(2D · 3D · Script 옆)의 "퀘스트" 탭. 퀘스트 목록 · 시작 조건 · 단계 · 보상 (data/quests.json)

const PANEL := preload("res://addons/rtz_quest_editor/quest_editor_panel.gd")
var panel: Control


func _enter_tree() -> void:
	panel = PANEL.new()
	EditorInterface.get_editor_main_screen().add_child(panel)
	_make_visible(false)


func _exit_tree() -> void:
	if panel != null:
		panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if panel != null:
		panel.visible = visible
		if visible and panel.has_method("reload_data"):
			panel.reload_data(true)   # 탭을 열 때마다 대원·의뢰·연구·스테이지 목록 다시 읽기 (편집 중인 퀘스트는 유지)


func _get_plugin_name() -> String:
	return "퀘스트"


func _get_plugin_icon() -> Texture2D:
	var th := EditorInterface.get_editor_theme()
	return th.get_icon("Script" if th.has_icon("Script", "EditorIcons") else "Node", "EditorIcons")
