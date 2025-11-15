extends Node

## Test script for crater generation system
## Attach this to a Node in your scene and run to test crater generation

@export var voxel_terrain: VoxelTerrain
@export var test_immediately: bool = true

func _ready():
	if test_immediately:
		test_crater_generation()


func test_crater_generation():
	print("\n=== Testing Crater Generation System ===\n")

	# Load the new clean graph
	var graph = load("res://solar_system/voxel_graph_planet_v5.tres") as VoxelGeneratorGraph
	if graph == null:
		push_error("Failed to load voxel_graph_planet_v5.tres")
		return

	print("✓ Loaded base terrain graph")

	# Create crater generator
	var crater_gen = CraterGenerator.new()
	print("✓ Created CraterGenerator")

	# Define test craters
	var craters = []

	# Landing Basin - spawn point
	var landing_basin = CraterGenerator.CraterDef.new(
		Vector3(0, 0, 0),     # Center at origin
		1200.0,               # 1.2km radius
		250.0,                # 250m deep
		45.0                  # 45m rim height
	)
	craters.append(landing_basin)
	print("  Added Landing Basin crater (0, 0, 0)")

	# North crater
	var north_crater = CraterGenerator.CraterDef.new(
		Vector3(0, 0, 3500),
		800.0,
		180.0,
		30.0
	)
	craters.append(north_crater)
	print("  Added North crater (0, 0, 3500)")

	# South-West crater
	var sw_crater = CraterGenerator.CraterDef.new(
		Vector3(-2500, 0, -1500),
		600.0,
		150.0,
		25.0
	)
	craters.append(sw_crater)
	print("  Added South-West crater (-2500, 0, -1500)")

	# East small crater
	var east_crater = CraterGenerator.CraterDef.new(
		Vector3(3000, 0, 500),
		400.0,
		100.0,
		20.0
	)
	craters.append(east_crater)
	print("  Added East crater (3000, 0, 500)")

	# Generate craters in graph
	print("\nGenerating crater nodes...")
	crater_gen.add_craters_to_graph(graph, craters)
	print("✓ Successfully generated ", craters.size(), " craters")

	# Apply to VoxelTerrain if provided
	if voxel_terrain:
		voxel_terrain.generator = graph
		print("✓ Applied to VoxelTerrain")
		print("\n=== Test Complete! ===")
		print("Check the terrain - you should see 4 craters:")
		print("  1. Landing Basin at spawn (0,0)")
		print("  2. Large crater to the North")
		print("  3. Medium crater to the South-West")
		print("  4. Small crater to the East")
	else:
		push_warning("VoxelTerrain not assigned - graph generated but not applied")
		print("\n=== Graph Generated ===")
		print("Assign a VoxelTerrain node to test_immediately to see results")


## Example: Generate random craters
func test_random_craters(count: int = 10):
	var graph = load("res://solar_system/voxel_graph_planet_v5.tres") as VoxelGeneratorGraph
	var crater_gen = CraterGenerator.new()

	var craters = []
	var planet_radius = 7000.0  # Slightly less than sphere radius

	for i in range(count):
		# Random position on planet surface (2D projection)
		var angle = randf() * TAU
		var distance = randf() * planet_radius

		var pos = Vector3(
			cos(angle) * distance,
			0,
			sin(angle) * distance
		)

		# Random size
		var radius = randf_range(200, 1000)
		var depth = radius * randf_range(0.2, 0.3)
		var rim_height = radius * randf_range(0.03, 0.06)

		var crater = CraterGenerator.CraterDef.new(pos, radius, depth, rim_height)
		craters.append(crater)

		print("Random crater ", i, ": pos=", pos, " radius=", radius)

	crater_gen.add_craters_to_graph(graph, craters)

	if voxel_terrain:
		voxel_terrain.generator = graph
		print("Generated ", count, " random craters")


## Example: Generate craters in a specific region
func test_regional_craters():
	var graph = load("res://solar_system/voxel_graph_planet_v5.tres") as VoxelGeneratorGraph
	var crater_gen = CraterGenerator.new()

	var craters = []

	# "Ancient Impact Zone" - cluster of old craters in the south
	var impact_zone_center = Vector3(0, 0, -4000)
	var impact_zone_radius = 2000.0

	for i in range(15):
		var angle = randf() * TAU
		var distance = randf() * impact_zone_radius

		var pos = impact_zone_center + Vector3(
			cos(angle) * distance,
			0,
			sin(angle) * distance
		)

		# Old, eroded craters - shallower and wider
		var radius = randf_range(300, 800)
		var depth = radius * 0.15  # Shallow (eroded)
		var rim_height = radius * 0.02  # Low rim (eroded)

		var crater = CraterGenerator.CraterDef.new(pos, radius, depth, rim_height)
		crater.bowl_flat_radius = radius * 0.7  # Wide flat bottom
		craters.append(crater)

	crater_gen.add_craters_to_graph(graph, craters)

	if voxel_terrain:
		voxel_terrain.generator = graph
		print("Generated ancient impact zone with ", craters.size(), " old craters")


## Call this from inspector or code to test different configurations
func regenerate_with_config(
	major_crater_count: int = 3,
	medium_crater_count: int = 10,
	small_crater_count: int = 20
):
	print("\n=== Regenerating with custom config ===")
	print("Major: ", major_crater_count, ", Medium: ", medium_crater_count, ", Small: ", small_crater_count)

	var graph = load("res://solar_system/voxel_graph_planet_v5.tres") as VoxelGeneratorGraph
	var crater_gen = CraterGenerator.new()
	var all_craters = []

	# Major craters (landmarks)
	all_craters.append_array(_generate_sized_craters(major_crater_count, 1000, 2000))
	# Medium craters
	all_craters.append_array(_generate_sized_craters(medium_crater_count, 400, 1000))
	# Small craters
	all_craters.append_array(_generate_sized_craters(small_crater_count, 100, 400))

	crater_gen.add_craters_to_graph(graph, all_craters)

	if voxel_terrain:
		voxel_terrain.generator = graph
		print("✓ Generated total of ", all_craters.size(), " craters")


func _generate_sized_craters(count: int, min_radius: float, max_radius: float) -> Array:
	var craters = []
	var planet_radius = 7000.0

	for i in range(count):
		var angle = randf() * TAU
		var distance = randf() * planet_radius

		var pos = Vector3(
			cos(angle) * distance,
			0,
			sin(angle) * distance
		)

		var radius = randf_range(min_radius, max_radius)
		var depth = radius * randf_range(0.2, 0.3)
		var rim_height = radius * randf_range(0.03, 0.06)

		craters.append(CraterGenerator.CraterDef.new(pos, radius, depth, rim_height))

	return craters
