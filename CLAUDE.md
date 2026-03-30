# Project Nomad - Agent Context Document

## Project Overview

**Project Nomad** is a first-person hard-SF survival crafting simulation set on a Kuiper Belt dwarf planet (~800km diameter). The player crash-lands on an icy, airless world and must mine resources, smelt materials, craft equipment, and build infrastructure to eventually construct a mass driver for escape.

The game features an AI companion named "Kai" (케이) who provides guidance, emotional companionship, and narrative depth across 4 Acts spanning 15-20 hours of gameplay.

**Core Loop:** Resource Mining -> Smelting -> Crafting -> Power Expansion -> Automation -> Repeat

## Tech Stack

| Component | Choice | Notes |
|-----------|--------|-------|
| Engine | Godot 4.6 stable | Custom build required |
| Build Type | Double Precision (`precision=double`) | Required for 800km planet scale |
| Voxel System | Zylann VoxelTools 1.6 | Compiled as module (not GDExtension) |
| Language | GDScript | Primary scripting language |
| Shaders | Godot Shading Language (GDShader) | Post-processing pipeline |
| Platform | PC (Windows primary, Linux secondary) | |
| Dev Environment | WSL2 (Ubuntu on Windows) | |

### Why Double Precision?
At 400km from origin (planet surface), 32-bit floats have ~5cm precision gaps causing mesh jitter. Double precision eliminates this. Both Godot 4.6 and VoxelTools support `precision=double` builds.

### Why Module (not GDExtension)?
VoxelTools as a module is the recommended and well-tested approach. GDExtension support is experimental with known bugs.

## Directory Structure

```
/mnt/d/repo/mygame/
├── CLAUDE.md              # This file - agent context
├── .gitignore
├── project/               # Godot project root (open this in Godot editor)
│   ├── project.godot      # Project configuration
│   ├── scenes/            # .tscn scene files
│   ├── scripts/           # GDScript files
│   │   ├── autoloads/     # Singleton scripts (GameManager, etc.)
│   │   └── player/        # Player-related scripts
│   ├── resources/         # .tres resource files
│   ├── shaders/           # .gdshader files
│   ├── textures/          # Image assets
│   └── addons/            # Godot plugins (if any)
├── docs/                  # Original GDD documents (.docx)
├── docs_txt/              # Text versions of GDD (for agent analysis)
├── analysis/              # Agent analysis reports (.md)
└── tools/                 # Build scripts and utilities
    ├── build_double_precision.sh
    └── convert_docs.py
```

### Key Directories for Agents
- **Read `docs_txt/`** for game design information (Korean language)
- **Read `analysis/`** for technical analysis and cross-team synthesis
- **Edit files in `project/`** for actual game development
- **`analysis/00_cross_team_synthesis.md`** is the agreed technical direction -- read this first

## GDScript Coding Conventions

### Naming
- `snake_case` for variables, functions, signals, file names
- `PascalCase` for classes, node names, enum types
- `UPPER_SNAKE_CASE` for constants, enum values
- File names match the class: `player_controller.gd` for `class_name PlayerController`

### Type Hints
Always use explicit type hints:
```gdscript
var speed: float = 3.0
var items: Array[Item] = []
func calculate_damage(base: float, multiplier: float) -> float:
```

### Node References
```gdscript
@onready var camera: Camera3D = $Head/Camera3D
@export var move_speed: float = 3.0
```

### Signals
Use past tense names:
```gdscript
signal health_changed(new_value: float)
signal item_collected(item: Item)
signal state_changed(old_state: GameState, new_state: GameState)
```

### File Header
Every script should have a doc comment explaining its purpose:
```gdscript
## PlayerController - 1인칭 캐릭터 컨트롤러
##
## 구면 중력(spherical gravity)을 지원하는 FPS 컨트롤러.
class_name PlayerController
extends CharacterBody3D
```

### Section Order in Scripts
1. `class_name` and `extends`
2. Signals
3. Constants / Enums
4. `@export` variables
5. `@onready` node references
6. Public variables
7. Private variables (prefix `_`)
8. Lifecycle methods (`_ready`, `_process`, `_physics_process`)
9. Public methods
10. Private methods (prefix `_`)

### Comments
- Korean or English, but be consistent within a file
- Design documents and GDD references are in Korean

## Key Architectural Decisions

### 1. Spherical Gravity
The planet is a sphere. Gravity points toward planet center, not global DOWN. All physics, movement, and building systems must account for this. See `player_controller.gd` for the reference implementation.

### 2. Voxel Terrain (VoxelLodTerrain)
- Using `VoxelLodTerrain` for smooth LOD terrain (Transvoxel algorithm)
- Hybrid approach: buildings are regular 3D meshes, only terrain is voxel
- Mining uses `VoxelTool.do_sphere()` or `edit_box()` for voxel editing
- `VoxelGenerator` for procedural planet generation

### 3. Power Progression (4 Stages)
RTG (0.5kW) -> Methane Generator -> Dual Redundancy -> D-D Fusion

### 4. Printer Progression (3 Tiers)
Mk.0 (manual) -> Mk.1 (semi-auto) -> Mk.2 (full auto)

### 5. Post-Processing Pipeline
Act-based color palettes with morale-linked visual effects:
- Morale -> Saturation / Lens flare intensity
- Oxygen -> Vignette
- Living Lode proximity -> Chromatic aberration

### 6. GameManager Singleton
Global state accessible via `GameManager.*`. Manages game state, act progression, morale, and serialization for save/load.

## Design Documents Reference

### Core GDD (in `docs_txt/`)
| File | Content |
|------|---------|
| `GDD - 마스터 비전 (The Vision) - V10.txt` | High-level vision, core pillars, themes |
| `GDD - 백과사전 (The Encyclopedia) - V10.txt` | Encyclopedia of all game systems, items, resources |
| `GDD - 플레이어 진행 (The Journey) - V10.txt` | Player progression, quest flow, Act structure |
| `게임 엔딩 시나리오 - 최종 정리 V2.txt` | Ending scenarios and branching |
| `추가설정노트_20251228_로버_발전기_호흡.txt` | Supplementary: rover, generator, breathing systems |
| `추가설정노트_20251229_엑트1재설계.txt` | Supplementary: Act 1 redesign |
| `대규모 행성을 위한 오브젝트 및 지형 배치 전략.txt` | Technical: object/terrain placement on large planets |
| `에셋구매계획.txt` | Asset purchase plan |

### Analysis Reports (in `analysis/`)
| File | Content |
|------|---------|
| `00_cross_team_synthesis.md` | **Read first.** Agreed decisions from all agents |
| `01_game_design_analysis.md` | Game design deep analysis, 14 inconsistencies found |
| `02_tech_architecture_analysis.md` | Engine choice, VoxelTools analysis, rendering strategy |
| `03_narrative_design_analysis.md` | Narrative structure, Kai character, emotional beats |

### Known Document Issues
The GDD V10 and supplementary notes (20251228, 20251229) have 14 inconsistencies. A V11 unified GDD is needed before implementation. Critical conflicts:
- Generator design (3 competing versions)
- D-D fusion output (10GW vs 2.1GW)
- Laser mining power requirements

## Common Development Tasks

### Opening the Project in Godot
```bash
# Use the custom double-precision build:
/path/to/godot-double --path /mnt/d/repo/mygame/project/
```

### Building Godot (Double Precision + VoxelTools)
```bash
chmod +x tools/build_double_precision.sh
./tools/build_double_precision.sh
```

### Converting Design Docs
```bash
pip install python-docx
python3 tools/convert_docs.py
```

### Running the Game
```bash
/path/to/godot-double --path /mnt/d/repo/mygame/project/ --main-scene
```

## Development Phases (from Synthesis)

### Phase 1 (2 weeks): Terrain + Atmosphere Prototype
- Godot double precision build + VoxelTools setup
- Spherical planet generation + tholin textures
- Post-processing pipeline (vacuum shadows, color grading, bloom)
- Scale verification (400km radius test)

### Phase 2 (2 weeks): Core Loop Prototype
- First-person movement + low gravity physics
- Voxel mining (`edit_box`)
- Basic inventory + crafting
- RTG -> methane generator power transition

## Agent Guidelines

### Before Making Changes
1. Read `analysis/00_cross_team_synthesis.md` for agreed direction
2. Check relevant GDD files in `docs_txt/` for design requirements
3. Understand the spherical gravity model before touching physics/movement code
4. Remember: all documents are in Korean

### When Writing Code
- Follow the GDScript conventions above
- Add type hints to everything
- Use signals for decoupled communication
- Test with spherical gravity in mind (no hardcoded Vector3.DOWN for gravity)
- Consider double precision implications (avoid assumptions about float precision)

### Important Constraints
- This is a solo developer project -- keep architecture simple and maintainable
- MVP scope is Acts 1-4 with one ending (mass driver)
- Performance budget: target 60 FPS on mid-range hardware
- Planet scale (800km) is the biggest technical risk -- respect double precision requirements
- VoxelTools is a C++ module, not GDExtension -- changes require engine rebuild
