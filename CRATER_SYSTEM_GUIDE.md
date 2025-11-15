# Crater Generation System Guide

## 개요

이 시스템은 Voxel 지형에 여러 개의 크레이터를 동적으로 추가할 수 있게 해줍니다. 각 크레이터는:
- **보울(Bowl)**: 움푹 패인 분지
- **림(Rim)**: 가장자리의 융기된 산맥

으로 구성됩니다.

## 파일 구조

```
solar_system/
├── voxel_graph_planet_v5.tres     # 새로운 깨끗한 베이스 그래프
├── crater_generator.gd             # 크레이터 생성 유틸리티
└── solar_system_setup.gd           # 여기서 크레이터를 추가
```

## 기본 사용법

### 1. solar_system_setup.gd에서 크레이터 추가

```gdscript
func setup_planet_terrain():
    var graph = load("res://solar_system/voxel_graph_planet_v5.tres") as VoxelGeneratorGraph

    # 크레이터 생성기 초기화
    var crater_gen = CraterGenerator.new()

    # 크레이터 정의
    var craters = [
        # Landing Basin - 스폰 지점 크레이터
        CraterGenerator.CraterDef.new(
            Vector3(0, 0, 0),      # 중심 (X, Y, Z)
            1200.0,                # 반지름
            250.0,                 # 깊이
            45.0                   # 림 높이
        ),

        # 북쪽 큰 크레이터
        CraterGenerator.CraterDef.new(
            Vector3(0, 0, 3500),   # 북쪽 3.5km
            800.0,
            180.0,
            30.0
        ),

        # 서쪽 작은 크레이터
        CraterGenerator.CraterDef.new(
            Vector3(-2000, 0, 500),
            400.0,
            100.0,
            20.0
        )
    ]

    # 그래프에 크레이터 추가
    crater_gen.add_craters_to_graph(graph, craters)

    # VoxelTerrain에 적용
    voxel_terrain.generator = graph
```

## 크레이터 파라미터 상세 설명

### 필수 파라미터

```gdscript
CraterGenerator.CraterDef.new(center, radius, depth, rim_height)
```

| 파라미터 | 타입 | 설명 | 예시 |
|---------|------|------|------|
| `center` | Vector3 | 크레이터 중심 좌표 (Y는 보통 0) | `Vector3(1000, 0, 2000)` |
| `radius` | float | 크레이터 외곽 반지름 (효과가 사라지는 지점) | `1200.0` |
| `depth` | float | 크레이터 깊이 (양수 입력, 자동으로 음수 변환) | `250.0` |
| `rim_height` | float | 가장자리 융기 높이 | `45.0` |

### 선택적 파라미터 (고급)

크레이터를 생성한 후 세밀하게 조정할 수 있습니다:

```gdscript
var crater = CraterGenerator.CraterDef.new(Vector3.ZERO, 1200, 250, 45)

# 평평한 바닥 크기 조정 (기본값: radius * 0.5)
crater.bowl_flat_radius = 500.0  # 더 넓은 평지

# 림 시작/끝 지점 조정
crater.rim_start_radius = 1000.0  # 림이 시작되는 거리 (기본: radius * 0.83)
crater.rim_end_radius = 1400.0    # 림이 끝나는 거리 (기본: radius * 1.08)
```

### 파라미터 효과 다이어그램

```
           림(Rim)
              ↓
         __/‾‾‾\__
      __/          \__
   __/                \__
  /     보울(Bowl)       \
 |   <-flat_radius->     |
 |                       |
 |_______________________|

 |<--- radius --->|
        |<-rim_start
              |<-rim_end
```

## 크레이터 크기 가이드

실제 천체의 크레이터 크기 참고:

| 크기 분류 | 반지름 | 깊이 | 림 높이 | 용도 |
|----------|--------|------|---------|------|
| 소형 | 100-300m | 20-50m | 5-15m | 작은 충돌흔적 |
| 중형 | 300-800m | 50-150m | 15-30m | 일반적인 크레이터 |
| 대형 | 800-2000m | 150-300m | 30-60m | 주요 랜드마크 |
| 거대 | 2000m+ | 300m+ | 60m+ | 충돌 분지 |

## 노드 구조 설명

각 크레이터는 다음 노드들로 구성됩니다:

### 1. 거리 계산 (Distance Calculation)
```
InputX ──→ Subtract ──→ Multiply ──┐
               ↓          (자기 자신)  │
          (중심 X)                  Add ──→ Sqrt ──→ distance
                                    │
InputZ ──→ Subtract ──→ Multiply ──┘
               ↓          (자기 자신)
          (중심 Z)
```

**역할**: 각 복셀에서 크레이터 중심까지의 2D 거리 계산

### 2. 보울 (Bowl/Depression)
```
distance ──→ Smoothstep ──→ Multiply ──→ bowl_depth
                ↓              ↓
           (edge0, edge1)  (depth 값)
```

**역할**:
- Smoothstep: 거리에 따라 0→1로 부드럽게 변화
- edge0 (flat_radius): 이 거리까지는 완전히 평평한 바닥
- edge1 (radius): 이 거리에서 효과 종료
- Multiply: 깊이 값을 곱해서 실제 지형 변형 생성

### 3. 림 (Rim/Uplift)
```
distance ──→ Smoothstep ──→ Multiply ──→ rim_height
                ↓              ↓
        (rim_start, rim_end) (height 값)
```

**역할**:
- rim_start: 림 융기 시작 지점
- rim_end: 림 융기 종료 지점
- 이 구간에서만 지형이 위로 솟아오름

### 4. 지형 합성 (Terrain Combination)
```
base_terrain ──→ Add(bowl) ──→ Add(rim) ──→ next_crater...
                    ↑              ↑
              bowl_depth      rim_height
```

**역할**: 모든 크레이터를 기본 지형에 순차적으로 추가

## 커스터마이징 가이드

### 크레이터 주변에 규산 먼지 추가

쉐이더에서 크레이터 거리를 이용:

```glsl
// planet_ground.gdshader에서
uniform vec3 u_crater_centers[10];  // 최대 10개 크레이터
uniform float u_crater_radii[10];
uniform int u_crater_count;

// Fragment shader
float min_crater_dist = 99999.0;
for (int i = 0; i < u_crater_count; i++) {
    vec2 crater_xz = u_crater_centers[i].xz;
    float dist = length(v_local_pos.xz - crater_xz);
    float normalized_dist = dist / u_crater_radii[i];
    min_crater_dist = min(min_crater_dist, normalized_dist);
}

// 크레이터 가까이 있을수록 더 많은 먼지
float dust_factor = smoothstep(1.5, 0.8, min_crater_dist);
vec3 dust_color = vec3(0.8, 0.75, 0.7);
ALBEDO = mix(ALBEDO, dust_color, dust_factor * 0.3);
```

### 크레이터 나이 효과 (침식)

오래된 크레이터는 더 완만하게:

```gdscript
# 새 크레이터
var fresh_crater = CraterGenerator.CraterDef.new(pos, 800, 200, 40)
fresh_crater.bowl_flat_radius = 400  # 날카로운 바닥
fresh_crater.rim_height = 40  # 높은 림

# 오래된 크레이터 (침식됨)
var old_crater = CraterGenerator.CraterDef.new(pos, 800, 120, 15)
old_crater.bowl_flat_radius = 600  # 넓고 완만한 바닥
old_crater.rim_height = 15  # 낮은 림
```

### 불규칙한 크레이터 (비대칭)

현재는 완벽한 원형입니다. 불규칙하게 만들려면:

1. **노이즈 추가 방식**:
```gdscript
# crater_generator.gd의 _create_crater_nodes에서
# distance 계산 후 노이즈를 더함:

# 노이즈 노드 추가
var noise_id = node_id + 10
graph.add_node(noise_id, "FastNoise2D", ...)
# distance + noise → 불규칙한 거리
```

2. **타원형 크레이터**:
```gdscript
# X와 Z 방향에 다른 스케일 적용
# X 방향: 1.0 배율
# Z 방향: 1.5 배율 → 타원형
```

### 크레이터 겹침 처리

현재는 Add로 단순히 더합니다. 더 자연스럽게 하려면:

```gdscript
# _combine_craters_with_terrain 함수에서
# Add 대신 Min 사용:
graph.add_node(combined_id, "Min", ...)  # 가장 낮은 값만 적용

# 또는 SdfSmoothUnion 사용:
graph.add_node(combined_id, "SdfSmoothUnion", ...)
graph.set_node_param(combined_id, 2, 50.0)  # smoothness
```

## 바이옴 시스템과 통합

크레이터를 바이옴 마스크로 사용:

### 1. solar_system_setup.gd에서 쉐이더에 전달
```gdscript
func _pass_crater_data_to_shader():
    var material = planet_mesh.material as ShaderMaterial

    # 크레이터 정보 배열로 전달
    var centers = PackedVector3Array()
    var radii = PackedFloat32Array()

    for crater in craters:
        centers.append(crater.center)
        radii.append(crater.radius)

    material.set_shader_parameter("u_crater_centers", centers)
    material.set_shader_parameter("u_crater_radii", radii)
    material.set_shader_parameter("u_crater_count", craters.size())
```

### 2. 쉐이더에서 크레이터별 바이옴 적용
```glsl
// 각 크레이터마다 다른 색상
vec3 crater_colors[3] = {
    vec3(0.7, 0.6, 0.5),  # Landing Basin - 밝은 얼음
    vec3(0.4, 0.3, 0.25), # Old crater - 어두운 흙
    vec3(0.8, 0.3, 0.2)   # Fresh crater - 붉은 암석
};

for (int i = 0; i < u_crater_count; i++) {
    float dist = length(v_local_pos.xz - u_crater_centers[i].xz);
    if (dist < u_crater_radii[i]) {
        float blend = smoothstep(u_crater_radii[i] - 200.0, u_crater_radii[i], dist);
        biome_color = mix(crater_colors[i], biome_color, blend);
    }
}
```

## 성능 최적화

### 1. LOD (Level of Detail)
멀리 있는 크레이터는 단순화:
```gdscript
var player_pos = player.global_position

for crater_def in all_craters:
    var dist_to_player = crater_def.center.distance_to(player_pos)

    # 플레이어 근처 크레이터만 상세하게
    if dist_to_player < 5000:
        detailed_craters.append(crater_def)
    elif dist_to_player < 15000:
        # 간단한 버전 (림 없음)
        var simple = crater_def.duplicate()
        simple.rim_height = 0
        simple_craters.append(simple)
    # 그 외는 무시
```

### 2. 지역별 크레이터 배치
특정 지역에만 크레이터를 생성:
```gdscript
# "Ancient Impact Zone"에만 크레이터 집중
func generate_craters_in_region(region_center: Vector3, region_radius: float, crater_count: int):
    var craters = []
    for i in range(crater_count):
        var angle = randf() * TAU
        var distance = randf() * region_radius
        var pos = region_center + Vector3(
            cos(angle) * distance,
            0,
            sin(angle) * distance
        )

        var size = randf_range(200, 800)
        craters.append(CraterGenerator.CraterDef.new(
            pos,
            size,
            size * 0.25,  # 깊이는 반지름의 25%
            size * 0.05   # 림은 반지름의 5%
        ))
    return craters
```

## 문제 해결

### 크레이터가 보이지 않음
1. 깊이가 지형 노이즈보다 크거나 같은지 확인
2. 반지름이 너무 작지 않은지 확인 (최소 100m 권장)
3. 림 높이가 0보다 큰지 확인

### 크레이터가 너무 날카로움
- `bowl_flat_radius`를 줄이기
- `rim_start_radius`와 `rim_end_radius` 간격 늘리기

### 성능 저하
- 크레이터 개수를 50개 이하로 제한
- LOD 시스템 사용
- 노이즈 octave 줄이기 (기본 지형)

## 예제: 완전한 행성 설정

```gdscript
# solar_system_setup.gd
func setup_makemake_terrain():
    var graph = load("res://solar_system/voxel_graph_planet_v5.tres")
    var crater_gen = CraterGenerator.new()

    # 주요 랜드마크 크레이터
    var major_craters = [
        CraterGenerator.CraterDef.new(Vector3(0, 0, 0), 1200, 250, 45),      # Landing Basin
        CraterGenerator.CraterDef.new(Vector3(0, 0, -4500), 1800, 350, 60),  # South Pole Basin
    ]

    # 중형 크레이터 랜덤 배치
    var medium_craters = _generate_random_craters(20, 400, 800)

    # 소형 크레이터 랜덤 배치
    var small_craters = _generate_random_craters(50, 100, 300)

    # 모두 합치기
    var all_craters = major_craters + medium_craters + small_craters

    # 그래프에 추가
    crater_gen.add_craters_to_graph(graph, all_craters)

    voxel_terrain.generator = graph

func _generate_random_craters(count: int, min_size: float, max_size: float) -> Array:
    var craters = []
    var planet_radius = 8000.0

    for i in range(count):
        # 구면 위 랜덤 포인트
        var theta = randf() * TAU
        var phi = randf() * PI
        var r = planet_radius * 0.9  # 표면보다 약간 안쪽

        var pos = Vector3(
            r * sin(phi) * cos(theta),
            0,  # Y는 무시 (2D 투영)
            r * sin(phi) * sin(theta)
        )

        var size = randf_range(min_size, max_size)
        craters.append(CraterGenerator.CraterDef.new(
            pos,
            size,
            size * randf_range(0.2, 0.3),   # 깊이 변동
            size * randf_range(0.03, 0.07)  # 림 높이 변동
        ))

    return craters
```

## 다음 단계

1. **바이옴 시스템**: 크레이터 위치에 따라 색상/텍스처 변경
2. **동적 로딩**: 플레이어 주변 크레이터만 로드
3. **침식 시뮬레이션**: 시간에 따른 크레이터 변화
4. **암석 분포**: 크레이터 림에 큰 바위 배치
5. **동굴 시스템**: 크레이터 아래 용암 동굴

궁금한 점이 있으면 언제든지 물어보세요!
