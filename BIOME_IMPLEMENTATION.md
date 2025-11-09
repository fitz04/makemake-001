# Makemake Biome Implementation Guide

This document explains how to implement the 5-biome system for the Makemake dwarf planet based on the Game Design Document.

## Overview

The implementation consists of three major components:

1. **Voxel Graph Modifications** - Creating distinct terrain features per biome
2. **Shader-based Biome Mapping** - Visual appearance based on position and height
3. **Resource Distribution** - Biome-specific prop placement (rocks, ice formations, etc.)

---

## Part 1: Biome Distribution System

### 1.1 Creating Biome Noise for Positional Mapping

We'll use noise-based functions to define biome regions. Add to `voxel_graph_planet_v4.tres`:

**Noise Resources Needed:**
```gdscript
# Biome selection noise - determines which biome based on position
[sub_resource type="ZN_FastNoiseLite" id="biome_selector"]
noise_type = 3  # Cellular
period = 4000.0  # Large cells for distinct regions
fractal_octaves = 1
cellular_distance_function = 0  # Euclidean
cellular_return_type = 1  # Distance2

# Secondary noise for biome boundaries
[sub_resource type="FastNoiseLite" id="biome_blend"]
frequency = 0.0005
fractal_octaves = 3
```

**Graph Nodes to Add:**

1. **Biome Selection Node** - Uses cellular noise to create 5 distinct regions
2. **Height-based Biome Modifier** - Modifies biome based on elevation
3. **Biome Output Node** - Outputs biome ID (0-4) for shader use

### 1.2 Manual Biome Positioning (Alternative Approach)

Instead of noise, we can manually position biomes using distance calculations:

**Landing Basin** (Biome 0):
- Position: Center of spawn (0, 0, 0)
- Radius: 500m from spawn point

**Cryo Plains** (Biome 1):
- Position: North of Landing Basin
- Area: Large flat region

**Ore Highlands** (Biome 2):
- Position: East/Southeast
- Elevation: Above 50m from base terrain

**Fire-Ice Basin** (Biome 3):
- Position: South crater at -1500m from Landing Basin
- Shape: Circular depression

**Living Lode Canyon** (Biome 4):
- Position: West canyon system
- Shape: Long narrow ravine

---

## Part 2: Terrain Shape Modifications

### 2.1 Voxel Graph Changes

Current graph structure:
- Node 9: SdfSphere (base planet shape, radius 8000)
- Node 11: Height multiplier (-80.0)
- Node 39: Main terrain noise (cellular, 7 octaves)

**Add Biome-Specific Terrain Nodes:**

```tres
# Landing Basin - Flatten the center
"70": {
    "type": "Distance",
    "gui_position": Vector2(400, 1200)
}
"71": {
    "type": "Smoothstep",
    "edge0": 0.0,
    "edge1": 500.0,  # 500m radius
    "gui_position": Vector2(540, 1200)
}
"72": {
    "type": "Multiply",
    "b": -20.0,  # Flatten by reducing height variation
    "gui_position": Vector2(680, 1200)
}

# Fire-Ice Basin - Create crater depression
"80": {
    "type": "Distance",
    "gui_position": Vector2(400, 1400)
}
"81": {
    "type": "Subtract",
    "b": Vector3(0, 0, -1500),  # Offset to south
    "gui_position": Vector2(260, 1400)
}
"82": {
    "type": "Smoothstep",
    "edge0": 0.0,
    "edge1": 800.0,  # Crater radius
    "gui_position": Vector2(540, 1400)
}
"83": {
    "type": "Multiply",
    "b": -150.0,  # Depression depth
    "gui_position": Vector2(680, 1400)
}

# Ore Highlands - Increase elevation
"90": {
    "type": "Clamp",
    "min": 0.0,
    "max": 1.0,
    "gui_position": Vector2(400, 1600)
}
"91": {
    "type": "Multiply",
    "b": 100.0,  # Height boost
    "gui_position": Vector2(540, 1600)
}

# Living Lode Canyon - Deep cuts
"100": {
    "type": "FastNoise3D",
    "noise": SubResource("canyon_noise"),
    "gui_position": Vector2(400, 1800)
}
"101": {
    "type": "Subtract",
    "b": 0.5,
    "gui_position": Vector2(540, 1800)
}
"102": {
    "type": "Multiply",
    "b": -200.0,  # Canyon depth
    "gui_position": Vector2(680, 1800)
}
```

**Required Noise Resources for Terrain:**

```tres
[sub_resource type="ZN_FastNoiseLite" id="canyon_noise"]
noise_type = 0  # Perlin
period = 50.0  # Tight noise for canyon walls
fractal_octaves = 4
fractal_lacunarity = 3.0  # Sharp features
```

### 2.2 Combining Biome Terrain Modifications

The final SDF should combine:
- Base sphere (node 9)
- Base terrain noise (current setup)
- Landing Basin flattening (node 72)
- Fire-Ice Basin depression (node 83)
- Ore Highlands elevation (node 91)
- Living Lode Canyon cuts (node 102)

Use `SdfSmoothUnion` and `SdfSmoothSubtract` nodes to blend these features.

---

## Part 3: Shader-Based Visual Biomes

### 3.1 Shader Parameter Additions

Add to `planet_ground.gdshader`:

```glsl
// Line 14 - Add after u_top_modulate
uniform sampler2D u_biome_map;  // Optional: baked biome map texture
uniform vec3 u_landing_basin_color : source_color = vec3(0.85, 0.88, 0.92);  // Light gray
uniform vec3 u_cryo_plains_color : source_color = vec3(0.95, 0.97, 1.0);     // Bright white
uniform vec3 u_ore_highlands_color : source_color = vec3(0.7, 0.65, 0.6);    // Brown-gray
uniform vec3 u_fire_ice_color : source_color = vec3(0.8, 0.9, 1.0);          // Blue-white
uniform vec3 u_canyon_color : source_color = vec3(0.75, 0.7, 0.65);          // Darker gray

// Biome center positions (in planet local space)
uniform vec3 u_landing_basin_center = vec3(0.0, 0.0, 0.0);
uniform vec3 u_fire_ice_center = vec3(0.0, 0.0, -1500.0);
uniform float u_planet_radius = 8000.0;
```

### 3.2 Biome Detection in Vertex Shader

Add to vertex shader (after line 67):

```glsl
varying float v_biome_id;
varying vec3 v_local_pos;

// In vertex() function:
vec3 local_pos = (planet_transform * vec4(VERTEX, 1.0)).xyz;
v_local_pos = local_pos;

// Calculate biome ID based on position
float dist_to_landing = length(local_pos - u_landing_basin_center);
float dist_to_fire_ice = length(local_pos - u_fire_ice_center);

// Simple biome selection (can be improved with noise)
if (dist_to_landing < 500.0) {
    v_biome_id = 0.0;  // Landing Basin
} else if (dist_to_fire_ice < 800.0) {
    v_biome_id = 3.0;  // Fire-Ice Basin
} else if (v_planet_height > 8050.0) {
    v_biome_id = 2.0;  // Ore Highlands (above 50m elevation)
} else if (local_pos.x < -500.0) {
    v_biome_id = 4.0;  // Living Lode Canyon (west side)
} else {
    v_biome_id = 1.0;  // Cryo Plains (default)
}
```

### 3.3 Biome Color Application in Fragment Shader

Replace the ALBEDO calculation (line 129) with:

```glsl
// Base color from textures
vec3 base_col = mix(side_col, top_col, topness);

// Biome color modulation
vec3 biome_color = u_cryo_plains_color;  // Default
if (v_biome_id < 0.5) {
    biome_color = u_landing_basin_color;
} else if (v_biome_id > 0.5 && v_biome_id < 1.5) {
    biome_color = u_cryo_plains_color;
} else if (v_biome_id > 1.5 && v_biome_id < 2.5) {
    biome_color = u_ore_highlands_color;
} else if (v_biome_id > 2.5 && v_biome_id < 3.5) {
    biome_color = u_fire_ice_color;
} else {
    biome_color = u_canyon_color;
}

// Blend biome color with texture
ALBEDO = base_col * biome_color;
```

### 3.4 Advanced: Noise-Based Biome Blending

For smoother biome transitions:

```glsl
// Add to fragment shader
float biome_blend_noise = triplanar_texture(
    u_top_normal_texture,  // Reuse noise from normal map
    triplanar_power_normal,
    v_triplanar_uv * 0.01
).r;

// Soften biome boundaries
float biome_boundary_width = 100.0;  // Meters
float boundary_factor = smoothstep(0.0, biome_boundary_width, dist_to_landing);
biome_color = mix(u_landing_basin_color, biome_color, boundary_factor);
```

---

## Part 4: Material Parameter Setup in Code

### 4.1 Setting Biome Colors in solar_system_setup.gd

Modify the Makemake material setup (around line 243):

```gdscript
elif body.name == "Makemake":
    # Ice dwarf planet - set biome colors
    mat.set_shader_parameter(&"u_top_modulate", Color(0.9, 0.95, 1.0))

    # Biome-specific colors
    mat.set_shader_parameter(&"u_landing_basin_color", Color(0.85, 0.88, 0.92))
    mat.set_shader_parameter(&"u_cryo_plains_color", Color(0.95, 0.97, 1.0))
    mat.set_shader_parameter(&"u_ore_highlands_color", Color(0.7, 0.65, 0.6))
    mat.set_shader_parameter(&"u_fire_ice_color", Color(0.8, 0.9, 1.0))
    mat.set_shader_parameter(&"u_canyon_color", Color(0.75, 0.7, 0.65))

    # Biome positions (in planet local space)
    mat.set_shader_parameter(&"u_landing_basin_center", Vector3(0, 0, 0))
    mat.set_shader_parameter(&"u_fire_ice_center", Vector3(0, 0, -1500))
    mat.set_shader_parameter(&"u_planet_radius", body.radius)
```

---

## Part 5: Resource Distribution Per Biome

### 5.1 VoxelInstancer Modifications

Currently, rocks are placed uniformly. We need to make density biome-dependent.

**Approach 1: Multiple Instancers Per Biome**

Create separate VoxelInstancer nodes for each biome:

```gdscript
# In solar_system_setup.gd, around line 340
# Current: Single instancer for all rocks
# New: Multiple instancers with different densities

func _setup_biome_props(body: StellarBody, volume: VoxelLodTerrain):
    # Landing Basin - minimal rocks, processed/cleared
    var landing_basin_instancer = _create_instancer(volume, "landing_basin_rocks")
    landing_basin_instancer.density = 0.005  # Very sparse
    _add_pebbles_to_instancer(landing_basin_instancer)

    # Cryo Plains - ice chunks and scattered rocks
    var cryo_instancer = _create_instancer(volume, "cryo_plains_ice")
    cryo_instancer.density = 0.03
    _add_ice_formations_to_instancer(cryo_instancer)

    # Ore Highlands - exposed bedrock, metal deposits
    var ore_instancer = _create_instancer(volume, "ore_highlands_metals")
    ore_instancer.density = 0.04
    _add_metal_deposits_to_instancer(ore_instancer)

    # Fire-Ice Basin - methane ice crystals
    var fire_ice_instancer = _create_instancer(volume, "fire_ice_crystals")
    fire_ice_instancer.density = 0.02
    _add_ice_crystals_to_instancer(fire_ice_instancer)

    # Living Lode Canyon - tungsten outcrops, alien life
    var canyon_instancer = _create_instancer(volume, "canyon_tungsten")
    canyon_instancer.density = 0.025
    _add_canyon_props_to_instancer(canyon_instancer)
```

**Approach 2: Single Instancer with Biome-Aware Density**

Modify the existing instancer noise to respect biome boundaries:

```gdscript
# In VoxelInstanceGenerator noise setup
# Add custom noise that outputs 0 in Landing Basin, 1 elsewhere
var biome_mask_noise = FastNoiseLite.new()
biome_mask_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
biome_mask_noise.frequency = 0.0002
# This noise is sampled by the instancer to determine placement
```

### 5.2 Biome-Specific Prop Models

Create or use different 3D models for each biome:

**Landing Basin:**
- Small pebbles only
- Occasional equipment/structures

**Cryo Plains:**
- Ice chunks (modify existing rock models with ice material)
- Frost formations
- Small craters

**Ore Highlands:**
- Rocky outcrops
- Metal-rich boulders (darker color)
- Exposed bedrock

**Fire-Ice Basin:**
- Methane ice crystals (tall, crystalline shapes)
- Sublimation vents (steam/gas particle emitters)
- Collapsed ice caves

**Living Lode Canyon:**
- Tungsten veins (glowing blue-gray material)
- Alien plant-like structures
- Bioluminescent rocks

### 5.3 Implementation in Code

```gdscript
# Add to solar_system_setup.gd after line 420

func _add_ice_formations_to_instancer(instance_generator: VoxelInstanceGenerator):
    var ice_scene = load("res://props/ice_chunk.tscn")  # Create this
    var item = VoxelInstanceLibraryMultiMeshItem.new()
    item.setup_from_template(ice_scene.instantiate())
    instance_generator.library.add_item(1, item)  # ID 1 for ice

func _add_metal_deposits_to_instancer(instance_generator: VoxelInstanceGenerator):
    var metal_scene = load("res://props/metal_deposit.tscn")  # Create this
    var item = VoxelInstanceLibraryMultiMeshItem.new()
    item.setup_from_template(metal_scene.instantiate())
    instance_generator.library.add_item(2, item)  # ID 2 for metal

func _add_ice_crystals_to_instancer(instance_generator: VoxelInstanceGenerator):
    var crystal_scene = load("res://props/methane_crystal.tscn")  # Create this
    var item = VoxelInstanceLibraryMultiMeshItem.new()
    item.setup_from_template(crystal_scene.instantiate())
    instance_generator.library.add_item(3, item)  # ID 3 for crystals

func _add_canyon_props_to_instancer(instance_generator: VoxelInstanceGenerator):
    var tungsten_scene = load("res://props/tungsten_vein.tscn")  # Create this
    var alien_scene = load("res://props/alien_structure.tscn")  # Create this

    var tungsten_item = VoxelInstanceLibraryMultiMeshItem.new()
    tungsten_item.setup_from_template(tungsten_scene.instantiate())
    instance_generator.library.add_item(4, tungsten_item)

    var alien_item = VoxelInstanceLibraryMultiMeshItem.new()
    alien_item.setup_from_template(alien_scene.instantiate())
    instance_generator.library.add_item(5, alien_item)
```

---

## Part 6: Gameplay Integration

### 6.1 Biome Detection System

Create a script to detect which biome the player is in:

```gdscript
# Create: res://solar_system/biome_detector.gd
extends Node
class_name BiomeDetector

enum Biome {
    LANDING_BASIN = 0,
    CRYO_PLAINS = 1,
    ORE_HIGHLANDS = 2,
    FIRE_ICE_BASIN = 3,
    LIVING_LODE_CANYON = 4
}

signal biome_changed(new_biome: Biome)

var current_biome: Biome = Biome.CRYO_PLAINS
var planet_radius: float = 8000.0
var landing_basin_center: Vector3 = Vector3.ZERO
var fire_ice_center: Vector3 = Vector3(0, 0, -1500)

func detect_biome(player_pos: Vector3) -> Biome:
    var local_pos = player_pos  # Assuming planet-local coordinates
    var height = local_pos.length()

    # Check Landing Basin
    var dist_to_landing = local_pos.distance_to(landing_basin_center)
    if dist_to_landing < 500.0:
        return Biome.LANDING_BASIN

    # Check Fire-Ice Basin
    var dist_to_fire_ice = local_pos.distance_to(fire_ice_center)
    if dist_to_fire_ice < 800.0:
        return Biome.FIRE_ICE_BASIN

    # Check Ore Highlands (elevation-based)
    if height > planet_radius + 50.0:
        return Biome.ORE_HIGHLANDS

    # Check Living Lode Canyon (west side, specific coordinates)
    if local_pos.x < -500.0 and abs(local_pos.z) < 1000.0:
        return Biome.LIVING_LODE_CANYON

    # Default: Cryo Plains
    return Biome.CRYO_PLAINS

func update(player_pos: Vector3):
    var new_biome = detect_biome(player_pos)
    if new_biome != current_biome:
        current_biome = new_biome
        biome_changed.emit(new_biome)
```

### 6.2 HUD Integration

Update HUD to show current biome:

```gdscript
# In res://gui/hud.gd
func _on_biome_changed(biome: BiomeDetector.Biome):
    var biome_names = [
        "Landing Basin",
        "Cryo Plains",
        "Ore Highlands",
        "Fire-Ice Basin",
        "Living Lode Canyon"
    ]
    $BiomeLabel.text = "Location: " + biome_names[biome]
```

### 6.3 Environmental Effects Per Biome

```gdscript
# Add to solar_system.gd or create biome_effects.gd

func _apply_biome_effects(biome: BiomeDetector.Biome):
    match biome:
        BiomeDetector.Biome.LANDING_BASIN:
            # Safe area, no hazards
            _set_ambient_temperature(250)  # Kelvin

        BiomeDetector.Biome.CRYO_PLAINS:
            # Extreme cold
            _set_ambient_temperature(30)
            # Add frost particles

        BiomeDetector.Biome.ORE_HIGHLANDS:
            # Rocky, uneven terrain
            # Reduce movement speed on steep slopes

        BiomeDetector.Biome.FIRE_ICE_BASIN:
            # Methane sublimation hazard
            _spawn_methane_vents()
            # Visual: hazy atmosphere effect

        BiomeDetector.Biome.LIVING_LODE_CANYON:
            # Tungsten radiation (harmless to player, but anomalous)
            # Alien structures emit light
            _add_bioluminescence()
```

---

## Part 7: Implementation Checklist

### Phase 1: Basic Biome Visualization (2-3 hours)
- [ ] Add biome color uniforms to `planet_ground.gdshader`
- [ ] Implement basic biome detection in vertex shader
- [ ] Set biome colors in `solar_system_setup.gd`
- [ ] Test: Should see colored regions on planet surface

### Phase 2: Terrain Shaping (4-6 hours)
- [ ] Add Landing Basin flattening nodes to `voxel_graph_planet_v4.tres`
- [ ] Add Fire-Ice Basin crater depression
- [ ] Add Ore Highlands elevation boost
- [ ] Add Living Lode Canyon cutting noise
- [ ] Combine all terrain modifications
- [ ] Test: Verify distinct terrain features

### Phase 3: Resource Distribution (3-4 hours)
- [ ] Create biome-specific prop 3D models (or reuse with material variants)
- [ ] Set up multiple VoxelInstancers per biome
- [ ] Adjust densities for each biome
- [ ] Test: Verify props appear in correct locations

### Phase 4: Gameplay Integration (2-3 hours)
- [ ] Create `BiomeDetector` class
- [ ] Add biome detection to player update loop
- [ ] Update HUD to display current biome
- [ ] Test: Verify biome changes are detected

### Phase 5: Polish & Effects (4-5 hours)
- [ ] Add biome transition blending in shader
- [ ] Implement environmental effects (particles, lighting)
- [ ] Add audio ambience per biome
- [ ] Create biome-specific weather/atmosphere effects
- [ ] Final testing and balancing

**Total Estimated Time: 15-20 hours**

---

## Part 8: Advanced Techniques

### 8.1 Procedural Biome Boundaries with Voronoi Cells

For more organic biome shapes:

```glsl
// In shader - use Voronoi/Worley noise for natural boundaries
vec3 voronoi_result = voronoi3d(v_local_pos * 0.0001);
float cell_id = floor(voronoi_result.y * 5.0);  // 5 biomes
v_biome_id = cell_id;
```

### 8.2 Height-Based Sub-Biomes

Within each biome, vary appearance by elevation:

```glsl
// Ice cap on high elevations
if (v_planet_height > u_planet_radius + 100.0) {
    biome_color = mix(biome_color, vec3(1.0), 0.5);  // Whiter at peaks
}

// Valley floors are darker
if (v_planet_height < u_planet_radius - 20.0) {
    biome_color = biome_color * 0.7;  // Darker in depressions
}
```

### 8.3 Seasonal/Dynamic Biomes

For future expansion:

```gdscript
# Time-based biome changes
var time_of_day: float = 0.0
var biome_modulation: Color = Color.WHITE

func _process(delta):
    time_of_day += delta * 0.01

    # Fire-Ice Basin: Glow at "night"
    if current_biome == Biome.FIRE_ICE_BASIN:
        var glow = sin(time_of_day) * 0.5 + 0.5
        biome_modulation = Color(1.0, 1.0, 1.0 + glow * 0.3)
```

---

## Part 9: Performance Considerations

### 9.1 LOD for Biome Details

Biome color details should fade at distance:

```glsl
// In fragment shader
float detail_distance = 500.0;
float detail_factor = clamp(detail_distance / v_camera_distance, 0.0, 1.0);
biome_color = mix(vec3(0.9), biome_color, detail_factor);  // Fade to generic color far away
```

### 9.2 Instancer Density LOD

```gdscript
# Reduce prop density in distant biomes
if player_distance_to_biome > 2000.0:
    instancer.density *= 0.5
```

### 9.3 Shader Complexity

Keep biome calculations simple in the fragment shader. Pre-calculate biome IDs in vertex shader or even pre-bake into a texture map for best performance.

---

## Part 10: Testing & Debugging

### 10.1 Biome Visualization Debug Mode

Add a debug view to see biome IDs as colors:

```glsl
// In fragment shader, add debug mode
uniform bool u_debug_show_biomes = false;

if (u_debug_show_biomes) {
    // Color-code biomes for debugging
    vec3 debug_colors[5] = vec3[](
        vec3(1, 0, 0),  // Landing Basin = Red
        vec3(0, 1, 0),  // Cryo Plains = Green
        vec3(0, 0, 1),  // Ore Highlands = Blue
        vec3(1, 1, 0),  // Fire-Ice Basin = Yellow
        vec3(1, 0, 1)   // Living Lode Canyon = Magenta
    );
    ALBEDO = debug_colors[int(v_biome_id)];
    return;
}
```

### 10.2 In-Game Console Commands

```gdscript
# Add to game console
func _on_console_command(cmd: String):
    if cmd == "debug_biomes":
        _toggle_biome_debug()
    elif cmd.begins_with("teleport_biome "):
        var biome_id = int(cmd.split(" ")[1])
        _teleport_to_biome(biome_id)
```

---

## Summary

This implementation provides:

✅ **5 Distinct Visual Biomes** - Color-coded regions matching your GDD
✅ **Unique Terrain Features** - Craters, highlands, canyons, plains
✅ **Biome-Specific Resources** - Different props/rocks per region
✅ **Gameplay Integration** - Detection system for location-based mechanics
✅ **Performance Optimized** - LOD and efficient shader calculations
✅ **Extensible** - Easy to add more biomes or modify existing ones

The modular approach allows you to implement incrementally:
1. Start with visual biomes (colors only)
2. Add terrain features
3. Implement resource distribution
4. Polish with effects

Good luck with implementation! 화이팅! 🚀
