shader_type spatial;

#include "res://addons/zylann.voxel/shaders/transvoxel.gdshaderinc"
#include "res://addons/zylann.voxel/shaders/lod_fade.gdshaderinc"
#include "res://addons/zylann.voxel/shaders/virtual_texturing.gdshaderinc"

uniform sampler2D u_top_albedo_texture : source_color;
uniform sampler2D u_top_normal_texture;
uniform sampler2D u_side_albedo_texture : source_color;
uniform sampler2D u_side_normal_texture;
uniform sampler2D u_global_normalmap;// : hint_normal;
uniform float u_mountain_height;
uniform vec3 u_top_modulate : source_color = vec3(1.0);
uniform vec3 u_global_color_tint : source_color = vec3(0.45, 0.40, 0.38);  // Dark reddish-brown tint for entire planet

// Biome system - uses 3D distance on sphere surface
uniform float u_planet_radius = 8000.0;

// Biome centers are on the sphere surface (length = planet_radius)
// Set from GDScript as: direction.normalized() * planet_radius
uniform vec3 u_landing_basin_center = vec3(0.0, 8000.0, 0.0);
uniform float u_landing_basin_radius = 1200.0;
uniform vec3 u_fire_ice_center = vec3(0.0, 0.0, -8000.0);
uniform float u_fire_ice_radius = 1800.0;
uniform vec3 u_canyon_center = vec3(-8000.0, 0.0, 0.0);
uniform float u_canyon_radius = 2500.0;

// Biome colors - Makemake surface (tholin + methane ice)
uniform vec3 u_landing_basin_color : source_color = vec3(0.95, 0.90, 0.85);
uniform vec3 u_cryo_plains_color : source_color = vec3(0.85, 0.75, 0.70);
uniform vec3 u_ore_highlands_color : source_color = vec3(0.75, 0.60, 0.50);
uniform vec3 u_fire_ice_color : source_color = vec3(0.65, 0.55, 0.50);
uniform vec3 u_canyon_color : source_color = vec3(0.50, 0.40, 0.35);

// Crater dust system (max 10 craters) - uses 3D distance
uniform int u_crater_count = 0;
uniform vec3 u_crater_centers[10];
uniform float u_crater_radii[10];
uniform vec3 u_crater_dust_color : source_color = vec3(0.80, 0.75, 0.65);

// From Voxel Tools API
// TODO Switch to instance uniforms when they work, see Godot issue #54897
// instance uniform vec3 u_block_local_position = vec3(0.0);
// instance uniform vec2 u_lod_fade = vec2(0.0);
// Debug diagnostic modes (set in editor inspector):
// 0 = normal rendering
// 1 = height quantization bands (10m intervals)
// 2 = flat gray + virtual texture normals (isolates VT normal banding)
// 3 = normal radial component (shows normal quantization)
// 4 = height quantization bands (5m intervals, finer)
// 5 = flat gray + geometry normals only (isolates pure geometry banding)
// 6 = flat gray + UNLIT (isolates mesh silhouette only)
uniform int u_debug_mode : hint_range(0, 6, 1) = 0;

uniform mat4 u_block_local_transform;

varying vec3 v_up_planet;
//varying vec3 v_planet_normal;
varying float v_planet_height;
varying vec3 v_triplanar_uv;
//varying vec3 v_triplanar_power_normal;
varying float v_camera_distance;
varying vec3 v_normal_model;

varying vec3 v_vertex_pos_model;
varying vec3 v_local_pos;  // For biome detection

vec4 triplanar_texture(sampler2D p_sampler, vec3 p_weights, vec3 p_triplanar_pos) {
	vec4 samp = vec4(0.0);
	samp += texture(p_sampler, p_triplanar_pos.xy) * p_weights.z;
	samp += texture(p_sampler, p_triplanar_pos.xz) * p_weights.y;
	samp += texture(p_sampler, p_triplanar_pos.zy * vec2(-1.0, 1.0)) * p_weights.x;
	return samp;
}

// Spherical arc distance between two points on a sphere surface
// Uses the angle between normalized direction vectors * radius
float sphere_arc_distance(vec3 pos_a, vec3 pos_b, float radius) {
	vec3 dir_a = normalize(pos_a);
	vec3 dir_b = normalize(pos_b);
	float cos_angle = clamp(dot(dir_a, dir_b), -1.0, 1.0);
	return acos(cos_angle) * radius;
}

void vertex() {
	VERTEX = get_transvoxel_position(VERTEX, CUSTOM0);
	v_vertex_pos_model = VERTEX;

	// Note, this transform does not contain any scale or rotation...
	// See `voxel_mesh_block_vlt.cpp`
	mat4 planet_transform = u_block_local_transform;
	vec3 local_pos = (planet_transform * vec4(VERTEX, 1.0)).xyz;
	//vec3 local_pos = VERTEX + u_block_local_position;

	v_up_planet = normalize(local_pos);
	v_normal_model = NORMAL;
	v_planet_height = length(local_pos);
	v_triplanar_uv = local_pos * 0.05;
	v_local_pos = local_pos;  // Store for biome detection

	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_camera_distance = distance(wpos, cam_pos);

	TANGENT = vec3(0.0, 0.0, -1.0) * abs(NORMAL.x);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(NORMAL.y);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(NORMAL.z);
	TANGENT = normalize(TANGENT);
	BINORMAL = vec3(0.0, -1.0, 0.0) * abs(NORMAL.x);
	BINORMAL += vec3(0.0, 0.0, 1.0) * abs(NORMAL.y);
	BINORMAL += vec3(0.0, -1.0, 0.0) * abs(NORMAL.z);
	BINORMAL = normalize(BINORMAL);
}

void fragment() {
	vec3 normal_model;
	vec3 normal_view = get_voxel_normal_view_model(v_vertex_pos_model,
		NORMAL, VIEW_MATRIX * MODEL_MATRIX,
		v_normal_model, normal_model);
	normal_model = normalize(normal_model);

	// Compute smooth normal for flatness/topness: blend analytical sphere normal
	// with terrain tangent to preserve slope info without voxel quantization.
	vec3 terrain_tangent = normal_model - dot(normal_model, v_up_planet) * v_up_planet;
	vec3 smooth_normal = normalize(v_up_planet + terrain_tangent * 0.8);
	float flatness = max(dot(smooth_normal, v_up_planet), 0.0);
	float topness = smoothstep(0.85, 1.0, flatness);  // Widened from 0.95 to reduce quantization sensitivity

	float mountain_height = u_mountain_height;
	float mountain_smoothness = 50.0;  // Wide transition to span multiple LOD cells (8-64m)
	float mountain_factor = smoothstep(
		mountain_height - mountain_smoothness,
		mountain_height + mountain_smoothness, v_planet_height);
	topness = mix(topness, 0.0, mountain_factor);

	// Triplanar weights from analytical sphere normal (v_up_planet) to eliminate
	// voxel normal quantization banding. normal_model is quantized by the voxel
	// grid, and pow() amplifies those discrete steps into visible concentric rings.
	// v_up_planet = normalize(local_pos) is perfectly smooth and continuous.
	float triplanar_blend_sharpness = 2.5;
	vec3 triplanar_power_normal = pow(abs(v_up_planet), vec3(triplanar_blend_sharpness));
	triplanar_power_normal /= dot(triplanar_power_normal, vec3(1.0));

	vec3 top_col = triplanar_texture(
		u_top_albedo_texture, triplanar_power_normal, v_triplanar_uv).rgb * u_top_modulate;
	vec3 top_norm = triplanar_texture(
		u_top_normal_texture, triplanar_power_normal, v_triplanar_uv).rgb;

	vec3 side_col = triplanar_texture(
		u_side_albedo_texture, triplanar_power_normal, v_triplanar_uv).rgb;
	vec3 side_norm = triplanar_texture(
		u_side_normal_texture, triplanar_power_normal, v_triplanar_uv).rgb;

	// Far texturing — transition pushed to 800-4000m so the UV-scale change
	// ring is far enough away to be imperceptible from ground level.
	// Near 100-200m, the ring swept through the terrain with every camera
	// movement, causing the "flowing contour" artifact.
	float far_min_distance = 800.0;
	float far_max_distance = 4000.0;
	float far_uv_multiplier = 0.19;
	float far_factor =
		clamp((v_camera_distance - far_min_distance) / (far_max_distance - far_min_distance), 0.0, 1.0);
	vec3 far_side_col = triplanar_texture(
		u_side_albedo_texture, triplanar_power_normal, v_triplanar_uv * far_uv_multiplier).rgb;
	vec3 far_side_norm = triplanar_texture(
		u_side_normal_texture, triplanar_power_normal, v_triplanar_uv * far_uv_multiplier).rgb;
	side_col = mix(side_col, far_side_col, far_factor);
	side_norm = mix(side_norm, far_side_norm, far_factor);

	// --- Biome detection using 3D spherical arc distance ---
	float height_from_surface = v_planet_height - u_planet_radius;
	// Break contour banding: use normalized direction (not quantized position)
	// so vertices at the same height get different noise values.
	vec3 noise_pos = normalize(v_local_pos) * 30.0;
	float height_noise =
		  sin(noise_pos.x * 7.3  + noise_pos.z * 5.1)  * 50.0   // coarse XZ
		+ sin(noise_pos.z * 11.7 + noise_pos.x * 8.9)  * 30.0   // medium XZ
		+ sin(noise_pos.x * 3.7  + noise_pos.y * 6.3)  * 25.0   // coarse XY
		+ sin(noise_pos.z * 17.1 + noise_pos.y * 4.7)  * 20.0;  // medium ZY
	// Total amplitude ~125m
	float perturbed_height = height_from_surface + height_noise;

	// Start with default: Cryo Plains
	vec3 biome_color = u_cryo_plains_color;

	// 1. Landing Basin - spherical distance from basin center
	float landing_dist = sphere_arc_distance(v_local_pos, u_landing_basin_center, u_planet_radius);
	float landing_blend = 1.0 - smoothstep(u_landing_basin_radius * 0.7, u_landing_basin_radius, landing_dist);
	biome_color = mix(biome_color, u_landing_basin_color, landing_blend);

	// 2. Ore Highlands - elevation-based.  Range widened to -40..180 so that
	//    the ±125m noise fully overlaps both edges — no hard contour line.
	float highland_blend = smoothstep(-40.0, 180.0, perturbed_height);
	biome_color = mix(biome_color, u_ore_highlands_color, highland_blend);

	// 3. Fire-Ice Basin - spherical distance from basin center
	float fire_ice_dist = sphere_arc_distance(v_local_pos, u_fire_ice_center, u_planet_radius);
	float fire_ice_blend = 1.0 - smoothstep(u_fire_ice_radius * 0.7, u_fire_ice_radius, fire_ice_dist);
	biome_color = mix(biome_color, u_fire_ice_color, fire_ice_blend);

	// 4. Living Lode Canyon - spherical distance from canyon center
	float canyon_dist = sphere_arc_distance(v_local_pos, u_canyon_center, u_planet_radius);
	float canyon_blend = 1.0 - smoothstep(u_canyon_radius * 0.7, u_canyon_radius, canyon_dist);
	biome_color = mix(biome_color, u_canyon_color, canyon_blend);

	// --- Crater dust using 3D distance ---
	float dust_factor = 0.0;
	if (u_crater_count > 0) {
		for (int i = 0; i < u_crater_count && i < 10; i++) {
			// 3D distance from crater center on sphere
			float dist_3d = length(v_local_pos - u_crater_centers[i]);
			float normalized_dist = dist_3d / u_crater_radii[i];
			// Dust ring around rim (0.8 to 2.0 radius)
			float crater_dust = smoothstep(2.0, 0.8, normalized_dist);
			dust_factor = max(dust_factor, crater_dust);
		}
	}

	vec3 base_albedo = mix(side_col, top_col, topness);
	vec3 colored_albedo = base_albedo * biome_color;
	ALBEDO = mix(colored_albedo, base_albedo * u_crater_dust_color, dust_factor * 0.6);

	// Manual TBN construction from analytical sphere normal to bypass quantized
	// vertex TANGENT/BINORMAL. Godot's NORMAL_MAP uses the vertex TBN which is
	// derived from quantized geometry normals — this re-injects banding.
	vec3 N = normalize(smooth_normal);
	// Construct tangent: cross with reference axis, fallback for poles
	vec3 ref_axis = abs(N.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 T = normalize(cross(ref_axis, N));
	vec3 B = cross(N, T);
	// Decode and apply normal map manually
	vec3 nm_tangent = mix(side_norm, top_norm, topness) * 2.0 - 1.0;
	vec3 final_normal_model = normalize(T * nm_tangent.x + B * nm_tangent.y + N * nm_tangent.z);
	vec3 final_normal_view = (VIEW_MATRIX * MODEL_MATRIX * vec4(final_normal_model, 0.0)).xyz;
	NORMAL = normalize(final_normal_view);
	// Do NOT set NORMAL_MAP — we handle it manually above

	// --- Debug diagnostic overrides ---
	if (u_debug_mode == 1) {
		// Mode 1: Height quantization (10m bands) — contour = voxel grid stepping
		ALBEDO = vec3(fract(v_planet_height * 0.1));
	} else if (u_debug_mode == 2) {
		// Mode 2: Flat gray — if banding persists, it's lighting/normal issue
		ALBEDO = vec3(0.5);
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
	} else if (u_debug_mode == 3) {
		// Mode 3: Normal radial dot — shows normal quantization as brightness steps
		ALBEDO = vec3(dot(normal_model, v_up_planet));
	} else if (u_debug_mode == 4) {
		// Mode 4: Height quantization (5m bands) — finer view
		ALBEDO = vec3(fract(v_planet_height * 0.2));
	} else if (u_debug_mode == 5) {
		// Mode 5: Flat gray + geometry normals only (no virtual texture normals)
		ALBEDO = vec3(0.5);
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
		NORMAL = (VIEW_MATRIX * MODEL_MATRIX * vec4(v_normal_model, 0.0)).xyz;
	} else if (u_debug_mode == 6) {
		// Mode 6: UNLIT flat gray — only mesh silhouette/geometry visible
		ALBEDO = vec3(0.7);
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
		NORMAL = (VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	}

	// No fake emission - this is a dark, airless world lit only by the distant sun
	ROUGHNESS = 0.85;

	// Debug virtual texture fallbacks
	/*if(u_voxel_virtual_texture_offset_scale.w < 0.51) {
		ALBEDO = vec3(1.0, 0.0, 0.0);
	}
	if(u_voxel_virtual_texture_offset_scale.w < 0.251) {
		ALBEDO = vec3(1.0, 0.5, 0.0);
	}
	if(u_voxel_virtual_texture_offset_scale.w < 0.1251) {
		ALBEDO = vec3(1.0, 1.0, 0.0);
	}
	if(u_voxel_virtual_texture_offset_scale.w < 0.06251) {
		ALBEDO = vec3(0.0, 1.0, 0.0);
	}
	if(u_voxel_virtual_texture_offset_scale.w == 0.0) {
		ALBEDO = vec3(1.0, 0.0, 1.0);
	}*/

	// Discard has to be last to workaround https://github.com/godotengine/godot/issues/34966
	if (get_lod_fade_discard(SCREEN_UV)) {
		discard;
	}
}