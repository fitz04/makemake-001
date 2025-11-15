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

// Biome system
uniform float u_planet_radius = 8000.0;
uniform vec3 u_landing_basin_center = vec3(0.0, 0.0, 0.0);
uniform float u_landing_basin_radius = 1200.0;
uniform vec3 u_fire_ice_center = vec3(0.0, 0.0, -4500.0);  // FAR SOUTH 4500m
uniform float u_fire_ice_radius = 1800.0;
uniform float u_canyon_min_x = -5500.0;  // FAR WEST boundary
uniform float u_canyon_max_x = -3000.0;  // Canyon east boundary
uniform float u_canyon_min_z = -1500.0;  // Canyon north boundary (narrower)
uniform float u_canyon_max_z = 1500.0;   // Canyon south boundary (narrower)
uniform vec3 u_landing_basin_color : source_color = vec3(0.70, 0.60, 0.55);  // Slightly brighter patch (methane ice)
uniform vec3 u_cryo_plains_color : source_color = vec3(0.45, 0.35, 0.30);    // Dominant dark reddish-brown (tholin)
uniform vec3 u_ore_highlands_color : source_color = vec3(0.55, 0.42, 0.36);  // Medium reddish-brown
uniform vec3 u_fire_ice_color : source_color = vec3(0.40, 0.30, 0.25);       // Very dark brown (crater)
uniform vec3 u_canyon_color : source_color = vec3(0.35, 0.25, 0.22);         // Darkest brown (canyon)

// Crater dust system (max 10 craters)
uniform int u_crater_count = 0;
uniform vec3 u_crater_centers[10];
uniform float u_crater_radii[10];
uniform vec3 u_crater_dust_color : source_color = vec3(0.75, 0.70, 0.60);  // Lighter dust - more visible up close
uniform float u_crater_dust_falloff = 2.0;  // Dust ring around rim
uniform int u_crater_ray_count = 12;  // Subtle ray hints
uniform float u_crater_ray_width = 0.15;  // Very thin rays
uniform float u_crater_ray_length = 1.5;  // Very short rays - about 1 radius length

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

// Simple hash function for pseudo-random ray angles
float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

// Calculate ejecta ray intensity for a single crater
float calculate_crater_rays(vec2 pos, vec2 crater_center, float crater_radius, int ray_count, float ray_width) {
	vec2 dir = pos - crater_center;
	float dist = length(dir);

	// Only apply rays outside rim (starting at 1.0 * radius)
	if (dist < crater_radius) {
		return 0.0;
	}

	// Angle from crater center
	float angle = atan(dir.y, dir.x);

	// Normalize to 0-1 range
	float angle_norm = (angle + 3.14159265) / (2.0 * 3.14159265);

	// Create rays using modulo pattern
	float ray_segment = angle_norm * float(ray_count);
	float ray_id = floor(ray_segment);
	float ray_fract = fract(ray_segment);

	// Add strong randomness to ray angles for irregular pattern
	float angle_jitter = (hash(ray_id * 12.345) - 0.5) * 0.6;  // Doubled jitter
	ray_fract += angle_jitter;
	ray_fract = fract(ray_fract);

	// Random ray width per ray (some thicker, some thinner)
	float width_variation = hash(ray_id * 45.678) * 0.5 + 0.5;  // 0.5 to 1.0
	float adjusted_width = ray_width * width_variation;

	// Ray intensity with jagged edges
	float ray_pattern = smoothstep(0.5 - adjusted_width, 0.5, ray_fract) *
	                     smoothstep(0.5 + adjusted_width, 0.5, ray_fract);

	// Add distance-based texture variation (makes rays look broken/patchy)
	float noise = hash(dist * 0.1 + ray_id);
	ray_pattern *= smoothstep(0.3, 0.7, noise);  // Patchy appearance

	// Fade rays with distance (stronger near crater, fade far away)
	float normalized_dist = dist / crater_radius;
	float distance_fade = 1.0 - smoothstep(1.0, u_crater_ray_length, normalized_dist);

	return ray_pattern * distance_fade;
}

// float skew3(float x) {
// 	return (x * x * x + x) * 0.5;
// }

// vec2 get_sphere_uv(vec3 npos) {
// 	vec2 uv = vec2(
// 		-(atan(npos.z, npos.x) / TAU) + 0.5,
// 		-0.5 * skew3(npos.y) + 0.5
// 	);
// 	return uv;
// }

// float pow8(float x) {
// 	return x*x*x*x * x*x*x*x;
// }

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

	float triplanar_blend_sharpness = 3.0;  // Softer blending to reduce slope artifacts
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

	// Biome detection - Height-based only: Ore Highlands > Cryo Plains
	float height_from_surface = v_planet_height - u_planet_radius;

	vec3 biome_color = u_cryo_plains_color;  // Default: Cryo Plains

	// Ore Highlands (above 50m elevation)
	if (height_from_surface > 50.0) {
		float highland_blend = smoothstep(30.0, 70.0, height_from_surface);
		biome_color = mix(u_cryo_plains_color, u_ore_highlands_color, highland_blend);
	}
	// Default: Cryo Plains (already set)

	// Crater dust - bright silicate dust around crater rims + ejecta rays
	float dust_factor = 0.0;
	float ray_factor = 0.0;
	if (u_crater_count > 0) {
		float min_normalized_dist = 999999.0;
		for (int i = 0; i < u_crater_count && i < 10; i++) {
			// Calculate distance from crater center (2D, ignore Y)
			float dist = length(v_local_pos.xz - u_crater_centers[i].xz);
			// Normalize by crater radius
			float normalized_dist = dist / u_crater_radii[i];
			// Track closest crater
			min_normalized_dist = min(min_normalized_dist, normalized_dist);

			// Calculate ejecta rays for this crater
			float crater_ray = calculate_crater_rays(
				v_local_pos.xz,
				u_crater_centers[i].xz,
				u_crater_radii[i],
				u_crater_ray_count,
				u_crater_ray_width
			);
			ray_factor = max(ray_factor, crater_ray);
		}

		// Dust is strongest near rim (1.0) and fades outward
		// Range: 0.8 (inner edge) to u_crater_dust_falloff (outer edge)
		dust_factor = smoothstep(u_crater_dust_falloff, 0.8, min_normalized_dist);
	}

	vec3 base_albedo = mix(side_col, top_col, topness);
	// Apply biome color, then blend in crater dust and ejecta rays
	vec3 colored_albedo = base_albedo * biome_color;

	// Combine dust ring and ejecta rays
	float total_dust = max(dust_factor, ray_factor);  // Full ray brightness

	ALBEDO = mix(colored_albedo, base_albedo * u_crater_dust_color, total_dust * 0.9);  // Much stronger visibility
	//ALBEDO = base_albedo * u_global_color_tint;  // Uniform dark tint
	//ALBEDO = base_albedo;  // No tint
	NORMAL_MAP = mix(side_norm, top_norm, topness);
	NORMAL = normal_view;
	//ALBEDO = vec3(normal_model);

	// Minimum ambient light for visibility in darkness
	EMISSION = ALBEDO * 0.08;  // Base 8% emission for all terrain

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