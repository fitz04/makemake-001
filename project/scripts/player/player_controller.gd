## PlayerController - 1인칭 캐릭터 컨트롤러
##
## Project Nomad 코딩 컨벤션:
##   - snake_case: 변수, 함수
##   - PascalCase: 클래스, 노드
##   - UPPER_SNAKE_CASE: 상수, enum 값
##   - @onready: 노드 참조에 사용
##   - 타입 힌트: 모든 변수와 함수 반환값에 명시
##
## 이 컨트롤러는 구면 중력(spherical gravity)을 지원합니다.
## 왜소행성 표면에서 0.64 m/s^2 중력으로 동작합니다.
##
## 노드 구조 (예상):
##   PlayerController (CharacterBody3D)
##   ├── CollisionShape3D
##   ├── Head (Node3D)
##   │   └── Camera3D
##   └── InteractionRay (RayCast3D)
class_name PlayerController
extends CharacterBody3D


# --- 시그널 ---

## 상호작용 대상이 변경되었을 때
signal interaction_target_changed(target: Node)

## 플레이어가 착지했을 때
signal landed()


# --- 익스포트 변수 ---

## 이동 속도 (m/s) - 저중력 환경에서의 보행 속도
@export var move_speed: float = 3.0

## 달리기 속도 배율
@export var sprint_multiplier: float = 1.6

## 점프 속도 (m/s) - 저중력에서 높이 뛰므로 작은 값
@export var jump_velocity: float = 2.5

## 마우스 감도
@export var mouse_sensitivity: float = 0.003

## 최대 카메라 상하 각도 (도)
@export var max_look_angle: float = 89.0

## 상호작용 거리 (m)
@export var interaction_distance: float = 3.0


# --- 노드 참조 ---

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_ray: RayCast3D = $InteractionRay


# --- 상태 변수 ---

## 구면 중력 사용 여부
var use_spherical_gravity: bool = true

## 행성 중심 좌표 (구면 중력 계산용)
var planet_center: Vector3 = Vector3.ZERO

## 현재 중력 벡터 (매 프레임 갱신)
var gravity_direction: Vector3 = Vector3.DOWN

## 현재 중력 가속도
var gravity_strength: float = GameManager.SURFACE_GRAVITY

## 지면 접촉 여부
var _is_on_floor_custom: bool = false

## 현재 상호작용 대상
var _current_interaction_target: Node = null


# --- 라이프사이클 ---

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if interaction_ray:
		interaction_ray.target_position = Vector3(0, 0, -interaction_distance)


func _unhandled_input(event: InputEvent) -> void:
	# 마우스 시점 제어
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_handle_mouse_look(event as InputEventMouseMotion)

	# ESC로 마우스 해제/캡처 토글
	if event.is_action_pressed("pause"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			GameManager.change_state(GameManager.GameState.PAUSED)
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			GameManager.change_state(GameManager.GameState.PLAYING)


func _physics_process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	_update_gravity()
	_apply_movement(delta)
	_check_interaction()
	move_and_slide()


# --- 내부 메서드 ---

## 마우스 시점 처리
func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	# 좌우 회전: 플레이어 전체 회전 (구면 중력에서는 up 벡터 기준)
	rotate_object_local(Vector3.UP, -event.relative.x * mouse_sensitivity)

	# 상하 회전: Head 노드만 회전
	if head:
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x,
			deg_to_rad(-max_look_angle),
			deg_to_rad(max_look_angle)
		)


## 중력 벡터 갱신 (구면 중력)
func _update_gravity() -> void:
	if use_spherical_gravity:
		# 행성 중심에서 플레이어 방향으로의 벡터 = "위"
		var to_player := global_position - planet_center
		if to_player.length_squared() > 0.001:
			gravity_direction = -to_player.normalized()

			# 플레이어의 up 벡터를 중력 반대 방향으로 정렬
			var target_up := -gravity_direction
			_align_to_surface(target_up)
	else:
		gravity_direction = Vector3.DOWN


## 캐릭터 up 벡터를 표면 법선에 정렬
func _align_to_surface(target_up: Vector3) -> void:
	var current_up := global_transform.basis.y
	if current_up.dot(target_up) < 0.9999:
		var angle := current_up.angle_to(target_up)
		var axis := current_up.cross(target_up).normalized()
		if axis.length_squared() > 0.001:
			# 부드러운 보간으로 정렬 (즉각 정렬하면 어지러움)
			var rotation_amount := minf(angle, 5.0 * get_physics_process_delta_time())
			global_transform.basis = global_transform.basis.rotated(axis, rotation_amount)
			global_transform.basis = global_transform.basis.orthonormalized()

	up_direction = target_up


## 이동 입력 처리 및 물리 적용
func _apply_movement(delta: float) -> void:
	# 중력 적용
	if not is_on_floor():
		velocity += gravity_direction * gravity_strength * delta
	else:
		if not _is_on_floor_custom:
			_is_on_floor_custom = true
			landed.emit()

	if not is_on_floor():
		_is_on_floor_custom = false

	# 입력 방향 계산
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# 속도 계산
	var current_speed := move_speed
	if Input.is_action_pressed("sprint"):
		current_speed *= sprint_multiplier

	# 이동 적용
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed * delta * 8.0)
		velocity.z = move_toward(velocity.z, 0, current_speed * delta * 8.0)

	# 점프
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity += -gravity_direction * jump_velocity


## 상호작용 대상 확인
func _check_interaction() -> void:
	if not interaction_ray:
		return

	var new_target: Node = null
	if interaction_ray.is_colliding():
		var collider := interaction_ray.get_collider()
		if collider and collider.has_method("get_interaction_prompt"):
			new_target = collider

	if new_target != _current_interaction_target:
		_current_interaction_target = new_target
		interaction_target_changed.emit(_current_interaction_target)

	# 상호작용 실행
	if _current_interaction_target and Input.is_action_just_pressed("interact"):
		if _current_interaction_target.has_method("interact"):
			_current_interaction_target.interact(self)
