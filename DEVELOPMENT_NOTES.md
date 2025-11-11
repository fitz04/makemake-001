# Makemake 개발 노트

## 프로젝트 개요
Godot 4.5 기반 Makemake 왜행성 탐사 게임. Voxel Terrain 플러그인을 사용한 절차적 지형 생성.

**📚 관련 문서:**
- [BIOME_IMPLEMENTATION.md](BIOME_IMPLEMENTATION.md) - 바이옴 시스템 상세 설계 및 구현 계획
- [CHANGELOG.md](CHANGELOG.md) - 버전별 변경 이력
- 이 문서 (DEVELOPMENT_NOTES.md) - 기술적 이슈, 설정, 디버깅 가이드

> **💡 세션 연속성:** 새로운 작업 세션을 시작할 때는 위 세 문서를 모두 검토하여 프로젝트의 현재 상태, 계획된 기능, 알려진 이슈를 파악하세요.

---

## 주요 이슈 및 발견사항

### 1. 지형 크기 동기화 이슈 ⚠️

**문제:** `graph.set_node_param()`이 지형 반지름 설정에 작동하지 않음
- 위치: [solar_system_setup.gd:252](solar_system/solar_system_setup.gd#L252)
- 영향: 두 파일 간 지형 크기를 수동으로 동기화해야 함

**일치해야 하는 파일들:**
- `solar_system_setup.gd` 73번째 줄: `planet.radius = 8000.0`
- `voxel_graph_planet_v4.tres` 205번째 줄: `"radius": 8000.0`

**불일치 시 증상:**
- 우주선이 잘못된 높이에 스폰됨
- 플레이어가 지형을 뚫고 떨어지거나 우주에 스폰됨
- 충돌 감지 실패

**임시 해결책:**
1. solar_system_setup.gd에서 `planet.radius` 변경
2. voxel_graph_planet_v4.tres 205번째 줄 수동 편집
3. 두 값이 정확히 일치하는지 확인

**TODO:** `graph.set_node_param()`이 반지름 변경을 적용하지 못하는 이유 조사

---

### 2. 스폰 높이 및 지형 생성 타이밍

**문제:** 복셀 메시 생성 전에 우주선이 지형을 뚫고 떨어짐
- 위치: [solar_system.gd:128](solar_system/solar_system.gd#L128)

**근본 원인:**
- VoxelLodTerrain은 메시를 비동기적으로 생성함
- 복잡한 지형(높은 octaves/gain)은 생성 시간이 더 오래 걸림
- 충돌 메시가 준비되기 전에 우주선 물리 연산이 시작됨

**현재 해결책:**
```gdscript
var spawn_height := makemake.radius + 150.0  // 150m 안전 여유
for i in range(120):  // 프레임 기반 지연
    await get_tree().process_frame
```

**테스트된 값들:**
- 5m: 너무 낮음 - 우주선 충돌 캡슐이 16m 높이
- 20m: 간신히 작동 - 꼬리가 지형을 뚫음
- 50m: 단순 지형에서 작동 (octaves=5, gain=0.2)
- 100-150m: 복잡한 지형에 필요 (octaves=7, gain=0.5)

**시스템 의존성:**
- 프레임 카운트는 하드웨어마다 신뢰할 수 없음
- 느린 시스템은 더 높은 스폰 높이나 더 많은 프레임이 필요할 수 있음
- `is_area_meshed()`가 50% 진행에서 멈춤 (청크 범위 이슈)

**더 나은 해결책 아이디어:**
1. 특정 청크 영역의 메시 완료를 기다림 (현재 고장남)
2. 지형 준비 시 시그널 기반 접근 사용
3. 표면 아래로 떨어질 때 재스폰하는 부드러운 낙하 구현

---

### 3. 초기화 중 Null 참조 오류

**오류 1: camera.gd 106번째 줄**
```
Invalid access to property or key 'global_transform' on a base object of type 'Nil'
```

**원인:** 우주선 할당 전에 `_physics_process`가 실행될 때 `_target`이 null

**수정:**
```gdscript
func _get_target_transform() -> Transform3D:
    if _target == null:
        return Transform3D()  // 가드 절
    return _target.global_transform
```

**오류 2: solar_system.gd 377번째 줄**
```
Invalid access to property or key 'global_transform' on a base object of type 'Nil'
```

**원인:** `static_bodies` 배열에 null 요소가 포함됨

**수정:**
```gdscript
for sb in previous_body.static_bodies:
    if sb != null and sb.get_parent() != null:  // Null 체크
        sb.get_parent().remove_child(sb)
```

---

## 지형 설정

### 현재 설정 (voxel_graph_planet_v4.tres)

**행성 크기:**
- 반지름: 8000.0 (8km)
- 테스트된 범위: 2km (너무 작음), 80km (너무 큼, 3GB RAM)

**지형 복잡도:**
- `fractal_octaves`: 7 (이전 5)
- `fractal_gain`: 0.5 (이전 0.2)
- `height_multiplier`: -80.0 (이전 -30.0)

**효과:**
- 높은 octaves = 더 많은 디테일, 날카로운 특징
- 높은 gain = 거친 지형, 더 많은 변화
- 높은 height multiplier = 더 높은 산/더 깊은 계곡

**성능 영향:**
- octaves=7, gain=0.5: ~3GB RAM, 더 긴 생성 시간
- 복잡한 지형은 더 높은 스폰 높이 필요 (150m vs 50m)

### 암석/잔해 밀도 (solar_system_setup.gd)

**깔끔한 표면을 위해 감소:**
- 자갈: 0.015 (이전 0.15) - 90% 감소
- 바위: 0.02 (이전 0.08) - 75% 감소
- 큰 바위: 0.01 (이전 0.03) - 67% 감소
- 석순: 0.02 (이전 0.06) - 67% 감소

---

## 외형 설정

### 얼음 왜행성 모습
```gdscript
// solar_system_setup.gd:245
mat.set_shader_parameter(&"u_top_modulate", Color(0.9, 0.95, 1.0))
```
- 얼음 같은 외형을 위한 연한 청회색 색조
- 실제 Makemake 관측 결과와 일치 (밝고 회색빛 표면)

---

## 우주선 설정

### 충돌 캡슐
[ship.tscn:21-23](ship/ship.tscn#L21-L23)에서:
```tres
[sub_resource type="CapsuleShape3D" id="CapsuleShape3D_rrvor"]
radius = 3.03344
height = 16.0
```

**의미:**
- 최소 안전 스폰 높이: 11m (절반 높이 + 반지름)
- 실제 스폰 높이: 150m (지형 생성 지연 고려)
- 충돌 캡슐이 우주선 중심 위아래로 8m 확장

---

## 계획된 기능 (BIOME_IMPLEMENTATION.md)

### 설계된 5개 바이옴:
1. **착륙 분지 (Landing Basin)** - 메인 기지, 평탄화된 지역 (반지름 500m)
2. **극저온 평원 (Cryo Plains)** - 얼음 채굴 지역, 얼어붙은 표면
3. **광석 고지대 (Ore Highlands)** - 금속 채굴, 노출된 기반암 (+50m 고도)
4. **화염-얼음 분지 (Fire-Ice Basin)** - 메탄 하이드레이트 크레이터 (반지름 800m, 깊이 -150m)
5. **살아있는 광맥 협곡 (Living Lode Canyon)** - 텅스텐 광맥, 외계 생명체, 깊은 협곡

### 구현 단계:
- Phase 1: 바이옴 시각적 색상 (2-3시간)
- Phase 2: 지형 형성 (4-6시간)
- Phase 3: 자원 분포 (3-4시간)
- Phase 4: 게임플레이 통합 (2-3시간)
- Phase 5: 완성도 및 효과 (4-5시간)

**총 예상 시간:** 15-20시간

---

## 개발 워크플로우

### 버전 관리 설정
- Git 초기화됨
- 첫 커밋: fc6f5f9
- 378개 파일, 58,570줄 커밋됨
- Godot 4용 `.gitignore` 설정됨

### 추적해야 할 주요 파일
**행성 크기 변경 시 항상 함께 커밋:**
- solar_system_setup.gd (73번째 줄)
- voxel_graph_planet_v4.tres (205번째 줄)

**수정 후 항상 테스트:**
- 지형 생성 매개변수 → 스폰 높이
- 스폰 높이 → 프레임 지연 카운트
- 암석 밀도 → 시각적 외형

---

## 알려진 버그

### 활성 이슈
1. ⚠️ **높은 우선순위:** 지형 반지름에 대해 `graph.set_node_param()` 작동 안 함
2. ⚠️ **중간 우선순위:** 프레임 기반 스폰 지연이 느린 하드웨어에서 신뢰할 수 없음
3. ⚠️ **낮은 우선순위:** `is_area_meshed()`가 50% 진행에서 멈춤

### 적용된 임시 해결책
1. 수동 .tres 파일 편집
2. 보수적인 150m 스폰 높이 + 120 프레임 지연
3. `is_area_meshed()` 완전히 회피

---

## 성능 노트

### 메모리 사용량
- 8km 행성, octaves=7, gain=0.5: ~3GB RAM
- 80km 행성: 3GB 초과, 프레임 드랍

### 지형 생성 시간
- 단순 지형 (octaves=5, gain=0.2): ~1-2초
- 복잡한 지형 (octaves=7, gain=0.5): ~3-5초
- 시스템 의존적, 크게 다를 수 있음

### 권장 설정
- 행성 반지름: 5-10km (탐험에 최적)
- Octaves: 6-7 (과도한 메모리 없이 좋은 디테일)
- 스폰 높이: 100-150m (복잡한 지형에 안전)

---

## 디버깅 팁

### 일반적인 문제 및 해결책

**문제: 우주선이 지형을 뚫고 떨어짐**
- 확인: solar_system.gd:128의 스폰 높이
- 확인: solar_system.gd:117의 프레임 지연 카운트
- 확인: 두 파일에서 행성 반지름 일치
- 해결: 스폰 높이를 50m씩 증가

**문제: 지형 크기가 이상함**
- 확인: voxel_graph_planet_v4.tres 205번째 줄 반지름
- 확인: solar_system_setup.gd 73번째 줄 반지름
- 해결: 두 값이 정확히 일치하는지 확인

**문제: 게임이 시작 시 크래시**
- 확인: camera.gd:106의 Null 참조 오류
- 확인: solar_system.gd:377의 Null 참조 오류
- 해결: 속성 접근 전에 null 체크 추가

**문제: 표면에 잔해가 너무 많음**
- 확인: solar_system_setup.gd:347-423의 인스턴스 밀도
- 해결: 밀도 값 감소 (0.01-0.02 권장)

### 디버그 프린트 위치
```gdscript
// solar_system.gd:130 - 스폰 위치 확인
print("Spawning ship at ", spawn_pos, spawn_height, " on Makemake surface")
```

---

## 파일 구조 참조

### 핵심 게임 시스템
- `solar_system/solar_system.gd` - 메인 게임 루프, 스폰 로직
- `solar_system/solar_system_setup.gd` - 행성 생성, 머티리얼 설정
- `solar_system/stellar_body.gd` - 행성 데이터 구조
- `camera/camera.gd` - 카메라 컨트롤러
- `ship/ship.gd` - 우주선 물리

### 지형 설정
- `solar_system/voxel_graph_planet_v4.tres` - 복셀 그래프 정의
- `solar_system/materials/planet_ground.gdshader` - 지형 쉐이더
- `solar_system/materials/planet_material_rocky.tres` - 머티리얼 인스턴스

### 문서
- `BIOME_IMPLEMENTATION.md` - 바이옴 시스템 설계 가이드
- `DEVELOPMENT_NOTES.md` - 이 파일
- `CHANGELOG.md` - 버전 히스토리

---

## 구현 이력

### Phase 1: 바이옴 시각 시스템 (2025-11-09) ✓

**목표:** 5개 중 3개 바이옴에 대한 기본 색상 구분 구현

**변경 사항:**

1. **쉐이더 유니폼 추가** ([planet_ground.gdshader:15-23](solar_system/materials/planet_ground.gdshader#L15-L23))
   - 적절한 기본값으로 5개 바이옴 색상 유니폼 추가
   - 거리 계산을 위한 `u_planet_radius` 추가
   - `u_landing_basin_center` 및 `u_landing_basin_radius` 추가

2. **바이옴 감지 로직** ([planet_ground.gdshader:141-161](solar_system/materials/planet_ground.gdshader#L141-L161))
   ```gdscript
   // 착륙 분지: 스폰 지점(0,0,0)에서 반지름 500m
   // 광석 고지대: 고도 50m 이상
   // 극저온 평원: 기본 바이옴 (다른 모든 지역)
   ```
   - 거리 기반 및 고도 기반 감지 사용
   - 전환을 위한 `smoothstep()`으로 부드러운 블렌딩 구현

3. **매개변수 설정** ([solar_system_setup.gd:252-260](solar_system/solar_system_setup.gd#L252-L260))
   - 쉐이더에 전달된 모든 바이옴 색상:
     - 착륙 분지: `Color(0.85, 0.88, 0.92)` - 연한 회색
     - 극저온 평원: `Color(0.95, 0.97, 1.0)` - 밝은 흰색
     - 광석 고지대: `Color(0.7, 0.65, 0.6)` - 갈색-회색
   - 착륙 분지 중심: `Vector2(0, 0)` (스폰 지점)
   - 착륙 분지 반지름: `500.0`

**작동 방식:**
- 쉐이더가 착륙 분지 중심으로부터 각 프래그먼트의 거리를 계산
- 고도는 행성 표면 기준으로 측정됨
- 바이옴 색상이 기본 지형 텍스처와 곱해져 표면에 색조 부여

**시각적 결과:**
- 우주선이 연한 회색 착륙 분지 지역에 스폰됨 (반지름 500m)
- 500m 너머: 밝은 흰색 극저온 평원으로 전환
- 높은 고도 (>50m): 갈색-회색 광석 고지대 보임

**상태:** ✓ 완료 (2025-11-09)

---

### Phase 2A: 5개 바이옴 완성 및 재배치 (2025-11-09) ✓

**목표:** 모든 바이옴 시각화 및 균형잡힌 배치

**변경 사항:**

1. **5개 바이옴 모두 구현**
   - 화염-얼음 분지 추가 (남쪽 4,500m, 반지름 1,800m)
   - 살아있는 광맥 협곡 추가 (서쪽 -5500~-3000m)
   - 우선순위 기반 바이옴 감지 시스템

2. **바이옴 크기 확대 (2-3배)**
   - 착륙 분지: 500m → 1,200m
   - 화염-얼음: 800m → 1,800m
   - 협곡: 1,500m → 2,500m 폭

3. **바이옴 재배치 (충돌 방지)**
   - 화염-얼음: 3,000m → 4,500m 남쪽 (더 멀리)
   - 협곡: 서쪽으로 더 이동 (착륙 분지와 1,800m 간격)
   - 각 바이옴 사이 극저온 평원 완충 지대 확보

4. **테스트용 극단적 색상 적용**
   ```gdscript
   착륙 분지:    Color(1.2, 1.2, 1.2)     # 매우 밝은 흰색
   극저온 평원:  Color(1.5, 1.6, 1.8)     # 극도로 밝은 시안
   광석 고지대:  Color(1.0, 0.5, 0.3)     # 밝은 주황-갈색
   화염-얼음:    Color(0.5, 1.5, 2.0)     # 매우 밝은 청록색
   협곡:         Color(0.4, 0.3, 0.25)    # 매우 어두운 갈색
   ```
   - HDR 값 (>1.0) 사용으로 명확한 구분
   - 개발 중 바이옴 경계 명확히 확인 가능

**조명 설정:**
- Ambient Light Energy: 5.0 (원래 7.7에서 조정)
- Sky Contribution: 0.88 (우주 배경 밝기)
- 어두운 우주 환경에서도 바이옴 색상 명확히 보임

**상태:** ✓ 완료. 5개 바이옴 모두 명확히 구분됨.

**다음 단계:**
- Phase 2B: 지형 형성 (크레이터, 협곡, 평탄화)
- Phase 3: 현실적 색상으로 전환

---

### Phase 3 계획: 현실적 Makemake 색상 (미래)

**목표:** 실제 Makemake 관측 데이터 기반 색상으로 전환

**과학적 근거:**
- **붉은-갈색 톤**: 메탄 얼음이 우주 방사선에 노출되어 "톨린(tholin)" 형성
- **밝은 패치**: 순수한 메탄 얼음 (질소 얼음 가능)
- **어두운 부분**: 오래된 표면, 더 많은 톨린 축적
- **얼룩덜룩한 패턴**: 계절적 얼음 승화/응고

**제안 색상 (NASA/ESA 관측 기반):**

```gdscript
# 메인 표면: 붉은-갈색 톤 (메탄 + 톨린)
극저온 평원: Color(0.85, 0.75, 0.70)   # 연한 붉은-갈색

# 밝은 패치: 신선한 메탄 얼음
착륙 분지: Color(0.95, 0.90, 0.85)     # 밝은 크림색

# 크레이터/저지대: 더 어두운 톨린
화염-얼음: Color(0.65, 0.55, 0.50)     # 어두운 갈색

# 협곡: 노출된 오래된 표면
협곡: Color(0.50, 0.40, 0.35)          # 매우 어두운 갈색

# 고지대: 혼합 표면
광석 고지대: Color(0.75, 0.60, 0.50)   # 중간 갈색
```

**바이옴 구분 전략 (색상이 미묘할 때):**
1. **지형 차이**: 크레이터, 협곡, 평지
2. **소품 배치**: 얼음 결정, 암석 패턴
3. **시각 효과**: 미묘한 안개, 파티클
4. **조명**: 바이옴별 다른 ambient 색상

**적용 시기:**
- Phase 2B (지형 형성) 완료 후
- solar_system_setup.gd의 색상 값만 변경 (5분 작업)

**테스트 방법:**
1. 극단적 색상과 현실적 색상 비교
2. 바이옴 구분 가능 여부 확인
3. 필요시 색상 채도 조정

---

## 다음 단계

### 즉시 할 작업
1. ~~Phase 1 바이옴 구현 시작 (시각적 색상)~~ ✓ 완료
2. 게임 내 바이옴 시각적 전환 테스트
3. Phase 2 시작: 화염-얼음 분지 크레이터 구현 (깊이 -150m, 반지름 800m)
4. Phase 2 시작: 살아있는 광맥 협곡 협곡 시스템 구현

### 향후 개선사항
1. `graph.set_node_param()` API 이슈 수정
2. 적절한 지형 준비 감지 구현
3. Phase 3: 바이옴별 자원 분포 추가
4. Phase 4: HUD 바이옴 표시기 생성
5. Phase 5: 바이옴별 환경 효과 추가

---

## 연락처 및 리소스

### Godot Voxel 플러그인
- 문서: https://voxel-tools.readthedocs.io/
- 이슈: https://github.com/Zylann/godot_voxel/issues

### 프로젝트별 이슈
- 프로젝트 저장소에 이슈 생성
- 적절한 레이블로 태그 지정 (bug, enhancement, terrain, biomes)

---

**최종 업데이트:** 2025-11-09
**Godot 버전:** 4.5
**Voxel 플러그인 버전:** Latest (프로젝트 addons 확인)
