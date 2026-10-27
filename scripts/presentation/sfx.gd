class_name Sfx
extends RefCounted
## 효과음 (발자국·쓰러짐). 소리 파일:
##   캐릭터 발자국 = assets/characters/<id>/sfx/<walk|run>_01.ogg, _02.ogg … (한 걸음씩, 돌아가며 재생 — tools/sfx_steps.py 로 자름)
##   공용 = assets/sfx/<이름>.ogg (dead = 쓰러질 때, 모든 캐릭터·몬스터)
## 위치 소리(AudioStreamPlayer2D): 화면 가운데에서 멀수록 작고, 좌우로 나뉨. 에디터(@tool 미리보기)에서는 안 남.

const COMMON := "res://assets/sfx"
## [임시] 음량 (dB)
const FOOTSTEP_DB := 0.0
const DEAD_DB := -3.0
const MAX_DISTANCE := 2200.0

static var enabled := true
static var _cache: Dictionary = {}   # 경로 → AudioStream (없으면 null)


static func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	if FileAccess.file_exists(path):   # 원본 파일이 있으면 직접 (임포트 전에 넣은 소리도 바로)
		s = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
	elif ResourceLoader.exists(path):   # 내보낸 게임
		s = load(path)
	_cache[path] = s
	return s


## 그 캐릭터 그 동작(walk|run)의 발자국 조각들 (없으면 빈 배열)
static func footsteps(cid: String, gait: String) -> Array:
	var key := "steps:%s/%s" % [cid, gait]
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var dir := "res://assets/characters".path_join(cid).path_join("sfx")
	if DirAccess.dir_exists_absolute(dir):
		var names := {}
		for f in DirAccess.get_files_at(dir):
			var fn := f.trim_suffix(".import").trim_suffix(".remap")
			if fn.begins_with(gait + "_") and fn.ends_with(".ogg"):
				names[fn] = true
		var keys := names.keys()
		keys.sort()
		for fn in keys:
			var s := _load(dir.path_join(fn))
			if s != null:
				out.append(s)
	_cache[key] = out
	return out


static func common(sound: String) -> AudioStream:
	return _load(COMMON.path_join(sound + ".ogg"))


## node 위치에서 한 번 재생 (끝나면 사라지는 플레이어)
static func play_at(node: Node2D, stream: AudioStream, volume_db: float = 0.0) -> void:
	if not enabled or stream == null or node == null or not node.is_inside_tree() or Engine.is_editor_hint():
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.max_distance = MAX_DISTANCE
	p.attenuation = 1.0
	node.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func clear_cache() -> void:
	_cache.clear()
