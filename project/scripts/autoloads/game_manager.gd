## GameManager - 전역 게임 상태 관리 싱글톤
##
## Project Nomad 코딩 컨벤션:
##   - snake_case: 변수, 함수
##   - PascalCase: 클래스, 노드
##   - UPPER_SNAKE_CASE: 상수, enum 값
##   - @onready: 노드 참조에 사용
##   - 타입 힌트: 모든 변수와 함수 반환값에 명시
##   - 시그널: 과거형 이름 사용 (state_changed, item_collected)
##   - 주석: 한국어 또는 영어, 일관성 유지
##
## 이 파일은 project.godot에서 AutoLoad로 등록됨.
## 접근: GameManager.current_act, GameManager.change_state(...) 등
extends Node


# --- 시그널 ---

## 게임 상태가 변경되었을 때
signal state_changed(old_state: GameState, new_state: GameState)

## Act가 변경되었을 때
signal act_changed(act: int)

## 사기(morale) 수치가 변경되었을 때
signal morale_changed(value: float)


# --- 상수 ---

## 게임 상태 enum
enum GameState {
	NONE,
	MAIN_MENU,
	PLAYING,
	PAUSED,
	CUTSCENE,
	GAME_OVER,
}

## 중력 가속도 (m/s^2) - 카이퍼벨트 왜소행성 표면
## 800km 직경 기준, 실제 세레스(0.28) 참조하되 게임플레이용 조정
const SURFACE_GRAVITY: float = 0.64

## Act 번호 범위
const ACT_MIN: int = 1
const ACT_MAX: int = 4


# --- 상태 변수 ---

## 현재 게임 상태
var current_state: GameState = GameState.NONE

## 현재 Act (1-4)
var current_act: int = 1

## 플레이어 사기 수치 (0.0 ~ 1.0)
## 후처리 파이프라인에서 채도/렌즈 플레어에 연동
var morale: float = 0.5:
	set(value):
		morale = clampf(value, 0.0, 1.0)
		morale_changed.emit(morale)

## 총 플레이 시간 (초)
var total_play_time: float = 0.0

## 게임 데이터 (저장/로드용)
var game_data: Dictionary = {}


# --- 라이프사이클 ---

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_initialize_game_data()


func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		total_play_time += delta


# --- 공개 메서드 ---

## 게임 상태 변경
func change_state(new_state: GameState) -> void:
	if new_state == current_state:
		return
	var old_state := current_state
	current_state = new_state
	state_changed.emit(old_state, new_state)

	match new_state:
		GameState.PAUSED:
			get_tree().paused = true
		GameState.PLAYING:
			get_tree().paused = false


## Act 변경
func set_act(act: int) -> void:
	act = clampi(act, ACT_MIN, ACT_MAX)
	if act != current_act:
		current_act = act
		act_changed.emit(current_act)


## 게임 데이터 초기화
func _initialize_game_data() -> void:
	game_data = {
		"player": {
			"position": Vector3.ZERO,
			"oxygen": 1.0,
			"health": 1.0,
		},
		"power": {
			"current_source": "rtg",
			"total_output_kw": 0.5,
		},
		"printer": {
			"tier": 0,  # Mk.0
		},
		"kai": {
			"relationship": 0.0,
			"dialogue_flags": {},
		},
	}


## 세이브 데이터를 딕셔너리로 직렬화
func serialize() -> Dictionary:
	return {
		"current_act": current_act,
		"morale": morale,
		"total_play_time": total_play_time,
		"game_data": game_data,
	}


## 딕셔너리에서 게임 상태 복원
func deserialize(data: Dictionary) -> void:
	current_act = data.get("current_act", 1)
	morale = data.get("morale", 0.5)
	total_play_time = data.get("total_play_time", 0.0)
	game_data = data.get("game_data", {})
