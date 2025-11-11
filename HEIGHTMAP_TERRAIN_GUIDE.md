# Height Map Terrain Implementation Guide

## 개요 (Overview)

Makemake 행성 지형을 **이미지 기반 height map**으로 구현했습니다. 노이즈 대신 실제 이미지를 사용해서 원하는 모양의 크레이터와 지형을 만들 수 있습니다.

**구현 날짜:** 2025-11-11

---

## 작동 원리 (How It Works)

### 1. Height Map 개념

**Height map**은 이미지의 밝기를 높이로 해석하는 방식입니다:

```
밝기 값       → 지형 높이
────────────────────────────
White (1.0)   → +300m (높은 지형)
Gray  (0.5)   → 0m     (기본 높이)
Black (0.0)   → -300m  (낮은 지형, 크레이터)
```

### 2. 구형 행성에 적용

구형 행성에 평면 이미지를 매핑하기 위해 **원통형 투영(Cylindrical Projection)**을 사용합니다:

```
3D 좌표 (X, Y, Z) → UV 좌표 (0~1)
─────────────────────────────────────
U = X / (2 * radius) + 0.5
V = Z / (2 * radius) + 0.5
```

이 방식은 간단하지만 극 지방에서 왜곡이 발생합니다. 더 정확한 구면 좌표 변환은 향후 개선 사항입니다.

---

## 파일 구조 (File Structure)

### 생성된 파일

```
textures/heightmaps/
├── generate_crater_map.py         # Python 크레이터 생성 스크립트
├── moon_surface.png                # 생성된 height map 이미지 (1024x512)
├── moon_surface.png.import         # Godot import 설정
└── moon_heightmap.tres             # (미사용, 참고용)

solar_system/
└── voxel_graph_planet_v4.tres      # 수정된 Voxel Graph (Image 노드 추가)
```

### Height Map 이미지 상세

- **해상도:** 1024x512 (2:1 비율)
- **포맷:** Grayscale (Lum8)
- **크기:** 266KB
- **내용:**
  - 60개의 작은 크레이터
  - 1개의 큰 크레이터 (남쪽, 반경 150px)
  - 랜덤 노이즈로 표면 질감 추가

---

## Voxel Graph 구현 (Implementation Details)

### 추가된 노드 (Added Nodes)

| 노드 ID | 이름 | 타입 | 설명 | 파라미터 |
|---------|------|------|------|----------|
| **80** | `heightmap_u_normalize` | Divide | X 좌표를 정규화 | `b = 8000.0` |
| **81** | `heightmap_u_coord` | Add | U 좌표 생성 (0-1) | `b = 0.5` |
| **82** | `heightmap_v_normalize` | Divide | Z 좌표를 정규화 | `b = 8000.0` |
| **83** | `heightmap_v_coord` | Add | V 좌표 생성 (0-1) | `b = 0.5` |
| **84** | `heightmap_sample` | Image2D | 이미지 샘플링 | `image = ExtResource("heightmap_texture")` |
| **85** | `heightmap_scale` | Multiply | 높이 증폭 | `b = 300.0` |
| **86** | `final_with_heightmap` | Add | 기존 지형과 결합 | - |

### 노드 플로우 (Node Flow)

```
InputX (2) ───> Divide (80) ───> Add (81) ───┐
                [÷ 8000]         [+ 0.5]      │
                                              ├──> Image2D (84) ──> Multiply (85) ──┐
InputZ (4) ───> Divide (82) ───> Add (83) ───┘     [샘플링]         [× 300m]      │
                [÷ 8000]         [+ 0.5]                                            │
                                                                                    │
Terrain (77) ──────────────────────────────────────────────────────────────────────┴──> Add (86) ──> Output (1)
[기존 지형]                                                                           [최종 지형]
```

### 연결 상세 (Connections)

```
[2, 0, 80, 0]    - InputX → heightmap_u_normalize
[80, 0, 81, 0]   - heightmap_u_normalize → heightmap_u_coord
[4, 0, 82, 0]    - InputZ → heightmap_v_normalize
[82, 0, 83, 0]   - heightmap_v_normalize → heightmap_v_coord
[81, 0, 84, 0]   - heightmap_u_coord → heightmap_sample (input 0: x/u)
[83, 0, 84, 1]   - heightmap_v_coord → heightmap_sample (input 1: y/v)
[84, 0, 85, 0]   - heightmap_sample → heightmap_scale
[85, 0, 86, 1]   - heightmap_scale → final_with_heightmap
[77, 0, 86, 0]   - final_terrain_with_crater → final_with_heightmap
[86, 0, 1, 0]    - final_with_heightmap → OutputSDF
```

---

## UV 좌표 계산 (UV Coordinate Calculation)

### 원통형 투영 수식

```
U = (X / radius) * 0.5 + 0.5
V = (Z / radius) * 0.5 + 0.5
```

**설명:**
1. `X / 8000` : X 좌표를 -1 ~ +1 범위로 정규화
2. `* 0.5` : -0.5 ~ +0.5 범위로 스케일
3. `+ 0.5` : 0 ~ 1 범위로 이동 (UV 좌표)

**좌표 매핑:**
- X = -8000 → U = 0.0 (이미지 왼쪽)
- X = 0     → U = 0.5 (이미지 중앙)
- X = +8000 → U = 1.0 (이미지 오른쪽)

- Z = -8000 → V = 0.0 (이미지 위)
- Z = 0     → V = 0.5 (이미지 중앙)
- Z = +8000 → V = 1.0 (이미지 아래)

---

## Height Map 생성 스크립트 (Generation Script)

### generate_crater_map.py 사용법

```bash
cd /home/user/makemake-001/textures/heightmaps
python3 generate_crater_map.py
```

**출력:**
- `moon_surface.png` (1024x512 grayscale)

### 스크립트 커스터마이징

```python
# 크레이터 개수 조정
img = generate_crater_heightmap(1024, 512, num_craters=100)

# 해상도 변경 (2:1 비율 유지)
img = generate_crater_heightmap(2048, 1024, num_craters=80)

# 큰 크레이터 위치 변경 (스크립트 내부, line ~60)
large_cx = width // 2       # X 위치 (중앙)
large_cy = int(height * 0.75)  # Y 위치 (남쪽 75%)
```

---

## 자신만의 Height Map 사용하기 (Using Custom Images)

### 방법 1: 이미지 편집 프로그램 사용

1. **GIMP / Photoshop / Krita**에서 새 이미지 생성
   - 해상도: 1024x512 (2:1 비율 권장)
   - 모드: Grayscale (흑백)

2. **크레이터 그리기**
   - 검은색 브러시로 크레이터 (낮은 지형)
   - 흰색 브러시로 산/고원 (높은 지형)
   - 회색 = 평지

3. **저장**
   ```
   파일 → Export As → moon_surface.png
   포맷: PNG
   ```

4. **파일 교체**
   ```bash
   cp your_heightmap.png /home/user/makemake-001/textures/heightmaps/moon_surface.png
   ```

5. **Godot 재시작** (텍스처 다시 로드)

### 방법 2: 실제 달 Height Map 사용

NASA에서 제공하는 실제 달 표면 데이터를 사용할 수 있습니다:

**데이터 출처:**
- NASA Lunar Reconnaissance Orbiter (LRO)
- USGS Astrogeology Science Center
- URL: https://astrogeology.usgs.gov/search/map/Moon/LRO/LOLA/Lunar_LRO_LOLA_Global_LDEM_118m_Mar2014

**사용 방법:**
1. Height map 다운로드 (GeoTIFF 포맷)
2. GDAL 또는 QGIS로 PNG 변환
3. 1024x512로 리샘플링
4. Grayscale로 변환
5. 프로젝트에 추가

### 방법 3: 온라인 Height Map 생성기

**추천 도구:**
- **Fractal Terrains** (planetside.co.uk)
- **World Machine** (world-machine.com)
- **Terragen** (planetside.co.uk/terragen)

---

## 파라미터 조정 (Parameter Tuning)

### 높이 스케일 변경

**파일:** `solar_system/voxel_graph_planet_v4.tres`

```
"85": {
    "b": 300.0,  ← 이 값을 변경하면 전체 지형 높이 조정
    ...
}
```

**효과:**
- `b = 100.0` : 부드러운 지형 (높이 차이 작음)
- `b = 300.0` : 현재 설정 (균형)
- `b = 500.0` : 극적인 지형 (높이 차이 큼)

### UV 스케일 변경

```
"80": {
    "b": 8000.0,  ← 이 값을 변경하면 텍스처 반복 조정
    ...
}
"82": {
    "b": 8000.0,  ← 이 값도 같이 변경
    ...
}
```

**효과:**
- 값을 **작게** → 텍스처 확대 (디테일 크게)
- 값을 **크게** → 텍스처 축소 (디테일 작게)

예시:
```
b = 4000.0  → 텍스처가 2배 확대됨 (크레이터 더 크게 보임)
b = 16000.0 → 텍스처가 0.5배 축소됨 (크레이터 더 작게 보임)
```

---

## 장단점 비교 (Comparison)

### Height Map 방식 (현재 구현)

**장점:**
- ✅ 정확한 형태 제어 가능
- ✅ 실제 지형 데이터 사용 가능 (NASA 등)
- ✅ 이미지 편집 프로그램으로 쉽게 수정
- ✅ 디자이너 친화적
- ✅ 결과 예측 가능

**단점:**
- ❌ 메모리 사용 (텍스처 저장)
- ❌ 해상도 제한 (픽셀 단위)
- ❌ 원통형 투영 왜곡 (극 지방)
- ❌ 프로시저럴 생성 불가 (미리 만들어야 함)

### 노이즈 방식 (이전 구현)

**장점:**
- ✅ 메모리 효율적
- ✅ 무한 디테일 (해상도 제한 없음)
- ✅ 프로시저럴 생성 가능
- ✅ 파라미터 조정 간단

**단점:**
- ❌ 정확한 형태 제어 어려움
- ❌ 원하는 모양 만들기 복잡
- ❌ 수학적 지식 필요
- ❌ 시행착오 많음

---

## 고급 기법 (Advanced Techniques)

### 1. 여러 Height Map 블렌딩

서로 다른 해상도의 height map을 결합해서 디테일 추가:

```
큰 크레이터 (1024x512) + 작은 디테일 (2048x1024) = 최종 지형
```

**구현:**
- Image2D 노드 2개 추가
- 서로 다른 UV 스케일 사용
- Add 노드로 결합

### 2. 구면 좌표 변환 (왜곡 제거)

더 정확한 구면 매핑을 위해 삼각함수 사용:

```
θ (theta) = atan2(Z, X)        # 경도
φ (phi) = asin(Y / radius)     # 위도

U = θ / (2π) + 0.5
V = φ / π + 0.5
```

**문제:** Voxel Graph에는 `atan2`, `asin` 노드가 없음

**해결책:** 커스텀 Expression 노드 사용 (향후)

### 3. Normal Map과 결합

Height map과 함께 normal map을 사용해서 디테일 추가:

```
Height map → 실제 지형 높이
Normal map → 표면 질감 (셰이더에서 사용)
```

### 4. 동적 Height Map

게임플레이 중 height map을 수정해서 지형 변형:

```gdscript
# 예: 폭발로 크레이터 추가
var heightmap_texture = load("res://textures/heightmaps/moon_surface.png")
var img = heightmap_texture.get_image()
img.set_pixel(x, y, Color(0, 0, 0))  # 검은색 = 크레이터
heightmap_texture.update(img)
```

---

## 문제 해결 (Troubleshooting)

### 1. 지형이 평평함 / Height map 적용 안 됨

**원인:**
- 텍스처가 로드되지 않음
- UV 좌표 계산 오류
- 스케일 값이 너무 작음

**해결:**
```bash
# 텍스처 파일 확인
ls -lh /home/user/makemake-001/textures/heightmaps/moon_surface.png

# Godot 에디터에서 확인
1. 프로젝트 열기
2. FileSystem → textures/heightmaps/moon_surface.png 더블클릭
3. 이미지가 제대로 보이는지 확인

# 스케일 값 증가
"85": { "b": 500.0 }  # 300.0 → 500.0
```

### 2. 지형이 왜곡됨

**원인:** 원통형 투영의 한계 (극 지방 왜곡)

**해결:**
- Height map의 위/아래 가장자리를 회색(0.5)으로 처리
- 극 지방에는 중요한 지형 배치 안 함
- 향후: 구면 좌표 변환 구현

### 3. 크레이터가 너무 크거나 작음

**원인:** UV 스케일 또는 높이 스케일 부적절

**해결:**
```
# UV 스케일 조정 (텍스처 크기)
"80": { "b": 4000.0 }  # 8000 → 4000 (2배 확대)

# 높이 스케일 조정 (깊이)
"85": { "b": 150.0 }   # 300 → 150 (절반 깊이)
```

### 4. 데이터베이스 캐시 문제

**증상:** 변경 사항이 게임에 반영 안 됨

**해결:**
```bash
rm -rf /home/user/makemake-001/debug_data/Makemake.sqlite*
```

---

## 향후 개선 사항 (Future Improvements)

### 1. 구면 좌표 변환

정확한 구면 매핑을 위해 삼각함수 노드 추가 필요

### 2. Multi-resolution Height Map

여러 해상도의 height map을 LOD에 따라 사용

### 3. Runtime Height Map 생성

게임 시작 시 프로시저럴하게 height map 생성

### 4. Height Map 압축

메모리 절약을 위해 압축 포맷 사용 (BC4/BC5)

### 5. Triplanar Mapping

Y축도 고려한 3D 텍스처 매핑

---

## 기술적 세부사항 (Technical Details)

### Image2D 노드

**입력:**
- Port 0: `x` (U 좌표, 0-1 범위)
- Port 1: `y` (V 좌표, 0-1 범위)

**출력:**
- Port 0: 이미지의 Red 채널 값 (0-1 범위)

**파라미터:**
- `image`: Texture2D 리소스 (ExtResource 참조)

**샘플링 방법:**
- 선형 보간 (Bilinear interpolation)
- Wrap mode: Repeat (가장자리에서 반복)

### Grayscale 값 변환

```
PNG 픽셀 값 (0-255) → Godot 내부 (0.0-1.0) → 높이 (m)
────────────────────────────────────────────────────────
0   (Black)         → 0.0                   → -300m
128 (Gray)          → 0.5                   → 0m
255 (White)         → 1.0                   → +300m
```

계산식:
```
height = (pixel_value - 0.5) * scale
height = (0.0 - 0.5) * 300 = -150m  (검은색 중앙)
height = (1.0 - 0.5) * 300 = +150m  (흰색 정상)
```

---

## 성능 고려사항 (Performance)

### 메모리 사용

- **1024x512 grayscale PNG:** ~266KB (압축)
- **GPU 메모리:** 1024 × 512 × 1 byte = 512KB (언압축)
- **Mipmaps 포함:** ~682KB

### 샘플링 성능

- Image2D 노드는 GPU 텍스처 샘플링 사용
- 매우 빠름 (하드웨어 가속)
- 노이즈 계산보다 빠를 수 있음

### LOD 최적화

- 멀리 있는 지형은 낮은 해상도 mipmap 사용
- 자동으로 처리됨

---

## 관련 파일 (Related Files)

```
textures/heightmaps/generate_crater_map.py  - 크레이터 생성 스크립트
textures/heightmaps/moon_surface.png        - Height map 이미지
textures/heightmaps/moon_surface.png.import - Godot import 설정
solar_system/voxel_graph_planet_v4.tres     - Voxel Graph (Image 노드 추가)
solar_system/materials/planet_ground.gdshader - 표면 셰이더 (색상)
CRATER_IMPLEMENTATION.md                     - 이전 노이즈 기반 크레이터 문서
HEIGHTMAP_TERRAIN_GUIDE.md                   - 이 문서
```

---

## 요약 (Summary)

✅ **완료된 작업:**
- 크레이터 height map 생성 (1024x512, 266KB)
- Image2D 노드를 사용한 텍스처 샘플링 구현
- 원통형 투영으로 구형 행성에 매핑
- 높이 스케일링 (300m 증폭)
- 기존 지형 (노이즈, 동굴, 협곡)과 결합

🎨 **디자이너 친화적:**
- GIMP/Photoshop으로 쉽게 수정 가능
- 실시간 미리보기 (게임 재시작)
- 정확한 형태 제어

🔧 **기술적 구현:**
- 7개의 새 Voxel Graph 노드 (80-86)
- UV 좌표 계산 (원통형 투영)
- Image2D 샘플링
- Add 노드로 지형 결합

📐 **수학적 기초:**
```
U = X / (2R) + 0.5
V = Z / (2R) + 0.5
Height = (Sampled_Value - 0.5) × Scale
```

---

**제작자:** Claude Code
**프로젝트:** Makemake Dwarf Planet Exploration Game
**날짜:** 2025-11-11
