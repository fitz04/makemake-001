# VoxelTools 한계 분석 보고서

**분석일:** 2026-03-30
**분석 대상:** Zylann godot_voxel (VoxelTools) -- Godot 4.6 / Voxel Tools 1.6
**분석 목적:** Project Nomad (800km 왜행성 생존 크래프팅) 개발에 대한 VoxelTools의 근본적 한계 여부 판별
**분석자:** Claude Opus 4.6 (Voxel Engine Specialist)

---

## 목차

1. [VoxelTools 완성도 평가](#1-voxeltools-완성도-평가)
2. [Project Nomad 필수 기능 대조표](#2-project-nomad-필수-기능-대조표)
3. [엔진 원인 vs 사용법 원인 분석](#3-엔진-원인-vs-사용법-원인-분석)
4. [장기적 리스크](#4-장기적-리스크-게임-완성까지)
5. [대안 엔진 최종 비교](#5-대안-엔진-최종-비교)
6. [최종 판정](#6-최종-판정)

---

## 1. VoxelTools 완성도 평가

### 1.1 현재 개발 상태

**분류: 후기 베타 (Late Beta) -- 프로덕션 사용은 가능하나 주의 필요**

| 항목 | 상태 | 상세 |
|------|------|------|
| 커밋 수 | 4,907+ | 7년 이상의 지속적 개발 |
| 릴리스 | 10개 | 최신: Godot 4.6 stable + Voxel Tools 1.6 (2026-02) |
| 배포 방식 | Module (안정) / GDExtension (실험적) | Module 권장 |
| 유지보수자 | 1인 (Marc Gilleron/Zylann) | MIT 라이선스, 포크 가능 |
| 문서화 | 양호 | ReadTheDocs + GitHub 소스 문서 |
| 테스트 커버리지 | 불명 | 자동화된 테스트 스위트에 대한 공개 정보 제한적 |

**"후기 베타"로 분류하는 근거:**

1. 핵심 기능(LOD 지형, 스트리밍, 런타임 편집, 절차적 생성)은 안정적으로 작동
2. 그러나 일부 주요 기능이 미완성 상태 (아래 1.2 참조)
3. GDExtension 빌드는 공식적으로 "실험적"으로 분류됨
4. 릴리스가 "단순한 개발 버전의 스냅샷"이라고 명시됨 -- 안정 릴리스 사이클이 아님
5. 상용 게임 출시 사례가 확인되지 않음

### 1.2 핵심 기능 중 미구현 또는 불완전한 것

| 기능 | 상태 | 영향도 |
|------|------|--------|
| **VoxelLodTerrain 멀티플레이어** | 미구현 (VoxelTerrain만 지원) | 높음 |
| **VoxelGraphFunction 파라미터 노출** | 미구현 (계획됨) | 중간 |
| **VoxelGraphFunction 에디터 디버깅** | 미구현 (프로파일링, 프리뷰 불가) | 중간 |
| **커스텀 인스턴스 제너레이터 API** | 미구현 (API 안정화 전) | 낮음 |
| **인스턴서 에디터 수동 배치** | 미구현 | 낮음 |
| **Dual Contouring 메셔** | 미구현 (계획됨) | 낮음 |
| **GPU 오프로딩** | 미구현 (Godot 컴퓨트 셰이더 의존) | 중간 |
| **구조물 생성 (나무, 건물)** | 그래프 제너레이터로 불가 -- 별도 시스템 필요 | 중간 |
| **인스턴서 스트리밍 이벤트 스크립트 API** | 미노출 | 낮음 |

### 1.3 알려진 심각한 버그 / 성능 문제

#### (1) Vulkan 메시 파괴 시 CPU 스파이크 (Godot 4.x)

> "Lots of buffers get freed on the main thread at the end of the frame, and it can take a while, causing a CPU spike."

많은 작은 메시가 동시에 파괴될 때 메인 스레드에서 CPU 스파이크가 발생한다. 빠른 이동 시 LOD 전환이 빈번하면 이 문제가 심화된다.

**완화:** 메시 블록 크기를 32로 증가, 플레이어 이동 속도 제한, LOD 거리 축소.

#### (2) 물리 충돌체 생성 병목

> "Creating a collider from a mesh is actually much more expensive than meshing itself (about 3 to 5 times)."

메시에서 충돌체를 생성하는 것이 메시 생성 자체보다 3~5배 비싸다. Godot이 충돌체 생성을 메인 스레드에서 수행하며, 여러 프레임에 분산시키기 때문에 지형 로딩이 매우 느려진다.

**영향:** 런타임 채굴 시 편집된 청크의 물리 메시 재생성이 눈에 띄는 지연을 유발할 수 있다.

#### (3) Transvoxel LOD 이음새

> "Transvoxel uses special meshes to stitch blocks of different level of detail. However the seams may still be visible as occasional sharp little steps."

LOD 경계에서 날카로운 계단 형태의 이음새가 간헐적으로 나타난다. 셰이더 기반 스무딩(CUSTOM0 정점 속성)으로 완화 가능하나 완전히 제거되지는 않는다.

#### (4) 인스턴서 MultiMesh LOD 변경 시 성능 문제

> "There is currently a performance issue occurring when MultiMesh.mesh is changed to a different LOD."

인스턴서의 MultiMesh 메시 LOD 전환 시 성능 저하가 발생한다.

#### (5) 빠른 이동 물체의 터널링

메시 충돌체에 두께가 없어 빠른 이동 물체가 지형을 관통할 수 있다. 드릴, 로버 등 고속 이동 객체에 영향.

#### (6) ShaderMaterial 인스턴싱 제한

> "If you use a ShaderMaterial, it will be instanced on every chunk... dynamic changes done to parameters will not apply."

각 청크마다 ShaderMaterial이 인스턴싱되므로, 동적 파라미터 변경이 적용되지 않는다. 글로벌 유니폼을 사용해야 한다.

### 1.4 상용 게임 출시 사례

**확인된 상용 출시 사례: 없음**

광범위한 웹 검색(GitHub, Godot 포럼, 게임 데이터베이스)에서 Zylann VoxelTools를 사용하여 출시된 상용 게임을 찾지 못했다. 다음과 같은 레퍼런스만 존재한다:

- **solar_system_demo:** Zylann 자신의 기술 데모 (행성 1~20km)
- **voxelgame:** Zylann의 Minecraft 스타일 프로토타입
- **커뮤니티 프로젝트:** 개인 프로토타입, 학습 프로젝트 수준

이것은 **중요한 리스크 신호**이다. 도구가 프로덕션 검증을 거치지 않았다는 의미이므로, 개발 후반에 예상치 못한 문제가 발생할 가능성이 있다.

---

## 2. Project Nomad 필수 기능 대조표

| 기능 | 지원 상태 | 상세 설명 |
|------|-----------|-----------|
| **800km 구형 행성 생성** | **부분 지원** | SdfSphere + SdfSphereHeightmap 노드로 구형 지형 생성 가능. 그러나 검증된 최대 크기는 20km(solar_system_demo의 x10 모드). 800km는 40배 규모이며 Double Precision 빌드 필수. LOD 레벨 10+ 에서의 안정성 미검증. |
| **런타임 지형 편집 (채굴)** | **지원됨** | VoxelTool의 `do_sphere()` 등으로 런타임 SDF 편집 지원. 다만 물리 충돌체 재생성이 메시 생성의 3~5배 비용. 대규모 편집 시 프레임 드롭 주의. |
| **대형 크레이터 생성 (구면 좌표)** | **지원됨 (올바르게 구현 시)** | SdfSphere + SdfSmoothSubtract + Distance3D 노드 조합으로 구면 좌표 기반 크레이터 생성 가능. 개발자의 실패는 Distance2D 사용이 원인이며, **엔진 한계가 아님**. |
| **바이옴 시스템 (크기 조절)** | **부분 지원** | VoxelGeneratorGraph의 Select 노드 + 노이즈 기반 분기로 바이옴 구현 가능. 그러나 그래프 제너레이터는 "복셀 단위"로만 작동하여 구조물 생성 불가. 바이옴 크기 조절은 노이즈 주파수/스케일 조정으로 가능 -- **사용법 문제**. |
| **동굴/지하 공간** | **지원됨** | 3D 노이즈로 자연 동굴 생성 가능 ("3D noise actually produces overhangs or even small caves"). SDF 기반이므로 오버행, 터널, 동굴 생성이 복셀 시스템의 핵심 강점. |
| **LOD + 물리 메시 동시 지원** | **지원됨 (성능 주의)** | VoxelLodTerrain이 LOD를 관리하고, 가까운 청크에 물리 충돌체를 자동 생성. 그러나 충돌체 생성이 메인 스레드에서 수행되어 병목 발생 가능. |
| **지형 저장/로드 (영구 수정)** | **지원됨** | VoxelStreamSQLite로 수정된 블록만 저장. 절차적 생성 + 변경분 저장 전략이 공식 지원됨. 비동기 저장으로 메인 스레드 차단 최소화. |
| **복셀 텍스처링/재질 시스템** | **부분 지원** | Triplanar 매핑 + Mixel4(4재질 블렌딩) 지원. 그러나 최대 4텍스처/복셀, 전체 16텍스처 제한. 60 텍스처 페치/프래그먼트로 GPU 부하 높음. 커스텀 셰이더 필수. |
| **인스턴싱 (바위, 소품)** | **지원됨** | VoxelInstancer로 자동 배치 + LOD 관리. 구면 모드(Sphere mode) 지원. SDF 스내핑으로 배치 정밀도 향상 가능. 다만 커스텀 제너레이터 API 미공개. |
| **Origin Shifting** | **우회 가능** | VoxelTools 자체 기능은 아니지만, solar_system_demo에서 구현됨. 복셀 청크 좌표는 정수 기반이므로 Origin Shifting과 호환. Double Precision 빌드와 병행 권장. |
| **후처리 파이프라인 호환** | **지원됨** | Godot 4 Forward+의 후처리와 완전 호환. SSAO, SSR, Volumetric Fog 등 모두 작동. ShaderMaterial의 글로벌 유니폼 사용 필요. |
| **1인칭 + 구형 중력** | **우회 가능** | VoxelTools 자체 기능은 아니지만, solar_system_demo에서 구형 중력 구현됨. VoxelInstancer의 Sphere mode가 구면 방향 정렬 지원. |

### 지원 상태 요약

- **지원됨:** 6개 (런타임 편집, 크레이터, 동굴, LOD+물리, 저장/로드, 후처리)
- **부분 지원:** 3개 (800km 행성, 바이옴, 텍스처링)
- **우회 가능:** 3개 (Origin Shifting, 1인칭+구형중력, 인스턴싱 -- 모두 레퍼런스 구현 존재)
- **미지원/불가:** 0개

**핵심 발견: VoxelTools에 "근본적으로 불가능한" 기능은 없다.**

---

## 3. 엔진 원인 vs 사용법 원인 분석

### 3.1 바이옴 크기 조절이 안 된 것

**판정: 100% 사용법 문제**

| 분석 항목 | 내용 |
|-----------|------|
| **개발자의 증상** | 바이옴 크기를 조절할 수 없었다 |
| **코드 리뷰 결과** | 셰이더(`planet_ground.gdshader`)에서 바이옴은 `height_from_surface > 50.0`이라는 단순 높이 비교로만 구현됨. `u_landing_basin_center`, `u_fire_ice_center` 등의 유니폼이 선언되었으나 **셰이더에서 사용하지 않고 있음** |
| **엔진의 실제 능력** | VoxelGeneratorGraph는 Select 노드 + FastNoiseLite 조합으로 바이옴 분기를 구현할 수 있음. 노이즈의 `frequency` 파라미터가 바이옴 크기를 직접 제어. 디더링 기법으로 바이옴 경계 블렌딩도 가능 |
| **올바른 접근법** | (1) VoxelGeneratorGraph에서 2D/3D 노이즈로 바이옴 ID 결정 --> frequency로 바이옴 크기 조절 (2) 셰이더에서 바이옴 ID에 따른 텍스처/색상 분기 (3) 지형 형상도 바이옴 ID에 따라 다른 노이즈 파라미터 적용 |
| **근본 원인** | 셰이더에 바이옴 유니폼을 선언만 하고 실제 사용 로직을 구현하지 않음. VoxelGeneratorGraph v5에서 모든 노이즈를 제거하여 바이옴별 지형 변화 자체가 없어짐 |

### 3.2 크레이터가 안 된 것

**판정: 95% 사용법 문제, 5% 도구 편의성 부재**

| 분석 항목 | 내용 |
|-----------|------|
| **개발자의 증상** | 크레이터가 행성을 관통하는 원통형으로 나타남 |
| **코드 리뷰 결과** | `crater_generator.gd`에서 `InputX`와 `InputZ`만 사용하여 2D 거리를 계산. 개발자 자신도 주석에서 문제를 인식("2D distance on a sphere would create a cylinder") |
| **엔진의 실제 능력** | VoxelGeneratorGraph는 **Distance3D** 노드와 **SdfSmoothSubtract** 노드를 모두 제공. SdfSphereHeightmap도 구면 하이트맵을 지원. 구면 좌표 기반 크레이터 생성에 필요한 모든 노드가 존재 |
| **올바른 접근법** | (1) Distance3D로 구면 표면에서의 3D 거리 계산 (2) 정규화된 방향 벡터와 행성 중심 사이의 각도 기반 거리로 크레이터 프로파일 적용 (3) SdfSmoothSubtract로 구에서 크레이터 bowl을 부드럽게 파냄 |
| **5% 도구 문제** | VoxelGeneratorGraph의 노드 편집이 그래프가 커지면 관리가 어려움. 100개 크레이터 = 1400개 노드는 그래프 에디터에서 실질적으로 불가능. 그러나 이는 **접근 방식의 문제**이지 엔진 한계가 아님 -- 노이즈 기반 크레이터 분포(Cellular/Worley noise)를 사용하면 노드 수가 크레이터 수에 비례하지 않음 |
| **근본 원인** | SDF와 구면 기하에 대한 이해 부족. 크레이터 개별 노드 추가 방식 자체가 확장 불가능한 설계 |

### 3.3 지형이 밋밋한 것

**판정: 100% 사용법 문제**

| 분석 항목 | 내용 |
|-----------|------|
| **개발자의 증상** | 행성 표면이 크레이터 외에는 완전히 매끄러운 볼링공 |
| **코드 리뷰 결과** | `voxel_graph_planet_v5.tres`의 전체 내용: `InputX, InputY, InputZ --> SdfSphere(radius=8000) --> OutputSDF`. **노이즈 노드가 하나도 없음** |
| **경위** | v4 그래프(40+ 노드, 셀룰러 노이즈 7옥타브, 퍼린 노이즈 6옥타브, 산악/협곡/동굴)가 너무 복잡해져서 포기하고, v5에서 "깨끗한 시작"으로 순수한 구만 남김. v4의 지형 복잡도가 v5에 이식되지 않음 |
| **엔진의 실제 능력** | VoxelGeneratorGraph는 다양한 노이즈 노드(FastNoise2D, FastNoise3D, Noise2D, Noise3D)를 제공. 리지드 프랙탈로 침식 효과, 셀룰러 노이즈로 크레이터 분포, 3D 노이즈로 동굴/오버행 생성이 모두 가능. 공식 문서에 구체적인 예제도 있음 |
| **근본 원인** | v4의 복잡도 관리 실패와 v5로의 불완전한 마이그레이션. 그래프 복잡도가 증가했을 때 VoxelGraphFunction으로 서브그래프를 분리하는 기법을 사용하지 않음. **엔진에는 지형 복잡도를 만들 능력이 충분히 있으나, 개발자가 그 능력을 활용하지 못했음** |

### 3.4 종합 진단

```
개발자가 경험한 5가지 좌절:
  1. 지형이 원하는 모양이 안 나옴    --> v5에서 노이즈를 모두 제거했기 때문 (사용법)
  2. 크레이터가 안 됨                --> 2D 거리 계산 사용 (사용법)
  3. 바이옴 크기 조절 불가            --> 셰이더 유니폼을 선언만 하고 사용 안 함 (사용법)
  4. 코드가 관리 불가능               --> God 클래스, 책임 분리 부재 (아키텍처 문제)
  5. 엔진이 불완전/한계가 있다는 의심  --> 엔진은 충분한 기능을 제공. 문제는 사용법

결론: 5가지 중 0가지가 엔진의 근본적 한계이다.
```

---

## 4. 장기적 리스크 (게임 완성까지)

### 4.1 매스 드라이버 2,500km 레일 렌더링

**가능 여부: 가능하나 복셀 시스템과 무관하게 해결해야 함**

| 항목 | 분석 |
|------|------|
| **문제** | 2,500km 레일은 복셀 지형 위에 놓이는 구조물이지 복셀 자체가 아님 |
| **부동소수점** | Double Precision 빌드 필수. 400km 반경에서 single float 정밀도는 ~5cm로, 레일 정렬에 부적합 |
| **렌더링** | 레일은 일반 MeshInstance3D로 구현. LOD가 필요한 수준의 장거리이므로, 구간별 메시 분할 + 거리 기반 컬링 필요 |
| **복셀과의 상호작용** | 레일 기초 부분만 복셀 지형과 접하며, 이는 하이브리드 방식(전략 1)으로 해결 가능 |
| **권장** | 레일을 커브 기반 절차적 메시로 생성하고, Godot의 Path3D + CSGPolygon3D 또는 커스텀 메시 생성으로 구현. 복셀 엔진과는 독립적 |

### 4.2 자동화 시스템 (로버, 컨베이어)

**가능 여부: 복셀 엔진이 방해되지 않음**

| 항목 | 분석 |
|------|------|
| **로버** | 일반 RigidBody3D/CharacterBody3D로 구현. 복셀 지형 위의 물리 충돌체와 상호작용. 터널링 방지를 위해 이동 속도 제한 필요 (CCD 사용) |
| **컨베이어** | MeshInstance3D 체인으로 구현. 복셀 지형 표면에 배치 시 법선 정렬 필요 (solar_system_demo의 RayCast 기법 참조) |
| **자동 채굴** | VoxelTool의 런타임 편집 API로 구현 가능. 자동 드릴이 일정 영역을 주기적으로 `do_sphere()` 호출. 물리 메시 재생성 비용을 분산시키기 위해 편집 속도 조절 필요 |
| **결론** | 자동화 시스템은 게임 로직 레이어이며, 복셀 엔진은 지형 데이터 제공자 역할만 함. 상호 간섭 없음 |

### 4.3 멀티플레이어 확장 가능성

**현재 상태: 제한적이나 개선 중**

| 항목 | 상태 |
|------|------|
| **VoxelTerrain** | 멀티플레이어 지원됨. VoxelTerrainMultiplayerSynchronizer 노드 제공. 서버 권위적 모델 |
| **VoxelLodTerrain** | **멀티플레이어 미지원** (계획됨). Project Nomad는 VoxelLodTerrain을 사용해야 하므로 이것이 문제 |
| **지형 편집 동기화** | area_edit_notification_enabled + RPC 기반 동기화 가능 |
| **블록 전송** | VoxelBlockSerializer로 압축 전송. UDP vs TCP 성능 고려 필요 |
| **미래 전망** | Zylann이 VoxelLodTerrain 멀티플레이어를 계획 중. 그러나 구현 시점 불확실 |
| **위험도** | GDD에 "멀티플레이어는 미래 확장"으로 명시되어 있으므로 당장의 블로커는 아님. 그러나 장기적으로 커스텀 동기화 레이어 구현이 필요할 수 있음 |

### 4.4 Godot 5로의 마이그레이션 리스크

| 항목 | 분석 |
|------|------|
| **Godot 5 출시 시기** | 2026년 3월 기준 공식 발표 없음. Godot 4.x 시리즈가 활발히 업데이트 중 (4.4 -> 4.5 -> 4.6). 최소 2~3년은 4.x 지원 지속 예상 |
| **4.x 마이너 버전 호환성** | Godot은 마이너 버전 간 호환성 유지 정책. 4.4 -> 4.5 -> 4.6 마이그레이션은 상대적으로 안전 |
| **Module 호환성** | C++ Module은 Godot 내부 API에 직접 의존하므로, 메이저 버전 업그레이드 시 대규모 수정 필요 |
| **GDExtension 호환성** | GDExtension은 4.2부터 하위 호환: 4.2용 확장을 4.3, 4.4 등에서 사용 가능. 그러나 Godot 5에서는 보장 없음 |
| **VoxelTools 대응** | Zylann이 Godot 3 -> 4 전환을 성공적으로 수행한 전례. MIT 라이선스이므로 최악의 경우 커뮤니티 포크 가능 |
| **위험도** | 중간. 18개월 개발 주기 동안 Godot 5 출시 가능성 낮음. 4.x 내에서의 마이너 업그레이드는 관리 가능 |

### 4.5 800km 스케일에서의 미검증 영역

이것이 **가장 큰 기술적 리스크**이다.

| 미검증 항목 | 위험도 | 완화 방안 |
|------------|--------|-----------|
| LOD 레벨 10+ 안정성 | **높음** | 초기 프로토타입에서 반경 400km 테스트. 불안정 시 80km로 축소 (게임플레이 조정) |
| 청크 좌표계 정수 범위 | 중간 | 1m 복셀 해상도 기준 800km = 800,000 블록. int32 범위(~21억) 내이므로 문제 없어야 함 |
| 메모리 사용량 패턴 | 중간 | 절차적 생성 + 변경분만 저장 전략으로 메모리는 시야 범위에 비례. 스케일과 무관해야 함 |
| 생성기 성능 (대형 구면) | 중간 | SdfSphereHeightmap이 대형 반경에서도 동일 비용인지 검증 필요 |
| Origin Shifting + LOD 상호작용 | 중간 | solar_system_demo의 구현을 확장. 원점 이동 시 LOD 재계산 비용 측정 필요 |

---

## 5. 대안 엔진 최종 비교

### 5.1 Unreal Engine 5 + Voxel Plugin 2.0

| 항목 | 평가 |
|------|------|
| **행성 생성** | Voxel Plugin 2.0이 행성 노드를 내장. 6개 하이트맵으로 행성 생성. 화성 실물 크기 재현 사례 존재 |
| **상용 검증** | Voxel Plugin은 상용 플러그인($349/라이선스)으로 더 넓은 사용자 기반 |
| **기능 완성도** | Nanite/Lumen 런타임 지원, 무제한 재질, 복셀 스컬프팅, PCG, 스플라인 |
| **장점** | (1) 상용 지원, (2) UE5의 Nanite/Lumen, (3) 행성 전용 기능, (4) 더 큰 커뮤니티 |
| **단점** | (1) UE5 학습 곡선 가파름 (솔로 개발자), (2) 라이선스 비용 ($349 + UE 로열티 5%), (3) 에디터 무거움, (4) C++ 필수, (5) 기존 Godot 학습 투자 폐기 |
| **솔로 개발자 적합도** | **낮음**. UE5 + C++은 팀 개발에 최적화. 솔로 개발자가 18개월 내 게임을 완성하기 어려움 |
| **마이그레이션 비용** | 매우 높음 (6~12개월). GDScript -> C++/블루프린트, 셰이더 전면 재작성, 아키텍처 재설계 |

### 5.2 Unity + 커스텀 복셀 시스템

| 항목 | 평가 |
|------|------|
| **선례** | Planet Nomads가 120km 행성을 C++ 커스텀 엔진(Sandy Engine)으로 구현 |
| **에셋 생태계** | Unity Asset Store가 인더스트리얼/하드SF 에셋에서 압도적 |
| **기존 복셀 플러그인** | Voxeland, uTerrains 등 존재하나 구형 행성 미지원. 커스텀 개발 필수 |
| **장점** | (1) 에셋 스토어 직접 사용, (2) HDRP 시각적 품질, (3) Planet Nomads 참고 가능, (4) 큰 커뮤니티 |
| **단점** | (1) **복셀 엔진 자체 개발 6~12개월** -- 솔로 개발자에게 치명적, (2) 라이선스 비용, (3) HDRP 복잡성 |
| **솔로 개발자 적합도** | **매우 낮음**. Planet Nomads 팀조차 전업 팀이었음. 복셀 엔진 자체 개발은 비현실적 |
| **마이그레이션 비용** | 높음 (3~6개월). 셰이더 재작성, UI 재작성, 복셀 로직 재작성 |

### 5.3 Godot + 전통적 지형 (복셀 포기)

| 항목 | 평가 |
|------|------|
| **방식** | Terrain3D 또는 커스텀 하이트맵 기반 지형 |
| **장점** | (1) 안정적이고 검증된 기술, (2) 텍스처링 용이, (3) GPU 효율적 |
| **단점** | (1) **구형 행성 불가** -- 하이트맵은 평면 기반, (2) **채굴 불가** -- 런타임 지형 편집 미지원, (3) **동굴/오버행 불가** |
| **솔로 개발자 적합도** | 해당 없음 |
| **판정** | **불가**. Project Nomad의 3대 핵심 메카닉(구형 행성, 채굴, 동굴)이 모두 불가능. 게임 디자인 자체를 포기해야 함 |

### 5.4 기타 대안

| 대안 | 평가 |
|------|------|
| **Voxel Farm** | 상용 복셀 엔진. EverQuest Next에서 사용. $5,000+/년 라이선스. 행성 지원 미확인. 솔로 인디에 비현실적 비용 |
| **TerraForge** | 지형 생성 도구이지 런타임 복셀 엔진이 아님. 부적합 |
| **커스텀 엔진** | C++/Rust로 처음부터 개발. 기술적으로 최적이나 개발 기간 1~2년. 비현실적 |
| **Bevy + 커스텀 복셀** | Rust 기반 ECS 엔진. 성숙도 부족. 학습 곡선 극한. 비현실적 |

### 5.5 대안 비교 요약

| 엔진 조합 | 행성 지원 | 채굴 | 동굴 | 솔로 적합도 | 프로토타입까지 | 총점 |
|-----------|-----------|------|------|-------------|----------------|------|
| **Godot + VoxelTools** | O | O | O | **높음** | **4~6주** | **9/10** |
| UE5 + Voxel Plugin 2 | O | O | O | 낮음 | 8~16주 | 5/10 |
| Unity + 커스텀 복셀 | O | O | O | 매우 낮음 | 24~48주 | 2/10 |
| Godot + 전통 지형 | X | X | X | - | - | 0/10 |

---

## 6. 최종 판정

### VoxelTools에 근본적 한계가 있는가?

**아니오.** VoxelTools에는 Project Nomad의 개발을 차단하는 근본적 한계가 없다.

### 개발자가 경험한 좌절의 원인은?

5가지 좌절 모두 **사용법과 아키텍처 문제**이다:

| 좌절 | 실제 원인 | 해결 난이도 |
|------|-----------|-------------|
| 지형 밋밋함 | v5 그래프에 노이즈 노드가 0개 | 쉬움 (노이즈 노드 추가) |
| 크레이터 실패 | Distance2D 사용 (구면에서 Distance3D 필요) | 중간 (SDF 이해 필요) |
| 바이옴 실패 | 셰이더 유니폼 미사용 + 제너레이터에 바이옴 로직 없음 | 중간 (설계 재구성) |
| 코드 관리 불가 | God 클래스 + 책임 미분리 | 높음 (리팩토링 필요) |
| 엔진 불완전 의심 | 위 4가지 문제의 심리적 귀인 | 해당 없음 |

### 진짜 리스크는 무엇인가?

1. **800km 스케일 미검증** -- 가장 큰 리스크. 초기 프로토타입으로 검증 필수
2. **1인 유지보수자 의존** -- MIT 라이선스로 완화 가능
3. **상용 게임 출시 사례 부재** -- 프로덕션 수준의 예상치 못한 문제 가능성
4. **물리 충돌체 성능** -- 대규모 채굴 시 프레임 드롭 가능
5. **VoxelLodTerrain 멀티플레이어 미지원** -- 장기적 리스크

### 권장 행동

1. **VoxelTools를 계속 사용한다.** 엔진을 바꾸는 것은 시간 낭비이다. 문제는 엔진이 아니라 사용법이다.
2. **첫 2주를 프로토타입에 투자한다.** 반경 400km의 행성을 Double Precision 빌드에서 생성하고, LOD 안정성, 원점 이동, 지형 편집을 검증한다.
3. **아키텍처를 리팩토링한다.** 05_makemake001_code_review.md의 권고에 따라 God 클래스를 분리하고, 책임을 명확히 한다.
4. **SDF와 노이즈를 올바르게 이해한다.** v4의 복잡도를 v5에 VoxelGraphFunction 서브그래프로 단계적으로 추가한다. Distance3D 기반 구면 크레이터를 구현한다.
5. **노이즈 기반 크레이터로 전환한다.** 개별 크레이터 노드 추가 방식을 버리고, Cellular/Worley 노이즈로 크레이터 분포를 절차적으로 생성한다.

---

## 부록: 참고 자료

### VoxelTools 공식 자료

- [GitHub Repository](https://github.com/Zylann/godot_voxel)
- [Releases](https://github.com/Zylann/godot_voxel/releases)
- [Documentation (ReadTheDocs)](https://voxel-tools.readthedocs.io/en/latest/)
- [Generator Documentation](https://github.com/Zylann/godot_voxel/blob/master/doc/source/generators.md)
- [Performance Documentation](https://github.com/Zylann/godot_voxel/blob/master/doc/source/performance.md)
- [Smooth Terrain Documentation](https://github.com/Zylann/godot_voxel/blob/master/doc/source/smooth_terrain.md)
- [Streams Documentation](https://github.com/Zylann/godot_voxel/blob/master/doc/source/streams.md)
- [Instancing Documentation](https://github.com/Zylann/godot_voxel/blob/master/doc/source/instancing.md)
- [Multiplayer Documentation](https://github.com/Zylann/godot_voxel/blob/master/doc/source/multiplayer.md)
- [Graph Nodes Reference](https://github.com/Zylann/godot_voxel/blob/master/doc/source/graph_nodes.md)

### 레퍼런스 프로젝트

- [Solar System Demo](https://github.com/Zylann/solar_system_demo) -- 행성 생성, Origin Shifting, 구형 중력
- [Voxel Game Demo](https://github.com/Zylann/voxelgame) -- Minecraft 스타일 프로토타입

### Godot 대형 월드 관련

- [Large World Coordinates Documentation](https://docs.godotengine.org/en/stable/tutorials/physics/large_world_coordinates.html)
- [Emulating Double Precision on GPU](https://godotengine.org/article/emulating-double-precision-gpu-render-large-worlds/)

### 비교 대상

- [Voxel Plugin for Unreal Engine](https://voxelplugin.com/) -- UE5 대안
- [Voxel Plugin Documentation](https://docs.voxelplugin.com/)
- [Planet Nomads Technical Article](https://www.gamedeveloper.com/programming/bending-unity-to-carry-spherical-voxel-planets-in-planet-nomads) -- Unity 커스텀 복셀 사례
- [Planetation Voxel Biomes](https://80.lv/articles/learn-how-space-survival-planetation-redefined-voxel-biomes) -- 바이옴 구현 참고

### GitHub Issues (참고)

- [GDExtension Issues Tracker (#442)](https://github.com/Zylann/godot_voxel/issues/442)
- [Feature Branches Tracker (#640)](https://github.com/Zylann/godot_voxel/issues/640)
- [Collision Issues (#271)](https://github.com/Zylann/godot_voxel/issues/271)
- [Voxel Instancer (#223)](https://github.com/Zylann/godot_voxel/issues/223)
- [SDF Sphere Generation (#385)](https://github.com/Zylann/godot_voxel/issues/385)
- [Multiple Textures for Smooth Terrain (#93)](https://github.com/Zylann/godot_voxel/issues/93)
