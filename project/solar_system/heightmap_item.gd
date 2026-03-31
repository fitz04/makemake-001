## HeightmapItem - Data class for heightmap stamps
## Usage: Create items that can be stamped onto terrain using raycast
class_name HeightmapItem
extends Resource

@export var name: String = "Heightmap"
@export var image: Texture2D = null
@export var scale_intensity: float = 1.0  # 0.1 to 3.0, multiplier for height variation
@export var blend_mode: BlendMode = BlendMode.REPLACE  # REPLACE or ADD
@export var radius: float = 20.0  # Radius in meters to apply heightmap

enum BlendMode {
	REPLACE,  # Completely replace terrain height
	ADD,      # Add to existing terrain
}

## Gets the pixel value at normalized UV coordinates
func sample_height(uv: Vector2) -> float:
	if image == null:
		print("ERROR: Heightmap image is null!")
		return 0.5  # Neutral gray

	var img = image.get_image()
	if img == null:
		print("ERROR: Could not get_image() from texture: %s" % image)
		return 0.5

	# Clamp UV to 0-1 range
	var clamped_uv = uv.clamp(Vector2.ZERO, Vector2.ONE)

	# Convert to pixel coordinates
	var pixel_x = int(clamped_uv.x * (img.get_width() - 1))
	var pixel_y = int(clamped_uv.y * (img.get_height() - 1))

	var pixel = img.get_pixel(pixel_x, pixel_y)

	# Return grayscale value
	# PNG16은 R채널이 높이 정보를 가짐
	var height_value = pixel.r

	# Debug disabled - too much logging
	# if randf() < 0.01:
	# 	print("Sample at UV(%.2f, %.2f) -> pixel(%d, %d) = %.3f (RGBA: %.3f, %.3f, %.3f, %.3f)" %
	# 		[clamped_uv.x, clamped_uv.y, pixel_x, pixel_y, height_value,
	# 		 pixel.r, pixel.g, pixel.b, pixel.a])

	return height_value


## Applies this heightmap to terrain at world position using SDF modification
## Returns the number of voxels modified
func apply_to_terrain(volume: VoxelLodTerrain, world_pos: Vector3, surface_normal: Vector3) -> int:
	if image == null:
		push_error("HeightmapItem: No image assigned")
		return 0

	var vt: VoxelToolLodTerrain = volume.get_voxel_tool()
	var local_pos = volume.get_global_transform().affine_inverse() * world_pos

	vt.channel = VoxelBuffer.CHANNEL_SDF

	var img = image.get_image()
	if img == null:
		print("ERROR: Could not get image from texture!")
		return 0

	# Debug: Check image properties to verify it loaded correctly
	print("Image properties: size=%dx%d, format=%s, has_mipmaps=%s" %
		[img.get_width(), img.get_height(), img.get_format(), img.has_mipmaps()])

	# Sample a few pixels across the image to check if there's actual variation
	var sample_positions = [
		Vector2(0.1, 0.1),  # Top-left area
		Vector2(0.5, 0.5),  # Center
		Vector2(0.9, 0.9),  # Bottom-right area
		Vector2(0.25, 0.75), # Mixed
		Vector2(0.75, 0.25)  # Mixed
	]
	print("Pixel samples across image:")
	for pos in sample_positions:
		var px = int(pos.x * (img.get_width() - 1))
		var py = int(pos.y * (img.get_height() - 1))
		var pixel = img.get_pixel(px, py)
		print("  UV(%.2f, %.2f) = RGBA(%.3f, %.3f, %.3f, %.3f)" %
			[pos.x, pos.y, pixel.r, pixel.g, pixel.b, pixel.a])

	var modified_count = 0
	var add_count = 0
	var remove_count = 0
	var radius_voxels = int(radius)

	# Convert surface normal from world space to local space
	# surface_normal is a direction (not a position), so we don't translate it
	var volume_basis = volume.get_global_transform().basis
	var volume_global_transform = volume.get_global_transform()
	var normalized_normal = (volume_basis.inverse() * surface_normal).normalized()

	print("\n=== Heightmap Application Debug ===")
	print("World hit position: (%.1f, %.1f, %.1f)" % [world_pos.x, world_pos.y, world_pos.z])
	print("World surface normal (from planet center): (%.3f, %.3f, %.3f)" % [surface_normal.x, surface_normal.y, surface_normal.z])
	print("Volume global position: (%.1f, %.1f, %.1f)" % [volume_global_transform.origin.x, volume_global_transform.origin.y, volume_global_transform.origin.z])
	print("Volume basis X: (%.3f, %.3f, %.3f)" % [volume_basis.x.x, volume_basis.x.y, volume_basis.x.z])
	print("Volume basis Y: (%.3f, %.3f, %.3f)" % [volume_basis.y.x, volume_basis.y.y, volume_basis.y.z])
	print("Volume basis Z: (%.3f, %.3f, %.3f)" % [volume_basis.z.x, volume_basis.z.y, volume_basis.z.z])
	print("Heightmap: name=%s, image_size=%dx%d, radius=%.1fm (scale_intensity=%.2f)" %
		[name, img.get_width(), img.get_height(), radius, scale_intensity])
	print("Local position: %.1f, %.1f, %.1f | Surface normal (local): (%.3f, %.3f, %.3f)" %
		[local_pos.x, local_pos.y, local_pos.z, normalized_normal.x, normalized_normal.y, normalized_normal.z])

	# Sample the center point for diagnostics
	var center_uv = _world_to_uv_relative(world_pos, world_pos)
	var center_height = sample_height(center_uv)
	print("Center: UV(%.3f, %.3f) | height=%.3f" % [center_uv.x, center_uv.y, center_height])

	# Create local coordinate system (tangent space) at hit point
	var tangent_space = _create_local_tangent_space(surface_normal)
	var right = tangent_space["right"]
	var forward = tangent_space["forward"]
	# Use actual hit position's radius instead of fixed value
	var planet_radius = world_pos.length()

	print("Tangent space - Right: (%.3f, %.3f, %.3f) | Forward: (%.3f, %.3f, %.3f)" %
		[right.x, right.y, right.z, forward.x, forward.y, forward.z])

	# SDF direct modification: more accurate than sphere-based approach
	# Step = 1 for smoothest results (may be slow for very large radii)
	var step = 1

	# Estimate sample count for performance warning
	var estimated_samples = int((radius_voxels * 2 / step) ** 2 * 0.785)  # Pi/4 for circle
	if estimated_samples > 5000:
		print("⚠️ WARNING: Large stamp will process %d samples (may take a moment)" % estimated_samples)
	var samples_tested = 0
	var samples_modified = 0

	# Define vertical range for 3D voxel modification
	# This allows proper terrain raising/digging through multiple layers
	# Larger range = smoother transitions
	var vertical_range = int(radius * scale_intensity * 0.3)  # Height range in voxels
	vertical_range = max(vertical_range, 20)  # Minimum 20 voxels for smooth results

	for x in range(-radius_voxels, radius_voxels + 1, step):
		for z in range(-radius_voxels, radius_voxels + 1, step):
			var horizontal_distance = sqrt(float(x * x + z * z))
			if horizontal_distance > radius_voxels:
				continue

			samples_tested += 1

			# Calculate offset in tangent space (local coordinate system on sphere surface)
			var offset_tangent = right * float(x) + forward * float(z)

			# Apply offset in world space
			var offset_world_pos = world_pos + offset_tangent

			# Project onto sphere surface to follow planet curvature
			var direction = offset_world_pos.normalized()
			var projected_world_pos = direction * planet_radius

			# Convert projected world position to voxel local space
			var sample_local_pos = volume.get_global_transform().affine_inverse() * projected_world_pos

			# Get UV coordinates relative to stamp center
			var uv = _world_to_uv_relative(projected_world_pos, world_pos)
			var height_sample = sample_height(uv)

			# Calculate smooth falloff from center using cosine interpolation
			# This creates very smooth, natural-looking transitions
			var normalized_distance = horizontal_distance / max(1.0, float(radius_voxels))
			var falloff = smoothstep(1.0, 0.0, normalized_distance)  # Very smooth falloff

			# Height relative to middle gray (0.5)
			# Standard heightmap: Black (0.0) = dig, Gray (0.5) = neutral, White (1.0) = raise
			var height_delta = (height_sample - 0.5) * 2.0

			# Apply with intensity scaling and falloff
			var strength = falloff * height_delta * scale_intensity

			# Debug: print first few samples
			if samples_tested <= 3:
				print("  Sample %d: UV=(%.3f,%.3f) height=%.3f strength=%.2f" %
					[samples_tested, uv.x, uv.y, height_sample, strength])

			# Skip if strength is too weak
			if abs(strength) < 0.1:
				continue

			# Apply SDF modification in vertical range
			# This creates proper height variation by modifying multiple voxel layers
			var height_offset = strength * 15.0  # Convert strength to voxel height

			for y_offset in range(-vertical_range, vertical_range + 1):
				var voxel_pos = sample_local_pos + (normalized_normal * float(y_offset))

				# Get current SDF value
				var current_sdf = vt.get_voxel_f(voxel_pos)

				# Calculate smooth SDF based on distance from target surface
				# Use smooth distance function instead of hard step
				var distance_from_target = float(y_offset) - height_offset

				# Apply smooth transition using smoothstep-like function
				# This creates gradual terrain changes instead of sharp edges
				var smooth_factor = 2.0  # Controls smoothness (lower = smoother)
				var new_sdf = distance_from_target / smooth_factor

				# Blend with existing SDF using smooth blending
				# Use lower blend factor for more visible changes
				var blend_factor = 0.5  # 50% new, 50% existing
				var blended_sdf = lerp(current_sdf, new_sdf, blend_factor)

				# Set the new SDF value
				vt.set_voxel_f(voxel_pos, blended_sdf)
				samples_modified += 1

			if strength > 0.0:
				add_count += 1
			else:
				remove_count += 1

			modified_count += 1

	print("\n=== APPLICATION SUMMARY ===")
	print("Samples tested: %d | Modified: %d (%.1f%%)" % [samples_tested, modified_count, (float(modified_count) / max(1, samples_tested) * 100.0)])
	print("✓ Applied '%s' using SDF modification (ADD: %d, REMOVE: %d)" % [name, add_count, remove_count])
	print("   Total voxels modified: %d" % samples_modified)

	if modified_count > 0:
		print("✅ SUCCESS - Terrain modified with SDF!")
		print("   Method: Direct SDF value modification (more accurate than spheres)")
		print("   Coverage: %.1f%% of tested samples" % (float(modified_count) / max(1, samples_tested) * 100.0))
	else:
		print("❌ FAILURE - No modifications made!")
		print("  Possible issues:")
		print("  - All pixels near 0.5 (gray)?")
		print("  - UV coordinates outside 0-1 range?")
		print("  - Threshold too high?")
	print("=========================\n")

	return modified_count


## Generate preview data without modifying terrain
## Returns array of dictionaries containing {pos: Vector3, radius: float, is_add: bool}
func preview_heightmap_application(volume: VoxelLodTerrain, world_pos: Vector3, surface_normal: Vector3) -> Array:
	if image == null:
		return []

	var vt: VoxelToolLodTerrain = volume.get_voxel_tool()
	var local_pos = volume.get_global_transform().affine_inverse() * world_pos

	vt.channel = VoxelBuffer.CHANNEL_SDF

	var img = image.get_image()
	if img == null:
		return []

	var preview_data: Array = []
	var radius_voxels = int(radius)

	# Create local coordinate system (tangent space) at hit point
	var tangent_space = _create_local_tangent_space(surface_normal)
	var right = tangent_space["right"]
	var forward = tangent_space["forward"]
	# Use actual hit position's radius instead of fixed value
	var planet_radius = world_pos.length()

	# Use larger step for preview to reduce calculation count
	# step=6 reduces iterations by ~36x (e.g., 81x81=6561 → 14x14=196)
	var preview_step = 6

	# Limit maximum preview spheres for performance
	var max_preview_spheres = 150

	for x in range(-radius_voxels, radius_voxels + 1, preview_step):
		for z in range(-radius_voxels, radius_voxels + 1, preview_step):
			# Early exit if we have enough preview spheres
			if preview_data.size() >= max_preview_spheres:
				break

			var distance = sqrt(float(x * x + z * z))
			if distance > radius_voxels:
				continue

			# Calculate offset in tangent space (local coordinate system on sphere surface)
			var offset_tangent = right * float(x) + forward * float(z)

			# Apply offset in world space
			var offset_world_pos = world_pos + offset_tangent

			# Project onto sphere surface to follow planet curvature
			var direction = offset_world_pos.normalized()
			var projected_world_pos = direction * planet_radius

			# Convert projected world position to voxel local space
			var sample_local_pos = volume.get_global_transform().affine_inverse() * projected_world_pos

			# Get UV coordinates relative to stamp center
			var uv = _world_to_uv_relative(projected_world_pos, world_pos)
			var height_sample = sample_height(uv)

			# Calculate smooth falloff from center
			var normalized_distance = distance / max(1.0, float(radius_voxels))
			var falloff = pow(1.0 - normalized_distance, 2.0)

			# Height relative to middle gray (0.5)
			# Standard heightmap: Black (0.0) = dig, Gray (0.5) = neutral, White (1.0) = raise
			var height_delta = (height_sample - 0.5) * 2.0

			# Apply with intensity scaling and falloff
			var strength = falloff * height_delta * scale_intensity

			# Higher threshold for preview to show only significant features
			if abs(strength) > 0.5:
				var sphere_radius = clamp(0.3 + (abs(strength) * 1.0), 0.2, 1.5)
				var is_add = strength > 0.0

				preview_data.append({
					"pos": sample_local_pos,
					"radius": sphere_radius,
					"is_add": is_add
				})

		# Break outer loop too if limit reached
		if preview_data.size() >= max_preview_spheres:
			break

	return preview_data


## Convert world position to UV coordinates relative to stamp center (planar projection)
func _world_to_uv_relative(sample_pos: Vector3, center_pos: Vector3) -> Vector2:
	# Using planar XZ projection for Gaea heightmaps
	# Map world XZ offset from center to 0-1 UV range

	# Calculate offset from stamp center
	var offset = sample_pos - center_pos

	# Normalize offset to -radius to +radius range, then map to 0-1
	# At center: offset=0 → UV=(0.5, 0.5)
	# At edge: offset=radius → UV=(1.0, 1.0)
	var u = (offset.x / radius) * 0.5 + 0.5
	var v = (offset.z / radius) * 0.5 + 0.5

	# Clamp to 0-1 range
	u = clamp(u, 0.0, 1.0)
	v = clamp(v, 0.0, 1.0)

	return Vector2(u, v)


## Create local coordinate system (tangent space) at a point on sphere
## Returns dictionary with {right: Vector3, forward: Vector3, up: Vector3}
func _create_local_tangent_space(surface_normal: Vector3) -> Dictionary:
	var up = surface_normal.normalized()

	# Create right vector perpendicular to up
	# Try using world Y axis first
	var right = up.cross(Vector3.UP)

	# If up is nearly parallel to world Y, use world X instead
	if right.length_squared() < 0.01:
		right = up.cross(Vector3.RIGHT)

	right = right.normalized()

	# Forward is perpendicular to both up and right
	var forward = right.cross(up).normalized()

	return {
		"right": right,
		"forward": forward,
		"up": up
	}
