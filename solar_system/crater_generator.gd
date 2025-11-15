extends Node
class_name CraterGenerator

## Crater Generator Utility
##
## This utility helps generate multiple craters on a VoxelGeneratorGraph terrain.
## Each crater consists of:
## - Distance calculation nodes (calculating distance from crater center)
## - Bowl nodes (the depression/hole)
## - Rim nodes (the raised edge around the crater)
##
## Usage:
##   var generator = CraterGenerator.new()
##   var craters = [
##       {"center": Vector3(0, 0, 0), "radius": 1200, "depth": 250, "rim_height": 45},
##       {"center": Vector3(3000, 0, 2000), "radius": 800, "depth": 180, "rim_height": 30}
##   ]
##   generator.add_craters_to_graph(graph, craters)

## Crater definition structure
class CraterDef:
	var center: Vector3  # Center position (X, Y=0, Z)
	var radius: float    # Outer radius where crater effect ends
	var depth: float     # Depth of crater bowl (negative value)
	var rim_height: float  # Height of rim uplift

	# Optional parameters for fine-tuning
	var bowl_flat_radius: float  # Radius of flat bottom (default: radius * 0.5)
	var rim_start_radius: float  # Where rim starts rising (default: radius * 0.92)
	var rim_end_radius: float    # Where rim ends (default: radius * 1.03)

	func _init(p_center: Vector3, p_radius: float, p_depth: float, p_rim_height: float):
		center = p_center
		radius = p_radius
		depth = p_depth
		rim_height = p_rim_height

		# Set defaults
		bowl_flat_radius = p_radius * 0.5
		rim_start_radius = p_radius * 0.92  # Sharper rim - starts closer to edge
		rim_end_radius = p_radius * 1.03    # Sharper rim - narrower peak


## Add multiple craters to a voxel graph
## @param generator: VoxelGeneratorGraph to modify
## @param crater_defs: Array of CraterDef objects
## @param terrain_output_node_id: The node ID that currently goes to OutputSDF (default: auto-detect)
func add_craters_to_graph(generator: VoxelGeneratorGraph, crater_defs: Array, terrain_output_node_id: int = -1) -> void:
	if crater_defs.is_empty():
		push_warning("CraterGenerator: No craters to add")
		return

	# Get the graph function
	var graph : VoxelGraphFunction = generator.get_main_function()

	# Find input coordinate nodes by ID (they should always be nodes 2, 3, 4 in our setup)
	var input_x_id = 2
	var input_z_id = 4

	# Find the terrain base node (currently connected to OutputSDF)
	if terrain_output_node_id == -1:
		terrain_output_node_id = 9  # planet_sphere node from v5.tres (simplified)

	# Find OutputSDF node (should always be node 10 in our setup)
	var output_sdf_id = 10

	# Start node ID from a high number to avoid conflicts
	var next_node_id = _get_max_node_id(graph) + 1
	var gui_y_offset = 800  # Start craters below main terrain

	print("CraterGenerator: Adding ", crater_defs.size(), " craters starting from node ID ", next_node_id)

	# Generate all crater node chains
	var crater_outputs = []  # Array of {bowl_id, rim_id}

	for i in range(crater_defs.size()):
		var crater = crater_defs[i]
		var gui_x_start = -200
		var gui_y = gui_y_offset + (i * 300)

		print("  Crater ", i, ": center=", crater.center, " radius=", crater.radius)

		# Create crater node chain
		var crater_nodes = _create_crater_nodes(
			graph, next_node_id, crater,
			input_x_id, input_z_id,
			Vector2(gui_x_start, gui_y)
		)

		crater_outputs.append(crater_nodes)
		next_node_id = crater_nodes.last_node_id + 1

	# Combine all craters with the base terrain
	var combined_id = _combine_craters_with_terrain(
		graph, next_node_id, terrain_output_node_id,
		crater_outputs, Vector2(1200, 400)
	)

	# Disconnect old terrain->OutputSDF connection and connect new combined output
	_disconnect_node_input(graph, output_sdf_id, 0)
	graph.add_connection(combined_id, 0, output_sdf_id, 0)

	print("CraterGenerator: Successfully added ", crater_defs.size(), " craters")


## Create all nodes for a single crater
## Returns: {bowl_id: int, rim_id: int, last_node_id: int}
func _create_crater_nodes(
	graph: VoxelGraphFunction,
	start_node_id: int,
	crater: CraterDef,
	input_x_id: int,
	input_z_id: int,
	gui_pos: Vector2
) -> Dictionary:

	var node_id = start_node_id
	var x = gui_pos.x
	var y = gui_pos.y

	# Node IDs for this crater
	var x_center_const_id = node_id
	var z_center_const_id = node_id + 1
	var x_offset_id = node_id + 2
	var z_offset_id = node_id + 3
	var x_squared_id = node_id + 4
	var z_squared_id = node_id + 5
	var dist_squared_id = node_id + 6
	var distance_id = node_id + 7
	var bowl_falloff_id = node_id + 8
	var bowl_depth_id = node_id + 9
	var rim_falloff_id = node_id + 10
	var rim_height_id = node_id + 11

	# X center constant
	x_center_const_id = graph.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2(x - 100, y - 60), x_center_const_id)
	graph.set_node_param(x_center_const_id, 0, crater.center.x)
	graph.set_node_name(x_center_const_id, "crater_%d_x_center" % start_node_id)

	# X offset from crater center (InputX - center.x)
	x_offset_id = graph.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(x, y), x_offset_id)
	graph.set_node_name(x_offset_id, "crater_%d_x_offset" % start_node_id)
	graph.add_connection(input_x_id, 0, x_offset_id, 0)
	graph.add_connection(x_center_const_id, 0, x_offset_id, 1)

	# Z center constant
	z_center_const_id = graph.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2(x - 100, y + 60), z_center_const_id)
	graph.set_node_param(z_center_const_id, 0, crater.center.z)
	graph.set_node_name(z_center_const_id, "crater_%d_z_center" % start_node_id)

	# Z offset from crater center (InputZ - center.z)
	z_offset_id = graph.create_node(VoxelGraphFunction.NODE_SUBTRACT, Vector2(x, y + 120), z_offset_id)
	graph.set_node_name(z_offset_id, "crater_%d_z_offset" % start_node_id)
	graph.add_connection(input_z_id, 0, z_offset_id, 0)
	graph.add_connection(z_center_const_id, 0, z_offset_id, 1)

	# X squared
	x_squared_id = graph.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(x + 200, y - 60), x_squared_id)
	graph.set_node_name(x_squared_id, "crater_%d_x_squared" % start_node_id)
	graph.add_connection(x_offset_id, 0, x_squared_id, 0)
	graph.add_connection(x_offset_id, 0, x_squared_id, 1)

	# Z squared
	z_squared_id = graph.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(x + 200, y + 120), z_squared_id)
	graph.set_node_name(z_squared_id, "crater_%d_z_squared" % start_node_id)
	graph.add_connection(z_offset_id, 0, z_squared_id, 0)
	graph.add_connection(z_offset_id, 0, z_squared_id, 1)

	# Distance squared (x² + z²)
	dist_squared_id = graph.create_node(VoxelGraphFunction.NODE_ADD, Vector2(x + 400, y), dist_squared_id)
	graph.set_node_name(dist_squared_id, "crater_%d_dist_squared" % start_node_id)
	graph.add_connection(x_squared_id, 0, dist_squared_id, 0)
	graph.add_connection(z_squared_id, 0, dist_squared_id, 1)

	# Distance (sqrt)
	distance_id = graph.create_node(VoxelGraphFunction.NODE_SQRT, Vector2(x + 600, y), distance_id)
	graph.set_node_name(distance_id, "crater_%d_distance" % start_node_id)
	graph.add_connection(dist_squared_id, 0, distance_id, 0)

	# Bowl falloff (smoothstep from flat bottom to edge)
	# SWAPPED: param order reversed - testing if Godot Voxel uses opposite convention
	bowl_falloff_id = graph.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(x + 800, y - 60), bowl_falloff_id)
	graph.set_node_param(bowl_falloff_id, 0, crater.radius)  # SWAPPED: was bowl_flat_radius
	graph.set_node_param(bowl_falloff_id, 1, crater.bowl_flat_radius)  # SWAPPED: was radius
	graph.set_node_name(bowl_falloff_id, "crater_%d_bowl_falloff" % start_node_id)
	graph.add_connection(distance_id, 0, bowl_falloff_id, 0)

	# Bowl depth constant
	var bowl_depth_const_id = node_id + 12
	bowl_depth_const_id = graph.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2(x + 900, y - 100), bowl_depth_const_id)
	graph.set_node_param(bowl_depth_const_id, 0, crater.depth)  # FIXED: Positive for depression (SDF subtract)
	graph.set_node_name(bowl_depth_const_id, "crater_%d_bowl_depth_const" % start_node_id)

	# Bowl depth (multiply by depth)
	bowl_depth_id = graph.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(x + 1000, y - 60), bowl_depth_id)
	graph.set_node_name(bowl_depth_id, "crater_%d_bowl_depth" % start_node_id)
	graph.add_connection(bowl_falloff_id, 0, bowl_depth_id, 0)
	graph.add_connection(bowl_depth_const_id, 0, bowl_depth_id, 1)

	# Rim falloff (smoothstep for raised edge)
	# SWAPPED: param order reversed - testing if Godot Voxel uses opposite convention
	rim_falloff_id = graph.create_node(VoxelGraphFunction.NODE_SMOOTHSTEP, Vector2(x + 800, y + 120), rim_falloff_id)
	graph.set_node_param(rim_falloff_id, 0, crater.rim_end_radius)  # SWAPPED: was rim_start_radius
	graph.set_node_param(rim_falloff_id, 1, crater.rim_start_radius)  # SWAPPED: was rim_end_radius
	graph.set_node_name(rim_falloff_id, "crater_%d_rim_falloff" % start_node_id)
	graph.add_connection(distance_id, 0, rim_falloff_id, 0)

	# Rim height constant
	var rim_height_const_id = node_id + 13
	rim_height_const_id = graph.create_node(VoxelGraphFunction.NODE_CONSTANT, Vector2(x + 900, y + 160), rim_height_const_id)
	graph.set_node_param(rim_height_const_id, 0, -crater.rim_height)  # NEGATIVE for uplift (rim rises up)
	graph.set_node_name(rim_height_const_id, "crater_%d_rim_height_const" % start_node_id)

	# Rim height (multiply by height)
	rim_height_id = graph.create_node(VoxelGraphFunction.NODE_MULTIPLY, Vector2(x + 1000, y + 120), rim_height_id)
	graph.set_node_name(rim_height_id, "crater_%d_rim_height" % start_node_id)
	graph.add_connection(rim_falloff_id, 0, rim_height_id, 0)
	graph.add_connection(rim_height_const_id, 0, rim_height_id, 1)

	return {
		"bowl_id": bowl_depth_id,
		"rim_id": rim_height_id,
		"last_node_id": rim_height_const_id
	}


## Combine all crater outputs with base terrain
func _combine_craters_with_terrain(
	graph: VoxelGraphFunction,
	start_node_id: int,
	terrain_id: int,
	crater_outputs: Array,
	gui_pos: Vector2
) -> int:

	var node_id = start_node_id
	var current_terrain = terrain_id

	# Add each crater's bowl and rim to the terrain
	for i in range(crater_outputs.size()):
		var crater = crater_outputs[i]
		var y_offset = i * 100

		# Add bowl (depression)
		var bowl_combined_id = node_id
		bowl_combined_id = graph.create_node(VoxelGraphFunction.NODE_ADD, Vector2(gui_pos.x, gui_pos.y + y_offset), bowl_combined_id)
		graph.set_node_name(bowl_combined_id, "combined_crater_%d_bowl" % i)
		graph.add_connection(current_terrain, 0, bowl_combined_id, 0)
		graph.add_connection(crater.bowl_id, 0, bowl_combined_id, 1)
		node_id += 1

		# Add rim (uplift)
		var rim_combined_id = node_id
		rim_combined_id = graph.create_node(VoxelGraphFunction.NODE_ADD, Vector2(gui_pos.x + 200, gui_pos.y + y_offset), rim_combined_id)
		graph.set_node_name(rim_combined_id, "combined_crater_%d_rim" % i)
		graph.add_connection(bowl_combined_id, 0, rim_combined_id, 0)
		graph.add_connection(crater.rim_id, 0, rim_combined_id, 1)
		node_id += 1

		current_terrain = rim_combined_id

	return current_terrain


## Helper: Get maximum node ID currently in graph
func _get_max_node_id(graph: VoxelGraphFunction) -> int:
	var node_ids = graph.get_node_ids()
	var max_id = 0
	for node_id in node_ids:
		if node_id > max_id:
			max_id = node_id
	return max_id


## Helper: Disconnect a specific input port on a node
func _disconnect_node_input(graph: VoxelGraphFunction, node_id: int, input_port: int) -> void:
	var connections = graph.get_connections()
	for conn in connections:
		if conn.dst_node_id == node_id and conn.dst_port_index == input_port:
			graph.remove_connection(conn.src_node_id, conn.src_port_index, conn.dst_node_id, conn.dst_port_index)
			return
