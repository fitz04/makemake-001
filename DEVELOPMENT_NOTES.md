# Makemake Development Notes

## Project Overview
Godot 4.5 기반 Makemake 왜행성 탐사 게임. Voxel Terrain 플러그인을 사용한 절차적 지형 생성.

---

## Critical Issues & Discoveries

### 1. Terrain Size Synchronization Issue ⚠️

**Problem:** `graph.set_node_param()` doesn't work for setting terrain radius
- Location: [solar_system_setup.gd:252](solar_system/solar_system_setup.gd#L252)
- Impact: Terrain size must be manually synchronized between two files

**Files That Must Match:**
- `solar_system_setup.gd` line 73: `planet.radius = 8000.0`
- `voxel_graph_planet_v4.tres` line 205: `"radius": 8000.0`

**Symptoms if Mismatched:**
- Ship spawns at wrong height
- Player falls through terrain or spawns in space
- Collision detection fails

**Workaround:**
1. Change `planet.radius` in solar_system_setup.gd
2. Manually edit `voxel_graph_planet_v4.tres` line 205
3. Ensure both values are identical

**TODO:** Investigate why `graph.set_node_param()` is not applying the radius change

---

### 2. Spawn Height & Terrain Generation Timing

**Problem:** Ship falls through terrain before voxel mesh generates
- Location: [solar_system.gd:128](solar_system/solar_system.gd#L128)

**Root Cause:**
- VoxelLodTerrain generates meshes asynchronously
- Complex terrain (high octaves/gain) takes longer to generate
- Ship physics starts before collision mesh is ready

**Current Solution:**
```gdscript
var spawn_height := makemake.radius + 150.0  // 150m safety margin
for i in range(120):  // Frame-based delay
    await get_tree().process_frame
```

**Tested Values:**
- 5m: Too low - ship collision capsule is 16m tall
- 20m: Barely works - tail clips through terrain
- 50m: Works for simple terrain (octaves=5, gain=0.2)
- 100-150m: Required for complex terrain (octaves=7, gain=0.5)

**System Dependencies:**
- Frame count is NOT reliable across different hardware
- Slower systems may need higher spawn height or more frames
- `is_area_meshed()` hangs at 50% progress (chunk range issue)

**Better Solution Ideas:**
1. Wait for specific chunk area to finish meshing (currently broken)
2. Use signal-based approach when terrain ready
3. Implement graceful falling with re-spawn if below surface

---

### 3. Null Reference Errors During Initialization

**Error 1: camera.gd line 106**
```
Invalid access to property or key 'global_transform' on a base object of type 'Nil'
```

**Cause:** `_target` is null when `_physics_process` runs before ship assignment

**Fix:**
```gdscript
func _get_target_transform() -> Transform3D:
    if _target == null:
        return Transform3D()  // Guard clause
    return _target.global_transform
```

**Error 2: solar_system.gd line 377**
```
Invalid access to property or key 'global_transform' on a base object of type 'Nil'
```

**Cause:** `static_bodies` array contained null elements

**Fix:**
```gdscript
for sb in previous_body.static_bodies:
    if sb != null and sb.get_parent() != null:  // Null checks
        sb.get_parent().remove_child(sb)
```

---

## Terrain Configuration

### Current Settings (voxel_graph_planet_v4.tres)

**Planet Size:**
- Radius: 8000.0 (8km)
- Tested ranges: 2km (too small), 80km (too large, 3GB RAM)

**Terrain Complexity:**
- `fractal_octaves`: 7 (was 5)
- `fractal_gain`: 0.5 (was 0.2)
- `height_multiplier`: -80.0 (was -30.0)

**Effects:**
- Higher octaves = more detail, sharper features
- Higher gain = rougher terrain, more variation
- Higher height multiplier = taller mountains/deeper valleys

**Performance Impact:**
- octaves=7, gain=0.5: ~3GB RAM, longer generation time
- Complex terrain requires higher spawn height (150m vs 50m)

### Rock/Debris Density (solar_system_setup.gd)

**Reduced for cleaner surface:**
- Pebbles: 0.015 (was 0.15) - 90% reduction
- Rocks: 0.02 (was 0.08) - 75% reduction
- Big rocks: 0.01 (was 0.03) - 67% reduction
- Stalactites: 0.02 (was 0.06) - 67% reduction

---

## Appearance Settings

### Ice Dwarf Planet Look
```gdscript
// solar_system_setup.gd:245
mat.set_shader_parameter(&"u_top_modulate", Color(0.9, 0.95, 1.0))
```
- Light blue-gray tint for icy appearance
- Matches real Makemake observations (bright, grayish surface)

---

## Ship Configuration

### Collision Capsule
From [ship.tscn:21-23](ship/ship.tscn#L21-L23):
```tres
[sub_resource type="CapsuleShape3D" id="CapsuleShape3D_rrvor"]
radius = 3.03344
height = 16.0
```

**Implications:**
- Minimum safe spawn height: 11m (half height + radius)
- Actual spawn height: 150m (accounting for terrain generation delay)
- Collision capsule extends 8m above and below ship center

---

## Planned Features (BIOME_IMPLEMENTATION.md)

### 5 Biomes Designed:
1. **Landing Basin** - Main base, flat cleared area (500m radius)
2. **Cryo Plains** - Ice mining region, frozen surface
3. **Ore Highlands** - Metal mining, exposed bedrock (+50m elevation)
4. **Fire-Ice Basin** - Methane hydrate crater (800m radius, -150m depth)
5. **Living Lode Canyon** - Tungsten veins, alien life, deep ravines

### Implementation Phases:
- Phase 1: Visual biome colors (2-3 hours)
- Phase 2: Terrain shaping (4-6 hours)
- Phase 3: Resource distribution (3-4 hours)
- Phase 4: Gameplay integration (2-3 hours)
- Phase 5: Polish & effects (4-5 hours)

**Total Estimate:** 15-20 hours

---

## Development Workflow

### Version Control Setup
- Git initialized
- First commit: fc6f5f9
- 378 files, 58,570 lines committed
- `.gitignore` configured for Godot 4

### Key Files to Track
**Always commit together when changing planet size:**
- solar_system_setup.gd (line 73)
- voxel_graph_planet_v4.tres (line 205)

**Always test after modifying:**
- Terrain generation parameters → spawn height
- Spawn height → frame delay count
- Rock density → visual appearance

---

## Known Bugs

### Active Issues
1. ⚠️ **High Priority:** `graph.set_node_param()` not working for terrain radius
2. ⚠️ **Medium Priority:** Frame-based spawn delay unreliable on slow hardware
3. ⚠️ **Low Priority:** `is_area_meshed()` hangs at 50% progress

### Workarounds Applied
1. Manual .tres file editing
2. Conservative 150m spawn height + 120 frame delay
3. Avoided `is_area_meshed()` entirely

---

## Performance Notes

### Memory Usage
- 8km planet, octaves=7, gain=0.5: ~3GB RAM
- 80km planet: Exceeded 3GB, frame drops

### Terrain Generation Time
- Simple terrain (octaves=5, gain=0.2): ~1-2 seconds
- Complex terrain (octaves=7, gain=0.5): ~3-5 seconds
- System-dependent, may vary significantly

### Recommended Settings
- Planet radius: 5-10km (sweet spot for exploration)
- Octaves: 6-7 (good detail without excessive memory)
- Spawn height: 100-150m (safe for complex terrain)

---

## Debugging Tips

### Common Issues & Solutions

**Problem: Ship falls through terrain**
- Check: Spawn height in solar_system.gd:128
- Check: Frame delay count in solar_system.gd:117
- Check: Planet radius matches in both files
- Solution: Increase spawn height by 50m increments

**Problem: Terrain looks wrong size**
- Check: voxel_graph_planet_v4.tres line 205 radius
- Check: solar_system_setup.gd line 73 radius
- Solution: Ensure both match exactly

**Problem: Game crashes on startup**
- Check: Null reference errors in camera.gd:106
- Check: Null reference errors in solar_system.gd:377
- Solution: Add null checks before accessing properties

**Problem: Too much debris on surface**
- Check: Instance densities in solar_system_setup.gd:347-423
- Solution: Reduce density values (0.01-0.02 recommended)

### Debug Print Locations
```gdscript
// solar_system.gd:130 - Spawn position verification
print("Spawning ship at ", spawn_pos, spawn_height, " on Makemake surface")
```

---

## File Structure Reference

### Core Game Systems
- `solar_system/solar_system.gd` - Main game loop, spawn logic
- `solar_system/solar_system_setup.gd` - Planet generation, material setup
- `solar_system/stellar_body.gd` - Planet data structure
- `camera/camera.gd` - Camera controller
- `ship/ship.gd` - Ship physics

### Terrain Configuration
- `solar_system/voxel_graph_planet_v4.tres` - Voxel graph definition
- `solar_system/materials/planet_ground.gdshader` - Terrain shader
- `solar_system/materials/planet_material_rocky.tres` - Material instance

### Documentation
- `BIOME_IMPLEMENTATION.md` - Biome system design guide
- `DEVELOPMENT_NOTES.md` - This file
- `CHANGELOG.md` - Version history

---

## Next Steps

### Immediate Tasks
1. Begin Phase 1 of biome implementation (visual colors)
2. Test biome detection system
3. Verify shader parameter passing

### Future Improvements
1. Fix `graph.set_node_param()` API issue
2. Implement proper terrain ready detection
3. Add biome-specific props and resources
4. Create HUD biome indicator
5. Add environmental effects per biome

---

## Contact & Resources

### Godot Voxel Plugin
- Documentation: https://voxel-tools.readthedocs.io/
- Issues: https://github.com/Zylann/godot_voxel/issues

### Project-Specific Issues
- Create issues in project repository
- Tag with appropriate labels (bug, enhancement, terrain, biomes)

---

**Last Updated:** 2025-11-09
**Godot Version:** 4.5
**Voxel Plugin Version:** Latest (check project addons)
