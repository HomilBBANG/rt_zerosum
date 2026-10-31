class_name Settings
extends RefCounted
## 사용자 설정 (user://settings.cfg — 다음 실행에도 유지): 배경음악 · 효과음 음량, 창 크기, 전체 화면, 마지막 창 위치 · 크기
## (마지막 위치 · 크기는 게임을 끌 때 저장 — 다음 실행 때 그 자리 그 크기로, 화면 밖이면 가운데로).
## 소리는 오디오 버스 두 개로 나눔: "BGM"(배경음악) · "SFX"(발자국 · 쓰러짐 등). 음량 0 = 끔.

const PATH := "user://settings.cfg"
const WINDOW_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

static var bgm := 0.8          # 0 ~ 1
static var sfx := 0.8
static var fullscreen := false
static var win_size := Vector2i.ZERO   # 마지막 창 모드 크기 (0 = 기본 1920×1080)
static var win_pos := Vector2i(-99999, -99999)   # 마지막 창 위치 (안쪽 왼쪽 위, 없음 = 가운데)
static var win_last := Vector2i.ZERO             # 마지막 창 실제 크기 (끝낼 때 · 크기 바꿀 때 저장)
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		bgm = clampf(float(c.get_value("audio", "bgm", bgm)), 0.0, 1.0)
		sfx = clampf(float(c.get_value("audio", "sfx", sfx)), 0.0, 1.0)
		fullscreen = bool(c.get_value("window", "fullscreen", false))
		win_size = c.get_value("window", "size", Vector2i.ZERO)
		win_pos = c.get_value("window", "pos", win_pos)
		win_last = c.get_value("window", "last_size", Vector2i.ZERO)
	apply_audio()


static func save_all() -> void:
	var c := ConfigFile.new()
	c.set_value("audio", "bgm", bgm)
	c.set_value("audio", "sfx", sfx)
	c.set_value("window", "fullscreen", fullscreen)
	c.set_value("window", "size", win_size)
	c.set_value("window", "pos", win_pos)
	c.set_value("window", "last_size", win_last)
	c.save(PATH)


## 버스가 없으면 만들고 음량 적용
static func apply_audio() -> void:
	_set_bus("BGM", bgm)
	_set_bus("SFX", sfx)


static func _set_bus(name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, v <= 0.001)
