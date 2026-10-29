@tool
extends EditorPlugin
## Godot 에디터 상단의 "스토리" 탭. 퀘스트 · 컷씬 · 신 해금 · 계기 흐름 그래프 (읽기 전용 — 고치는 건 퀘스트 · 컷씬 · 스킬 트리(기적) 탭)

const PANEL := preload("res://addons/rtz_story_editor/story_editor_panel.gd")
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
			panel.reload_data()   # 탭을 열 때마다 퀘스트 · 컷씬 · 신 해금 파일을 다시 읽음 (다른 탭에서 저장한 것 반영)


func _get_plugin_name() -> String:
	return "스토리"


func _get_plugin_icon() -> Texture2D:
	var th := EditorInterface.get_editor_theme()
	return th.get_icon("GraphEdit" if th.has_icon("GraphEdit", "EditorIcons") else "Node", "EditorIcons")
