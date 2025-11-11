# Fire-Ice Basin Crater Implementation

## 개요 (Overview)

Makemake 행성 남쪽에 **Fire-Ice Basin** 크레이터를 추가했습니다. 이 크레이터는 실제로 지형이 움푹 파인 형태로 구현되어 있으며, 셰이더에서 색상도 다르게 표시됩니다.

**위치:** 남쪽 -4500m (Z축)
**반경:** 1800m
**깊이:** 200m
**색상:** 어두운 갈색 (Dark brown - old tholin)

---

## 변경된 파일 (Modified Files)

### 1. `solar_system/voxel_graph_planet_v4.tres`

크레이터 지형을 생성하기 위해 8개의 새로운 노드를 추가했습니다.

#### 추가된 노드 (Added Nodes)

| 노드 ID | 이름 | 타입 | 설명 | 파라미터 |
|---------|------|------|------|----------|
| **70** | `crater_z_offset` | Subtract | 크레이터 중심까지 Z 오프셋 계산 | `b = -4500.0` |
| **71** | `crater_x_squared` | Multiply | X 좌표 제곱 (거리 계산용) | - |
| **72** | `crater_z_squared` | Multiply | Z 오프셋 제곱 (거리 계산용) | - |
| **73** | `crater_distance_squared` | Add | X² + Z² 합산 | - |
| **74** | `crater_distance` | Sqrt | 크레이터 중심까지의 거리 | - |
| **75** | `crater_falloff` | Smoothstep | 크레이터 가장자리 부드럽게 처리 | `edge0 = 1800.0`<br>`edge1 = 0.0` |
| **76** | `crater_depth` | Multiply | 크레이터 깊이 (-200m) | `b = -200.0` |
| **77** | `final_terrain_with_crater` | Add | 기존 지형과 크레이터 결합 | - |

#### 추가된 연결 (Added Connections)

```
[4, 0, 70, 0]     - InputZ → crater_z_offset
[2, 0, 71, 0]     - InputX → crater_x_squared (input a)
[2, 0, 71, 1]     - InputX → crater_x_squared (input b)
[70, 0, 72, 0]    - crater_z_offset → crater_z_squared (input a)
[70, 0, 72, 1]    - crater_z_offset → crater_z_squared (input b)
[71, 0, 73, 0]    - crater_x_squared → crater_distance_squared
[72, 0, 73, 1]    - crater_z_squared → crater_distance_squared
[73, 0, 74, 0]    - crater_distance_squared → crater_distance (sqrt)
[74, 0, 75, 0]    - crater_distance → crater_falloff (smoothstep)
[75, 0, 76, 0]    - crater_falloff → crater_depth
[76, 0, 77, 1]    - crater_depth → final_terrain_with_crater
[60, 0, 77, 0]    - existing terrain → final_terrain_with_crater
[77, 0, 1, 0]     - final_terrain_with_crater → OutputSDF
```

#### 노드 플로우 (Node Flow)

```
InputZ (4) ──────┐
                 │
                 ├─> Subtract (70) ─┬─> Multiply (72) ──┐
                 │   [Z - (-4500)]   │   [offset_Z²]     │
                 │                   │                   │
InputX (2) ──────┼───────────────────┼─> Multiply (71) ──┤
                 │                   │   [X²]            │
                 │                   │                   │
                 │                   └─> Add (73) ───────┤
                 │                       [X² + Z²]       │
                 │                                       │
                 │                       Sqrt (74) ──────┤
                 │                       [distance]      │
                 │                                       │
                 │                       Smoothstep (75) ┤
                 │                       [falloff 0-1]   │
                 │                                       │
                 │                       Multiply (76) ──┤
                 │                       [×(-200m)]      │
                 │                                       │
Terrain (60) ────┴─────────────────────> Add (77) ──────> Output (1)
[caves+ravines]                          [final]
```

---

## 작동 원리 (How It Works)

### 1. 거리 계산 (Distance Calculation)

크레이터는 XZ 평면(수평면)에서 중심점 `(0, 0, -4500)`으로부터의 2D 거리를 계산합니다:

```
offset_Z = Z - (-4500) = Z + 4500
distance = sqrt(X² + offset_Z²)
```

### 2. 부드러운 감쇠 (Smooth Falloff)

Smoothstep 함수를 사용해 크레이터 가장자리를 부드럽게 처리:

- **중심 (distance = 0)**: falloff = 1.0 (최대 깊이)
- **가장자리 (distance = 1800)**: falloff = 0.0 (깊이 없음)
- **중간 영역**: 부드러운 곡선으로 전환

### 3. 깊이 적용 (Depth Application)

```
crater_depth = falloff × (-200m)
```

중심에서 최대 200m 깊이, 가장자리로 갈수록 0m까지 감소합니다.

### 4. 지형 결합 (Terrain Combination)

```
final_terrain = existing_terrain + crater_depth
```

기존 지형 (동굴, 협곡 등)에 크레이터 깊이를 더해 최종 지형 생성.

---

## 게임 내 위치 (In-Game Location)

### 찾아가는 방법:

1. **스폰 지점에서 남쪽으로 이동**
   - Landing Basin (스폰 지점, 밝은 크림색)에서 출발
   - 남쪽 방향 (Z축 음수 방향)으로 약 4500m 이동

2. **시각적 특징:**
   - 지형이 200m 깊이로 움푹 파여 있음
   - 색상이 어두운 갈색 (Dark brown)으로 변함
   - 반경 1800m의 큰 원형 분화구

3. **좌표:**
   - 중심: `(X: 0, Z: -4500)`
   - 반경: 1800m 이내

---

## 셰이더 색상 (Shader Colors)

크레이터 영역은 셰이더에서 별도의 색상으로 렌더링됩니다:

**파일:** `solar_system/materials/planet_ground.gdshader`

```glsl
// Line 19-20: Crater center and radius
uniform vec3 u_fire_ice_center = vec3(0.0, 0.0, -4500.0);
uniform float u_fire_ice_radius = 1800.0;

// Line 28: Crater color (dark brown)
uniform vec3 u_fire_ice_color : source_color = vec3(0.65, 0.55, 0.50);

// Line 164-167: Biome detection
else if (dist_to_fire_ice < u_fire_ice_radius) {
    float crater_blend = smoothstep(u_fire_ice_radius - 400.0, u_fire_ice_radius, dist_to_fire_ice);
    biome_color = mix(u_fire_ice_color, u_cryo_plains_color, crater_blend);
}
```

---

## 파라미터 조정 (Parameter Tuning)

### 크레이터 크기 변경:

**파일:** `solar_system/voxel_graph_planet_v4.tres`

```
"75": {
    "edge0": 1800.0,  ← 이 값을 변경하면 크레이터 반경 조정
    ...
}
```

### 크레이터 깊이 변경:

```
"76": {
    "b": -200.0,  ← 이 값을 변경하면 크레이터 깊이 조정 (음수 = 아래로)
    ...
}
```

### 크레이터 위치 변경:

```
"70": {
    "b": -4500.0,  ← 이 값을 변경하면 Z축 위치 조정
    ...
}
```

X축 위치를 변경하려면 노드 71에 Subtract 노드를 추가해야 합니다.

---

## 기술적 세부사항 (Technical Details)

### Smoothstep 함수 동작:

Godot의 Smoothstep은 다음과 같이 동작합니다:

```glsl
smoothstep(edge0, edge1, x) = {
    0.0                if x <= edge0
    3t² - 2t³          if edge0 < x < edge1  (where t = (x-edge0)/(edge1-edge0))
    1.0                if x >= edge1
}
```

우리는 `edge0 = 1800`, `edge1 = 0`으로 설정해 **역방향** smoothstep을 사용:
- x = 0 (중심) → t = 1.0
- x = 1800 (가장자리) → t = 0.0

### SDF (Signed Distance Field) 방식:

Voxel Terrain은 SDF를 사용해 지형을 생성합니다:
- **음수 값**: 지형 내부 (solid)
- **양수 값**: 지형 외부 (air)
- **0**: 지형 표면

크레이터는 `-200m` 값을 더해 지형을 아래로 밀어냅니다.

---

## 테스트 방법 (Testing)

### 1. 게임 실행

```bash
cd /home/user/makemake-001
godot --path . solar_system/solar_system.tscn
```

### 2. 크레이터로 이동

- W/A/S/D 키로 남쪽 방향 이동
- 좌표 확인: HUD에 현재 위치 표시
- 색상 변화 확인: 밝은 색 → 어두운 갈색

### 3. 지형 확인

- 표면이 실제로 200m 아래로 파여 있는지 확인
- 가장자리가 부드럽게 경사져 있는지 확인

---

## 향후 개선 사항 (Future Improvements)

### 1. 크레이터 림 (Crater Rim)

가장자리에 약간 솟은 테두리 추가:

```
- 추가 노드: Smoothstep (좁은 범위)
- 높이: +20~30m
- 위치: 반경 1700~1900m 영역
```

### 2. 내부 노이즈 (Interior Noise)

크레이터 바닥에 작은 굴곡 추가:

```
- FastNoise3D 노드 추가
- Scale: 작은 주기 (50-100m)
- Amplitude: ±10m
```

### 3. 중앙 봉우리 (Central Peak)

큰 크레이터의 특징인 중앙 융기 추가:

```
- Gaussian-like bump at center
- Height: +50m
- Radius: 300m
```

---

## 문제 해결 (Troubleshooting)

### 크레이터가 보이지 않는 경우:

1. **데이터베이스 캐시 삭제:**
   ```bash
   rm -rf debug_data/Makemake.sqlite*
   ```

2. **게임 재시작**

3. **올바른 위치로 이동했는지 확인**
   - Z 좌표가 -3000 ~ -6000 범위인지 확인

### 크레이터 모양이 이상한 경우:

- Voxel LOD 설정 확인
- Mesh block size 확인 (현재 32)
- View distance 충분한지 확인

---

## 관련 파일 (Related Files)

```
solar_system/voxel_graph_planet_v4.tres      - 크레이터 지형 노드 (이 파일 수정함)
solar_system/materials/planet_ground.gdshader - 크레이터 색상 셰이더
solar_system/solar_system_setup.gd           - 크레이터 파라미터 설정
BIOME_IMPLEMENTATION.md                       - 바이옴 시스템 전체 가이드
```

---

## 커밋 정보 (Commit Info)

**변경 사항:**
- `voxel_graph_planet_v4.tres`: 노드 8개 추가 (70-77), 연결 13개 추가
- `CRATER_IMPLEMENTATION.md`: 이 문서 작성

**구현 날짜:** 2025-11-11

---

## 요약 (Summary)

✅ **완료된 작업:**
- Fire-Ice Basin 크레이터 지형 생성 (200m 깊이, 1800m 반경)
- 크레이터 중심 위치: 남쪽 -4500m
- 부드러운 가장자리 처리 (Smoothstep)
- 기존 지형(동굴, 협곡)과 자연스럽게 결합
- 셰이더 색상과 동기화

🎮 **게임 내 효과:**
- 남쪽으로 이동하면 큰 분화구 발견
- 지형이 실제로 움푹 파여 있음
- 색상이 어두운 갈색으로 변화
- 크레이터 바닥으로 내려갈 수 있음

📐 **기술적 구현:**
- 8개의 Voxel Graph 노드 체인
- XZ 평면 거리 계산 (2D distance)
- Smoothstep 기반 falloff
- SDF Add 방식으로 지형 결합

---

**제작자:** Claude Code
**프로젝트:** Makemake Dwarf Planet Exploration Game
