extends RefCounted
class_name CraterCarver

## Crater Carver - Uses VoxelTool to carve craters on a spherical planet surface.
##
## Unlike CraterGenerator (which modified the VoxelGeneratorGraph and used 2D XZ distance),
## this system uses VoxelTool.do_sphere() to carve craters AFTER terrain generation.
## It uses proper 3D spherical distance so craters conform to the planet's curved surface.
##
## Usage:
##   var carver = CraterCarver.new()
##   carver.planet_radius = 8000.0
##   carver.add_crater(Vector3(0, 1, 0), 500.0, 100.0, 15.0)  # direction, radius, depth, rim
##   carver.carve_all(voxel_lod_terrain)

## Definition for a single crater
class CraterDef:
	## Normalized direction from planet center to crater center on the surface
	var surface_direction: Vector3
	## Radius of the crater bowl on the surface (meters)
	var radius: float
	## Depth of the crater bowl below the surface (meters)
	var depth: float
	## Height of the rim above the surface (meters)
	var rim_height: float
	## Human-readable name for debugging
	var label: String

	func _init(p_direction: Vector3, p_radius: float, p_depth: float, p_rim_height: float, p_label: String = ""):
		surface_direction = p_direction.normalized()
		radius = p_radius
		depth = p_depth
		rim_height = p_rim_height
		label = p_label


## The radius of the planet (must match StellarBody.radius and voxel graph sphere radius)
var planet_radius: float = 8000.0

## Stored crater definitions to be carved
var _craters: Array[CraterDef] = []


## Add a crater by specifying a direction from the planet center.
## The direction vector is normalized internally, so magnitude does not matter.
## This is the preferred method because it works correctly on a sphere.
func add_crater(direction: Vector3, radius: float, depth: float, rim_height: float, label: String = "") -> void:
	_craters.append(CraterDef.new(direction, radius, depth, rim_height, label))


## Add a crater from a flat-world XZ position.
## Converts (x, 0, z) into a proper surface direction on the sphere by projecting
## the point onto the sphere surface via normalization.
## This is a convenience for migrating existing crater definitions that used flat coordinates.
func add_crater_from_flat_position(flat_pos: Vector3, radius: float, depth: float, rim_height: float, label: String = "") -> void:
	# Project the flat position onto the sphere surface.
	# For positions near the "north pole" (0, R, 0), we treat flat_pos.x as longitude
	# and flat_pos.z as latitude offset, then map onto the sphere.
	# The simplest correct approach: treat (x, planet_radius, z) as a point and normalize.
	var world_point := Vector3(flat_pos.x, planet_radius, flat_pos.z)
	var direction := world_point.normalized()
	_craters.append(CraterDef.new(direction, radius, depth, rim_height, label))


## Carve all defined craters into the VoxelLodTerrain using VoxelTool.
## The terrain must be in the scene tree and generating for this to work.
## Returns true if carving was performed, false if no craters or terrain unavailable.
func carve_all(volume: VoxelLodTerrain) -> bool:
	if _craters.is_empty():
		push_warning("CraterCarver: No craters defined, nothing to carve.")
		return false

	if volume == null:
		push_error("CraterCarver: VoxelLodTerrain is null.")
		return false

	var voxel_tool: VoxelTool = volume.get_voxel_tool()
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF

	print("CraterCarver: Carving ", _craters.size(), " craters on planet with radius ", planet_radius)

	for i in range(_craters.size()):
		var crater := _craters[i]
		_carve_single_crater(voxel_tool, crater, i)

	print("CraterCarver: Finished carving all craters.")
	return true


## Carve a single crater using minimal do_sphere() calls.
## Uses only 1-2 sphere operations to avoid performance hang.
func _carve_single_crater(voxel_tool: VoxelTool, crater: CraterDef, index: int) -> void:
	var surface_center: Vector3 = crater.surface_direction * planet_radius
	var crater_label := crater.label if crater.label != "" else "crater_%d" % index
	print("  Carving %s at %s (r=%.0f, d=%.0f)" % [
		crater_label, str(surface_center), crater.radius, crater.depth
	])

	var up := crater.surface_direction

	# Bowl: single sphere placed below the surface to create a concave depression.
	# The sphere center is offset inward so it intersects the surface, creating a bowl shape.
	# A larger offset = shallower/wider bowl, smaller offset = deeper/narrower.
	voxel_tool.mode = VoxelTool.MODE_REMOVE
	var bowl_offset := crater.radius * 0.8  # How far below surface to place sphere center
	var bowl_center := surface_center - up * bowl_offset
	var bowl_sphere_radius := crater.radius  # Match crater radius
	voxel_tool.do_sphere(bowl_center, bowl_sphere_radius)


## Calculate a tangent-plane offset on the sphere surface.
## Given the "up" direction at a point on the sphere and an angle around that point,
## returns a displacement vector in the tangent plane.
func _get_tangent_offset(up: Vector3, angle: float, distance: float) -> Vector3:
	# Build an orthonormal basis on the tangent plane
	var arbitrary := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var tangent_u := up.cross(arbitrary).normalized()
	var tangent_v := up.cross(tangent_u).normalized()
	return (tangent_u * cos(angle) + tangent_v * sin(angle)) * distance


## Determine how many spheres to place in a ring based on crater radius.
## Larger craters need more spheres for a smooth profile.
func _get_ring_count(radius: float) -> int:
	# Roughly one sphere every 80-100 meters of circumference
	return clampi(int(TAU * radius / 90.0), 8, 64)


## Get the list of crater definitions (read-only access for shader parameter setup, etc.)
func get_craters() -> Array[CraterDef]:
	return _craters


## Get the world-space surface center for a crater (for shader/fog volume placement)
func get_crater_surface_center(index: int) -> Vector3:
	if index < 0 or index >= _craters.size():
		return Vector3.ZERO
	return _craters[index].surface_direction * planet_radius
