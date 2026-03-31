# makemake-001 코드 리뷰 보고서

**리뷰 대상:** `/mnt/c/Users/fitzz/Documents/godot/makemake-001/`
**리뷰 일자:** 2026-03-30
**리뷰어:** Claude Opus 4.6 (시니어 Godot/VoxelTools 코드 리뷰)

---

## 1. 아키텍처 진단

### 1.1 전체 구조 요약

이 프로젝트는 Zylann의 Solar System 데모를 기반으로 Makemake 왜행성 탐사 게임으로 분기시킨 것이다. 원본 데모는 여러 행성을 보여주는 것이 목적이었지만, 이 프로젝트는 단일 행성(Makemake)에 착륙하여 지형을 탐험하는 것으로 방향을 전환했다. 문제는 **원본 아키텍처를 그대로 유지한 채** 위에 새로운 기능(크레이터, 바이옴, 하이트맵 스탬프)을 계속 쌓아올렸다는 것이다.

### 1.2 의존성 그래프

```
main.gd
  └── SolarSystem (solar_system.gd) ← 신(God) 클래스
        ├── SolarSystemSetup (static) ← 600줄 팩토리+설정 혼합
        │     ├── StellarBody (데이터 클래스)
        │     ├── CraterGenerator (런타임 그래프 조작)
        │     ├── VoxelGeneratorGraph (v5.tres)
        │     └── planet_ground.gdshader
        ├── Ship (ship.gd)
        │     └── ShipController (ship_controller.gd)
        │           └── Character (캐릭터 스폰 시)
        └── Camera (camera.gd)

Character (character_controller.gd)
  ├── HeightmapItem (heightmap_item.gd)
  ├── RuntimeCraterPlacer (runtime_crater_placer.gd)
  │     └── CraterGenerator (재사용)
  └── SolarSystem 참조 (get_parent().get_parent() 하드코딩)
```

### 1.3 핵심 문제점

#### (1) SolarSystem이 God 클래스

`solar_system.gd`(540줄)가 다음 책임을 모두 떠안고 있다:
- 행성 생성 및 초기화
- 플레이어(우주선/캐릭터) 스폰 및 관리
- 궤도 시뮬레이션 (orbit physics)
- 레퍼런스 바디 전환 (floating origin)
- 그림자 거리 동적 조절
- 대기 해킹 처리
- 클라우드 품질 설정
- 캐릭터/우주선 설정 적용
- 디버그 출력
- 세이브/로드
- 일시정지 메뉴 연결

단일 행성 게임에서 이 복잡도는 불필요하다.

#### (2) SolarSystemSetup이 두 번째 God 클래스

`solar_system_setup.gd`(640줄)는 `static` 함수만으로 구성된 거대한 유틸리티 클래스다:
- 태양계 데이터 생성 (`create_solar_system_data`)
- 태양 설정 (`_setup_sun`)
- 바다 설정 (`_setup_sea`)
- 대기 설정 (`_setup_atmosphere`)
- 행성 지형 생성 (`_setup_rocky_planet`) ← 이 함수만 200줄 이상
- 크레이터 추가 (CraterGenerator 연계)
- 먼지 FogVolume 추가
- 인스턴싱(돌/자갈) 설정 (`_configure_instancing_for_planet`)

**결과:** 지형 생성 로직을 수정하려면 이 파일 안에서 크레이터 정의, 노이즈 파라미터, 셰이더 유니폼 설정, 인스턴서 설정을 모두 이해해야 한다.

#### (3) character_controller.gd에 기능이 너무 많이 들어있음

`character_controller.gd`(632줄)는 다음을 모두 처리한다:
- 이동 입력 처리
- 하이트맵 시스템 (로딩, 전환, 프리뷰)
- 지형 파기/쌓기 (dig/build)
- 웨이포인트 배치
- 시각적 업데이트 (visual root)
- 상호작용 (우주선 탑승)
- SDF 매장 감지 및 텔레포트
- RuntimeCraterPlacer 초기화

한 컨트롤러가 하이트맵 시스템 전체와 테스트용 하이트맵 생성 함수(`_create_test_heightmap_mountain`, `_create_test_heightmap_crater`, `_create_test_heightmap_plateau`)까지 품고 있다.

#### (4) 설정 전달 방식이 혼란스럽다

- **우주선 설정:** `@export` 프로퍼티에 직접 할당 (solar_system.gd `_apply_ship_settings`)
- **캐릭터 설정:** `set_meta()` 로 메타데이터로 전달 (solar_system.gd `_apply_character_settings`)
- **캐릭터 물리:** `character.gd`에서 `has_meta()`로 매 프레임 체크 후 전역 변수에 대입
- **하이트맵 설정:** `character_controller.gd`에서 `_get_settings()`로 solar_system._settings에 직접 접근 (private 멤버)

이 세 가지 방식이 하나의 프로젝트에서 혼재하고 있다. `_get_solar_system()`이 `get_parent().get_parent()` 하드코딩이라는 점도 주목.

#### (5) 코드 중복

- **하이트맵 적용 로직:** `character_controller.gd`의 `_dig_cmd` 처리와 `_build_cmd` 처리가 거의 동일한 40줄을 복붙하고 있다 (159-206행 vs 207-245행).
- **크레이터 정의:** `solar_system_setup.gd`에 6개 크레이터가 수동으로 정의되어 있고, `test_crater_system.gd`에 4개, `CRATER_SYSTEM_GUIDE.md`에 또 다른 3개가 있다. 어느 것이 실제 사용 중인지 혼란.
- **탄젠트 스페이스 계산:** `heightmap_item.gd`의 `_create_local_tangent_space()`가 독립적으로 구현되어 있는데, 이것은 voxel 시스템의 내장 기능과 중복될 가능성이 높다.

---

## 2. 지형 생성 파이프라인 진단

### 2.1 v4 vs v5 그래프: 왜 두 개가 있는가

| 특성 | v4 (voxel_graph_planet_v4.tres) | v5 (voxel_graph_planet_v5.tres) |
|------|------|------|
| 노드 수 | 40+ 개 | 5개 |
| 노이즈 | 셀룰러(7 octave) + 퍼린(6 octave) + 두 종류의 FastNoiseLite | 없음 |
| 지형 특징 | 산악, 협곡, 동굴, 크레이터(수동 1개) | 순수한 구(sphere)만 |
| 하이트맵 | Image2D 노드로 PNG 샘플링 | 없음 |
| 용도 | 이전 "완전체" 그래프 (사실상 폐기됨) | 새로운 "깨끗한" 시작점 |

**현재 코드(`solar_system_setup.gd:43`)는 v5를 사용:**
```gdscript
const BasePlanetVoxelGraph = preload("./voxel_graph_planet_v5.tres")
```

**v5의 내용물:**
```
InputX, InputY, InputZ -> SdfSphere (radius=8000) -> OutputSDF
```

이것은 말 그대로 **완벽한 구(sphere)**다. 노이즈도, 산맥도, 동굴도 없다. v4에 있던 복잡한 지형 생성(셀룰러 노이즈, 협곡, 동굴)이 모두 버려졌다.

### 2.2 왜 이렇게 되었는가: 경위 추적

개발 일지를 통해 경위를 재구성하면:

1. **원본(v4):** Zylann 데모에서 가져온 복잡한 지형 그래프. 셀룰러 노이즈로 날카로운 지형, 협곡, 동굴을 생성.
2. **문제 발생:** v4에 수동으로 크레이터 노드를 추가하려고 시도 (노드 70-80). 연결이 복잡해지고 디버깅이 어려워짐.
3. **v5 생성:** "깨끗한 시작점"으로 순수한 구만 남기고, CraterGenerator로 동적 크레이터 추가하는 방식으로 전환.
4. **결과:** v4의 복잡한 지형(산맥, 협곡, 동굴)이 모두 사라짐. v5는 **매끄러운 구 + 동적 크레이터**만 남음.

### 2.3 현재 노이즈 설정이 만들어내는 지형

**현재 v5 기반 실제 지형:**
- 반지름 8000m의 **완벽한 구**
- CraterGenerator가 런타임에 6개 크레이터 노드를 주입 (bowl + rim)
- 크레이터 외의 지역은 **완전히 매끄럽다** (노이즈 없음)

이것이 "지형이 원하는 모양이 아니다"의 근본 원인이다. **v4의 지형 복잡도를 포기했기 때문에 행성 표면이 밋밋한 구 위에 크레이터 몇 개만 있는 형태가 되었다.**

### 2.4 바이옴 시스템 분석

**셰이더(`planet_ground.gdshader`)의 바이옴 시스템은 순수하게 색상만 다르게 칠한다.** 지형 형상에는 전혀 영향을 주지 않는다.

현재 구현:
```glsl
// 높이 기반 바이옴만 동작
float height_from_surface = v_planet_height - u_planet_radius;
vec3 biome_color = u_cryo_plains_color;
if (height_from_surface > 50.0) {
    biome_color = mix(u_cryo_plains_color, u_ore_highlands_color, ...);
}
```

셰이더 코드를 보면 `u_landing_basin_center`, `u_fire_ice_center`, `u_canyon_min_x` 등의 유니폼이 선언되어 있지만, **fragment shader에서 이 값들을 사용하는 바이옴 분기 로직이 없다.** 오직 `height_from_surface > 50.0` 체크만 있다.

`solar_system_setup.gd`에서는 이 유니폼들에 값을 열심히 세팅하지만(248-272행), 셰이더가 해당 값을 무시하므로 **Landing Basin 색상, Fire-Ice 색상, Canyon 색상은 화면에 나타나지 않는다.**

### 2.5 셰이더의 추가 문제점

1. **크레이터 먼지 시스템이 2D 평면 기반:** `v_local_pos.xz`로 거리를 계산하므로 구면 행성에서는 정확하지 않다. 행성 표면의 대척점에도 먼지가 보일 수 있다.

2. **고정 EMISSION이 8%:** 모든 지형에 8% 자체발광이 걸려 있어 그림자가 있어도 완전히 어두워지지 않는다. 의도적일 수 있지만, 현실적인 Makemake 표현과는 거리가 있다.

3. **노멀맵이 비활성화 상태:** `volume.normalmap_enabled = false` - "크레이터와 청크 이음새에 아티팩트가 발생해서" 끈 상태다. 이로 인해 멀리서 지형 디테일이 떨어진다.

4. **에젝타 레이 시스템이 과도하게 복잡:** `calculate_crater_rays()` 함수가 60줄로, 각 프래그먼트에서 최대 10개 크레이터에 대해 레이 패턴을 계산한다. 성능 비용 대비 시각적 효과가 미미할 가능성이 높다.

### 2.6 **근본 원인 분석: 왜 원하는 지형이 안 나오는가**

1. **v5로 전환하면서 모든 자연 지형이 사라졌다.** v4의 셀룰러 노이즈, 협곡, 동굴이 v5에 이식되지 않았다.

2. **CraterGenerator는 "크레이터만" 추가한다.** 산맥, 언덕, 평원 같은 자연 지형은 생성하지 않는다. 완벽한 구 위에 크레이터만 있으면 "달"이 아니라 "크레이터가 뚫린 볼링공"이 된다.

3. **크레이터가 2D 평면(XZ) 기반으로 계산된다.** 구면 행성에서 XZ 거리를 쓰면 크레이터가 행성의 "적도" 부근에서만 올바르게 보인다. 극지방이나 행성 뒷면에 크레이터를 배치하면 원통형으로 뻗거나 왜곡된다. (이 문제는 `runtime_crater_placer.gd`의 주석에서도 인식하고 있다: "If we use 2D distance on a sphere, we get a cylinder.")

4. **v4의 지형은 "너무 거칠고", v5의 지형은 "너무 밋밋하다."** 중간 지점을 찾지 못한 채 두 극단을 오가다가 포기한 것으로 보인다.

---

## 3. 크레이터 시스템 진단

### 3.1 crater_generator.gd의 접근 방식과 한계

**접근 방식:** VoxelGeneratorGraph의 노드를 런타임에 프로그래밍 방식으로 추가한다. 각 크레이터마다 14개의 노드(거리 5개, bowl 4개, rim 4개, 상수 1개)를 생성하고 연결한다.

**근본적 한계:**

1. **스케일링 불가능:** 크레이터 하나당 14개 노드. 6개 크레이터 = 84개 노드. "수백 개"를 목표로 했지만 100개 크레이터 = 1400개 노드. VoxelGeneratorGraph는 매 복셀마다 이 모든 노드를 평가해야 한다. 성능이 기하급수적으로 저하된다.

2. **2D 거리 계산:** 앞서 지적한 대로, `InputX`와 `InputZ`만 사용하여 2D 거리를 계산한다. 구면 행성에서는 이 방식이 작동하지 않는다. Y축(수직)을 무시하므로 크레이터가 행성을 관통하는 원통형 형태가 된다.

3. **Smoothstep 파라미터 혼란:** 코드에 "SWAPPED" 주석이 있다:
   ```gdscript
   # SWAPPED: param order reversed - testing if Godot Voxel uses opposite convention
   graph.set_node_param(bowl_falloff_id, 0, crater.radius)  # was bowl_flat_radius
   graph.set_node_param(bowl_falloff_id, 1, crater.bowl_flat_radius)  # was radius
   ```
   이것은 Smoothstep의 edge0/edge1 순서를 시행착오로 뒤집어본 흔적이다. **정확한 동작을 이해하지 못한 채 "되는 방향"으로 맞추었다.**

4. **bowl과 rim이 SDF에 단순 Add로 결합된다.** SDF 값에 직접 더하는 방식은 지형 표면이 매끄러운 경우에만 올바르게 작동한다. 노이즈가 있는 지형에서는 크레이터 형태가 왜곡될 수 있다.

### 3.2 heightmap_item.gd의 문제

이 클래스는 외부 하이트맵 이미지(Gaea에서 생성한 .exr/.png)를 지형에 "스탬프"하는 기능이다.

**왜 제대로 작동하지 않는가:**

1. **SDF 수정 방식이 근본적으로 잘못되었다.** 하이트맵의 밝기 값을 SDF 값으로 직접 변환하려고 하는데, SDF(Signed Distance Field)에서 높이 변화를 적용하는 올바른 방법은 표면 법선 방향으로 SDF 등고선을 이동시키는 것이다. 현재 코드는:
   ```gdscript
   var new_sdf = distance_from_target / smooth_factor
   var blended_sdf = lerp(current_sdf, new_sdf, blend_factor)
   vt.set_voxel_f(voxel_pos, blended_sdf)
   ```
   이것은 기존 SDF 필드를 완전히 무시하고 새로운 값을 블렌딩하는 방식으로, 복셀 기하에 구멍을 내거나 예측 불가능한 형태를 만든다.

2. **3중 루프가 성능을 죽인다.** X루프 x Z루프 x Y루프(vertical_range). radius=70이면 약 140x140x40 = 약 80만 복셀을 수정한다. 각 복셀마다 `get_voxel_f()` + `set_voxel_f()`를 호출하므로 **수 초간 프리즈**가 발생한다.

3. **디버그 로깅이 과도하다.** `apply_to_terrain()`에 30줄 이상의 print문이 있다. 이미지 속성, 픽셀 샘플, 탄젠트 스페이스, 법선 등을 매번 출력한다. 이것은 "왜 안 되는지 모르겠다"의 흔적이다.

4. **UV 매핑이 평면 기반이다.** `_world_to_uv_relative()`가 XZ 평면 투영을 사용하므로, 구면 행성의 경사진 표면에서는 하이트맵이 왜곡된다.

### 3.3 runtime_crater_placer.gd의 문제

1. **런타임 그래프 수정은 지원되지 않는 사용법이다.** VoxelGeneratorGraph를 런타임에 수정하고 `apply_changes()`를 호출하는 것은 기술적으로 가능하지만, 실제로는:
   - 전체 지형을 재생성해야 함 (수 초간 프리즈)
   - 이미 생성된 청크의 캐시와 충돌 가능
   - 저장된 데이터와 새 제너레이터 결과가 불일치 가능

2. **코드 78-89줄의 주석이 문제를 정확히 진단하고 있다:** 작성자 자신이 "2D distance on a sphere would create a cylinder of craters through the planet"이라고 인식하면서도 해결하지 못했다.

3. **VoxelTerrain 검색이 너무 무식하다.** `_find_voxel_terrain()`이 씬 트리 전체를 재귀 탐색한다.

### 3.4 **근본 원인 분석: 왜 크레이터가 안 되는가**

**접근 방식 자체가 근본적으로 잘못되었다.** 세 가지 독립적인 크레이터 시스템을 시도했고, 세 가지 모두 실패했다:

| 시도 | 방식 | 실패 이유 |
|------|------|-----------|
| v4 수동 노드 | .tres 파일에 직접 노드 추가 | 복잡도 관리 불가, 디버깅 불가능 |
| CraterGenerator | 런타임 그래프 노드 동적 추가 | 2D 거리 계산, 스케일링 불가, Smoothstep 혼란 |
| HeightmapItem | SDF 직접 수정으로 스탬프 | SDF 이해 부족, 성능 문제, 평면 UV 왜곡 |

**올바른 접근법은:**
- **SDF 기반 구면 크레이터:** `SdfSphere`에서 3D 거리를 사용하고, 표면 법선 방향으로 bowl/rim 프로파일을 적용
- **또는 노이즈 기반 크레이터:** 워리 노이즈(Worley/Cellular)로 자연스러운 크레이터 분포 생성
- **또는 VoxelTool을 이용한 구면 파기:** `do_sphere()`로 지형을 깎는 방식 (이미 ShipController에서 사용 중)

---

## 4. 살릴 수 있는 코드 vs 새로 짜야 할 코드

### 4.1 그대로 사용 가능 (복사해서 바로 쓸 수 있는 것)

| 파일 | 이유 |
|------|------|
| `settings.gd` | 깔끔한 데이터 클래스. 그대로 복사해서 필요한 설정만 추가/제거하면 된다. |
| `stellar_body.gd` | 행성 데이터 클래스. 구조가 단순하고 명확하다. |
| `camera/camera.gd` | 3인칭 카메라 로직이 잘 작성되어 있다. 충돌 회피, 보간, 리지드바디 추적 모두 잘 동작한다. |
| `ship/ship.gd` | 우주선 물리가 잘 구현되어 있다. 6DOF 이동, 중력, 감속, 슈퍼스피드 모두 동작한다. `_integrate_forces()`의 구현이 견고하다. |
| `ship/ship_controller.gd` | 입력 처리가 깔끔하다. 키보드+마우스 통합, 캐릭터 탈출 로직이 잘 되어 있다. |
| `addons/zylann.3d_basics/character/character.gd` | 캐릭터 물리 (구면 중력, 점프, 슬로프 처리)가 잘 구현되어 있다. Godot의 `is_on_floor()` 문제를 잘 우회했다. |
| `main.gd` | 단순하고 깔끔한 게임 진입점. |

### 4.2 리팩토링 후 사용 (로직은 맞지만 구조 정리 필요)

| 파일/기능 | 필요한 작업 |
|-----------|-------------|
| `solar_system.gd`의 궤도 시뮬레이션 로직 | `_compute_absolute_body_transform()`, 레퍼런스 바디 전환, 그림자 거리 조절을 별도 클래스로 분리 |
| `solar_system.gd`의 스폰 로직 | 프레임 기반 지연을 VoxelLodTerrain 시그널 기반으로 변경. 스폰 매니저로 분리 |
| `solar_system_setup.gd`의 인스턴싱 설정 | `_configure_instancing_for_planet()`은 로직이 올바르다. 별도 클래스로 분리하면 재사용 가능 |
| `solar_system_setup.gd`의 대기 설정 | `update_atmosphere_settings()`는 로직이 맞다. 별도 클래스로 분리 |
| `character_controller.gd`의 이동/상호작용 | dig/build 기능, 상호작용 시스템을 별도 컴포넌트로 분리. 하이트맵 관련 코드 전부 제거 |
| `planet_ground.gdshader`의 텍스처링 | triplanar 텍스처링, far 텍스처링 로직은 올바르다. 바이옴/크레이터 관련 코드를 정리하고 실제 바이옴 분기를 구현해야 한다 |
| `voxel_graph_planet_v4.tres`의 지형 노이즈 | 셀룰러 노이즈 + 협곡 + 동굴 시스템의 로직은 올바르다. 크레이터/하이트맵 관련 노드(70-86)를 제거하고 정리하면 쓸 수 있다 |

### 4.3 새로 작성 (근본적으로 잘못된 접근)

| 파일/기능 | 왜 새로 짜야 하는가 |
|-----------|---------------------|
| `crater_generator.gd` | 2D 거리 기반 접근이 구면에서 작동 불가. 노드 동적 생성 방식은 스케일링 불가. 완전히 다른 접근법 필요 |
| `heightmap_item.gd` | SDF 수정 방식이 근본적으로 잘못됨. 성능 문제 해결 불가. 하이트맵 스탬프 자체를 VoxelTool API 위에 올바르게 재구현해야 함 |
| `runtime_crater_placer.gd` | 런타임 그래프 수정 접근이 비실용적. VoxelTool.do_sphere() 기반으로 재구현 |
| `test_crater_system.gd` | 테스트 대상(CraterGenerator)이 폐기되므로 같이 폐기 |
| `voxel_graph_planet_v5.tres` | 순수 구체만 있는 그래프는 사용 불가. v4 기반으로 크레이터 없는 깨끗한 지형 그래프를 새로 만들어야 한다 |
| `solar_system_setup.gd`의 크레이터 관련 코드 | `_setup_rocky_planet()`의 크레이터 생성 부분(275-357행), `_add_crater_dust_volumes()`를 새로운 크레이터 시스템으로 교체 |

---

## 5. 새 프로젝트 구성 제안

### 5.1 기존 코드에서 이식할 것

**즉시 복사:**
```
settings.gd                      -> 그대로 복사
stellar_body.gd                  -> 그대로 복사
camera/camera.gd + camera.tscn   -> 그대로 복사
ship/ship.gd + ship.tscn         -> 그대로 복사
ship/ship_controller.gd          -> 그대로 복사
ship/ship_audio.gd               -> 그대로 복사
ship/jet_vfx.gd                  -> 그대로 복사
main.gd                          -> 그대로 복사
character/ 폴더 (tscn, audio)    -> 그대로 복사
addons/ 폴더 전체                -> 그대로 복사
gui/ 폴더 전체                   -> 그대로 복사
props/ 폴더 전체                 -> 그대로 복사
sounds/ 폴더 전체                -> 그대로 복사
```

**정리 후 복사:**
```
solar_system_setup.gd  -> planet_factory.gd로 리네임, 크레이터 코드 제거
solar_system.gd        -> game_world.gd로 리네임, 책임 분리
character_controller.gd -> 하이트맵 코드 제거, dig/build 분리
planet_ground.gdshader -> 바이옴 로직 재작성
```

### 5.2 새로 작성할 것

#### (1) 지형 그래프: `voxel_graph_planet.tres` (신규)

v4의 좋은 부분(노이즈, 협곡, 동굴)을 유지하되, 크레이터/하이트맵 노드를 제거한 깨끗한 그래프를 만든다.

포함할 것:
- SdfSphere (기본 구체)
- FastNoise3D (셀룰러 노이즈, 표면 굴곡)
- Height multiplier (높이 변화량 조절)
- 선택적: 협곡 시스템 (ravine noise)
- 선택적: 동굴 시스템 (cave noise)

포함하지 않을 것:
- 수동 크레이터 노드
- Image2D 하이트맵 샘플링
- 바이옴 관련 노드 (바이옴은 셰이더에서 처리)

#### (2) 크레이터 시스템: `crater_system.gd` (신규)

**올바른 접근법 - 3가지 옵션:**

**옵션 A: VoxelTool 기반 (가장 실용적)**
```gdscript
# 행성 생성 후, VoxelTool로 크레이터를 "파낸다"
func carve_crater(volume: VoxelLodTerrain, center_3d: Vector3, radius: float, depth: float):
    var vt = volume.get_voxel_tool()
    vt.channel = VoxelBuffer.CHANNEL_SDF
    vt.mode = VoxelTool.MODE_REMOVE

    # 구면 좌표로 크레이터 위치 계산
    var surface_point = center_3d.normalized() * planet_radius

    # 여러 구체를 겹쳐서 자연스러운 크레이터 형태 생성
    # 중심에 큰 구, 가장자리로 갈수록 작은 구
    for ring in range(steps):
        var ring_radius = ...
        var ring_depth = ...
        vt.do_sphere(ring_center, ring_radius)

    # 림은 MODE_ADD로 추가
    vt.mode = VoxelTool.MODE_ADD
    # 가장자리를 따라 작은 구체들을 추가
```
- 장점: 기존 VoxelTool API만 사용, 3D 구면 좌표 자연스러움, SQLite 저장 자동 지원
- 단점: 세밀한 형태 제어 어려움, 런타임 수정은 저장 필요

**옵션 B: 그래프 내장 크레이터 (가장 깨끗함)**
```
# VoxelGraphFunction에 SdfSphere를 중첩하여 크레이터 표현
# InputX/Y/Z -> 3D 거리 계산 -> SdfSphere(crater) -> SdfSmoothSubtract
```
- 핵심: **3D 거리**를 사용해야 한다. XZ 2D 거리가 아니라 `sqrt(x^2 + y^2 + z^2)`
- 소수의 대형 크레이터(5-10개)에 적합
- 장점: 그래프 한 곳에서 관리, LOD 자동 지원
- 단점: 많은 수의 크레이터에 비실용적

**옵션 C: 노이즈 기반 크레이터 (가장 자연스러움)**
```
# Worley/Cellular 노이즈로 크레이터 분포를 자동 생성
# cellular_return_type = DISTANCE_TO_CLOSEST → 크레이터 형태 자연 발생
```
- 장점: 수백 개 크레이터 자동 생성, 자연스러운 분포, 성능 영향 최소
- 단점: 개별 크레이터 위치/크기 세밀 제어 어려움

**권장:** 옵션 A(주요 랜드마크 크레이터) + 옵션 C(소형 크레이터 분포) 혼합

#### (3) 바이옴 시스템: `biome_shader.gdshaderinc` (신규)

셰이더 include 파일로 바이옴 로직을 분리한다:

```glsl
// 구면 좌표 기반 바이옴 결정
vec3 get_biome_color(vec3 local_pos, float planet_radius) {
    // 3D 거리 기반 바이옴 감지 (2D XZ가 아님)
    float dist_to_landing = length(local_pos - u_landing_basin_center);
    float dist_to_fire_ice = length(local_pos - u_fire_ice_center);

    // 높이 기반 서브바이옴
    float height = length(local_pos) - planet_radius;

    // 우선순위 기반 바이옴 결정 + smoothstep 블렌딩
    vec3 biome_color = u_cryo_plains_color;

    if (dist_to_landing < u_landing_basin_radius) {
        float blend = smoothstep(u_landing_basin_radius - 200.0, u_landing_basin_radius, dist_to_landing);
        biome_color = mix(u_landing_basin_color, biome_color, blend);
    }
    // ... 나머지 바이옴

    return biome_color;
}
```

#### (4) 게임 월드 매니저: `game_world.gd` (신규, solar_system.gd 대체)

책임 분리:
```
game_world.gd          - 플레이어 스폰, 레퍼런스 전환, 메인 루프 조율
orbit_simulator.gd     - 궤도 시뮬레이션 (필요한 경우)
planet_factory.gd      - 행성 생성 (solar_system_setup.gd 정리)
spawn_manager.gd       - 지형 대기 + 안전 스폰
```

### 5.3 지형 생성의 올바른 접근법 (요약)

1. **기본 지형 그래프 (v4 기반 정리)**
   - SdfSphere + 셀룰러 노이즈(표면 굴곡) + 선택적 협곡/동굴
   - 이것만으로 흥미로운 자연 지형이 나온다

2. **대형 크레이터 (그래프 내장 또는 VoxelTool)**
   - 5-10개의 주요 랜드마크 크레이터
   - **반드시 3D 거리 사용** (XZ 2D가 아님)
   - 그래프에 내장하면 LOD가 자동이고, VoxelTool로 파면 저장이 자동

3. **소형 크레이터 (노이즈 기반)**
   - Worley 노이즈의 `cellular_return_type = DISTANCE`를 적절히 가공
   - 또는 별도의 노이즈 레이어로 표면에 작은 분화구 패턴 추가

4. **바이옴 (셰이더)**
   - 바이옴은 **색상/텍스처만** 담당
   - 지형 형상은 그래프에서 처리
   - 3D 거리 + 높이 기반 바이옴 결정

### 5.4 크레이터 구현의 올바른 접근법 (요약)

| 기존 접근 (실패) | 올바른 접근 |
|------------------|------------|
| 2D XZ 거리 계산 | 3D 구면 거리 (`length(pos - center)`) |
| 런타임 그래프 노드 동적 생성 | 미리 정의된 그래프 또는 VoxelTool |
| SDF에 단순 Add | `SdfSmoothSubtract` 또는 `do_sphere()` |
| 크레이터당 14개 노드 | Worley 노이즈 1개로 수백 개 |
| 하이트맵 스탬프로 SDF 직접 수정 | VoxelTool.do_sphere() 조합 |

---

## 부록: 우선순위별 액션 아이템

### P0 (즉시 해결해야 시작 가능)
1. v4 기반으로 크레이터/하이트맵 노드 없는 깨끗한 지형 그래프 생성
2. `solar_system_setup.gd`에서 CraterGenerator 관련 코드 제거
3. 셰이더에서 바이옴 감지 로직 실제 구현 (유니폼 값 사용)

### P1 (핵심 게임 경험)
4. VoxelTool 기반 크레이터 시스템 구현
5. game_world.gd 책임 분리
6. 스폰 매니저 구현 (프레임 기반 대기 -> 시그널 기반)

### P2 (품질 향상)
7. character_controller.gd에서 하이트맵/크레이터 코드 분리
8. 바이옴별 인스턴싱 (돌 종류 차별화)
9. 노멀맵 재활성화 및 아티팩트 해결

### P3 (장기)
10. Worley 노이즈 기반 소형 크레이터 분포
11. 바이옴별 환경 효과 (파티클, 사운드)
12. 문서 정리 (현재 5개 MD 파일이 서로 모순됨)

---

## 결론

이 프로젝트의 핵심 문제는 **지형 생성의 근본적 접근법 오류**다. v4의 복잡한 지형을 포기하고 v5의 빈 구체로 갈아탄 후, 그 위에 잘못된 크레이터 시스템(2D 거리, 동적 노드 생성)을 올려놓았다. 그 결과 "매끄러운 볼링공 + 이상한 크레이터"가 되었다.

**좋은 소식:** 우주선, 카메라, 캐릭터, 설정 시스템은 모두 잘 작동한다. 이식 가능한 코드가 전체의 약 60%다. 지형 생성 파이프라인만 올바르게 재구축하면 프로젝트를 살릴 수 있다.

**핵심 교훈:**
1. VoxelGeneratorGraph에서 3D 구면 거리를 사용해야 한다
2. 런타임 그래프 수정보다 VoxelTool API를 사용하라
3. v4의 노이즈 설정은 버리지 말고 정리해서 사용하라
4. 셰이더에 유니폼을 선언했으면 실제로 사용해야 한다
