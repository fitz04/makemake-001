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

	//vec3 normal = normalize(v_planet_normal);
	float flatness = max(dot(normal_model, v_up_planet), 0.0);
	float topness = smoothstep(0.95, 1.0, flatness);  // More strict: only very flat surfaces get top texture

	float mountain_height = u_mountain_height;
	float mountain_smoothness = 3.0;
	float mountain_factor = smoothstep(
		mountain_height - mountain_smoothness,
		mountain_height + mountain_smoothness, v_planet_height);
	topness = mix(topness, 0.0, mountain_factor);

	// Dynamic triplanar sharpness: sharp close-up (4.0), soft far away (1.5) to hide axis-switch artifacts
	float triplanar_blend_sharpness = mix(1.5, 4.0, clamp(1.0 - v_camera_distance / 500.0, 0.0, 1.0));
	vec3 triplanar_power_normal = pow(abs(normal_model), vec3(triplanar_blend_sharpness));
	triplanar_power_normal /= dot(triplanar_power_normal, vec3(1.0));

	vec3 top_col = triplanar_texture(
		u_top_albedo_texture, triplanar_power_normal, v_triplanar_uv).rgb * u_top_modulate;
	vec3 top_norm = triplanar_texture(
		u_top_normal_texture, triplanar_power_normal, v_triplanar_uv).rgb;

	vec3 side_col = triplanar_texture(
		u_side_albedo_texture, triplanar_power_normal, v_triplanar_uv).rgb;
	vec3 side_norm = triplanar_texture(
		u_side_normal_texture, triplanar_power_normal, v_triplanar_uv).rgb;

	// Far texturing
	float far_min_distance = 100.0;
	float far_max_distance = 200.0;
	float far_uv_multiplier = 0.25;
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

	// Start with default: Cryo Plains
	vec3 biome_color = u_cryo_plains_color;

	// 1. Landing Basin - spherical distance from basin center
	float landing_dist = sphere_arc_distance(v_local_pos, u_landing_basin_center, u_planet_radius);
	float landing_blend = 1.0 - smoothstep(u_landing_basin_radius * 0.7, u_landing_basin_radius, landing_dist);
	biome_color = mix(biome_color, u_landing_basin_color, landing_blend);

	// 2. Ore Highlands - elevation-based (above 50m)
	float highland_blend = smoothstep(10.0, 120.0, height_from_surface);
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
	NORMAL_MAP = mix(side_norm, top_norm, topness);
	NORMAL = normal_view;

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