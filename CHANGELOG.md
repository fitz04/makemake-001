# Changelog

All notable changes to the Makemake project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Planned
- 5-biome system implementation (see BIOME_IMPLEMENTATION.md)
- Biome-specific resource distribution
- Environmental effects per biome
- HUD biome indicator
- Improved terrain generation timing

---

## [0.1.0] - 2025-11-09

### Added - Initial Release

#### Core Systems
- Godot 4.5 voxel terrain system integration
- Single planet (Makemake) focused gameplay
- Ship physics and controller
- Character controller (for on-foot exploration)
- Camera system with VoxelViewer
- Basic HUD and menu system
- Pause menu with settings
- Mouse capture system

#### Planet Configuration
- Makemake dwarf planet setup
  - 8km radius planet
  - Ice dwarf planet appearance (grayish-white: Color(0.9, 0.95, 1.0))
  - No atmosphere (disabled)
  - Far outer solar system orbit (120,000m from sun)

#### Terrain Generation
- Complex procedural terrain
  - Cellular noise (7 octaves, 0.5 gain)
  - Height multiplier: -80.0
  - Ravine system with blend noise
  - Cave system with height-based generation
- Terrain features:
  - Sharp mountain ranges
  - Deep crevasses and ravines
  - Underground cave networks
  - Varied elevation (±80m from base radius)

#### Props & Environment
- Reduced debris density for cleaner surface:
  - Pebbles: 0.015 density (90% reduction from original)
  - Rocks: 0.02 density (75% reduction)
  - Big rocks: 0.01 density (67% reduction)
  - Stalactites: 0.02 density (67% reduction)
- Multiple rock variants with random scaling and rotation
- Slope-based placement (0-40° for most props)

#### Spawn System
- Safe spawn mechanism:
  - 150m spawn height above surface
  - 120 frame delay for terrain generation
  - Automatic positioning on Makemake
  - Ship collision capsule: 16m height, 3m radius

#### Documentation
- BIOME_IMPLEMENTATION.md - Complete 5-biome system design guide
  - Landing Basin design
  - Cryo Plains design
  - Ore Highlands design
  - Fire-Ice Basin design
  - Living Lode Canyon design
  - Implementation phases and time estimates
  - Shader modification guides
  - Resource distribution strategies
- DEVELOPMENT_NOTES.md - Technical notes and debugging guide
- CHANGELOG.md - This file
- README.md - Project overview
- LICENSE.md - Project license

#### Version Control
- Git repository initialized
- .gitignore configured for Godot 4
  - .godot/ excluded
  - Debug data excluded
  - Build artifacts excluded
  - System files excluded

### Fixed

#### Null Reference Crashes
- **camera.gd:106** - Added null check for `_target` before accessing global_transform
  - Symptom: Crash during initialization when camera physics runs before ship assignment
  - Fix: Return default Transform3D() when target is null

- **solar_system.gd:377** - Added null checks in `set_reference_body()`
  - Symptom: Crash when removing static bodies with null parents
  - Fix: Check both `sb != null` and `sb.get_parent() != null` before removal

#### Spawn Issues
- **Ship falling through terrain** - Increased spawn height and frame delay
  - Initial: 5m height (too low for 16m ship)
  - Tested: 15m, 20m, 50m
  - Final: 150m height with 120 frame delay
  - Reason: Complex terrain (octaves=7, gain=0.5) requires more generation time

### Changed

#### Terrain Parameters
- **Increased terrain complexity:**
  - fractal_octaves: 5 → 7
  - fractal_gain: 0.2 → 0.5
  - height_multiplier: -30.0 → -80.0
  - Result: More interesting terrain with sharper features

- **Planet size adjustments:**
  - Initial: 2km radius (too small)
  - Tested: 80km radius (too large, 3GB RAM, performance issues)
  - Final: 8km radius (sweet spot for exploration)

#### Material Settings
- **Ice planet appearance:**
  - Added blue-white tint: Color(0.9, 0.95, 1.0)
  - Matches Makemake's observed icy surface
  - Applied via `u_top_modulate` shader parameter

#### Code Organization
- **Added critical warnings in solar_system_setup.gd:**
  ```gdscript
  # WARNING: This value determines SPAWN POSITION only!
  # Actual terrain size is set in voxel_graph_planet_v4.tres (line 205)
  # BOTH VALUES MUST MATCH or spawn will be in wrong location!
  # TODO: Fix graph.set_node_param() not working (line ~253)
  ```

### Known Issues

#### High Priority
- **graph.set_node_param() not working** (solar_system_setup.gd:252)
  - Terrain radius must be manually synchronized between:
    - solar_system_setup.gd line 73
    - voxel_graph_planet_v4.tres line 205
  - Workaround: Manual file editing required

#### Medium Priority
- **Frame-based spawn delay unreliable** (solar_system.gd:117)
  - 120 frame delay works on development system
  - May fail on slower hardware
  - Symptoms: Ship still falls through terrain occasionally
  - Workaround: Increase spawn height or frame count

#### Low Priority
- **is_area_meshed() hangs** (abandoned approach)
  - Hangs at 50% progress when checking large areas
  - Likely due to chunk range limitations
  - Workaround: Using frame-based delay instead

### Technical Details

#### Dependencies
- Godot Engine 4.5
- Voxel Tools plugin (zylann.voxel)
- Atmosphere plugin (zylann.atmosphere)
- Debug Draw plugin (zylann.debug_draw)
- Lens Flare plugin (SIsilicon.vfx.lens_flare)

#### Performance Metrics
- Memory usage: ~3GB RAM (8km planet, octaves=7)
- Terrain generation time: 3-5 seconds (system dependent)
- Tested on: [Add your system specs]

#### File Changes
- Modified: solar_system_setup.gd
- Modified: voxel_graph_planet_v4.tres
- Modified: solar_system.gd
- Modified: camera.gd
- Added: .gitignore
- Added: BIOME_IMPLEMENTATION.md
- Added: DEVELOPMENT_NOTES.md
- Added: CHANGELOG.md

---

## Version History Notes

### Version Numbering
- Format: MAJOR.MINOR.PATCH
- MAJOR: Breaking changes or major feature additions
- MINOR: New features, non-breaking changes
- PATCH: Bug fixes, small tweaks

### Git Commit References
- [0.1.0]: Initial commit fc6f5f9

---

## How to Use This Changelog

### For Developers
- Read "Known Issues" before starting work
- Check "Unreleased" for planned features
- Update this file when making significant changes
- Reference DEVELOPMENT_NOTES.md for technical details

### For Users/Testers
- Check "Fixed" section for resolved bugs
- Review "Known Issues" for current limitations
- See "Added" for new features in each version

### Changelog Update Process
1. Make changes to code
2. Test thoroughly
3. Update CHANGELOG.md under [Unreleased]
4. When releasing, move [Unreleased] items to new version section
5. Commit with descriptive message referencing changelog

---

**Changelog Maintained By:** Development Team
**Last Updated:** 2025-11-09
