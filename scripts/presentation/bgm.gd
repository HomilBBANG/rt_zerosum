class_name Bgm
extends RefCounted
## 배경음악 (data/bgm.json 목록, 파일 assets/audio/bgm/). Game(자동 로드)에 붙은 플레이어 하나로 재생.
## 기지(아웃게임) 전용: 기지에 들어오면 재생, 기지를 떠나면(타이틀 · 편성 · 전투 등) 짧게 줄이며 멈춤 — 다시 오면 그 곡 처음부터.
## 한 곡이 끝나면 다음 곡 (목록 끝이면 처음으로). 기지 공용실 주크박스 → 음악 카세트 창에서 ▲ 이전 · ▼ 다음.

const DATA := "res://data/bgm.json"
const DIR := "res://assets/audio/bgm"

static var tracks: Array = []      # [{file, title}]
static var index := 0
static var volume_db := -8.0
static var _player: AudioStreamPlayer
static var _loaded := false
static var changed_hook: Array[Callable] = []
static var _fade: Tween   # 곡이 바뀔 때 부를 것 (카세트 창 제목 갱신)


static func _load_list() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return
	volume_db = float(d.get("volume_db", -8.0))
	for t in d.get("tracks", []):
		if str(t.get("file", "")) != "":
			tracks.append({"file": str(t.file), "title": str(t.get("title", t.file))})


static func _ensure_player() -> AudioStreamPlayer:
	if _player != null and is_instance_valid(_player):
		return _player
	var root := Engine.get_main_loop() as SceneTree
	if root == null:
		return null
	_player = AudioStreamPlayer.new()
	_player.name = "Bgm"
	_player.bus = "BGM"   # 설정 '배경음악' 음량 (Settings)
	_player.finished.connect(func(): play_index(index + 1))   # 다 들으면 다음 곡
	Game.add_child(_player)
	return _player


static func _stream(file: String) -> AudioStream:
	var path := DIR.path_join(file)
	if ResourceLoader.exists(path):
		return load(path)
	if FileAccess.file_exists(path):   # 임포트 전에 넣은 곡도
		return AudioStreamMP3.load_from_file(ProjectSettings.globalize_path(path))
	return null


## 아직 아무것도 안 나오면 지금 곡부터 재생 (기지에 들어올 때)
static func ensure_playing() -> void:
	_load_list()
	var p := _ensure_player()
	if _fade != null and _fade.is_valid():   # 줄이는 중에 기지로 돌아오면 줄이기 취소
		_fade.kill()
		_fade = null
		if p != null:
			p.volume_db = volume_db
	if p == null or p.playing or tracks.is_empty():
		return
	play_index(index)


static func play_index(i: int) -> void:
	_load_list()
	if tracks.is_empty():
		return
	index = posmod(i, tracks.size())
	var p := _ensure_player()
	if p == null:
		return
	p.stream = _stream(str(tracks[index].file))
	p.volume_db = volume_db
	if p.stream != null:
		p.play()
	for cb in changed_hook:
		if cb.is_valid():
			cb.call()


static func next() -> void:
	play_index(index + 1)


static func prev() -> void:
	play_index(index - 1)


static func title() -> String:
	_load_list()
	return "" if tracks.is_empty() else str(tracks[index].title)


static func stop() -> void:
	if _player != null and is_instance_valid(_player):
		_player.stop()


## 짧게 소리를 줄이며 멈춤 (기지를 떠날 때). 플레이어는 Game 에 붙어 있어 장면이 바뀌어도 끝까지 줄어듦
static func fade_out(sec: float = 0.4) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.playing:
		return
	var p := _player
	_fade = p.create_tween()
	_fade.tween_property(p, "volume_db", -60.0, sec)
	_fade.tween_callback(func():
		p.stop()
		p.volume_db = volume_db)
