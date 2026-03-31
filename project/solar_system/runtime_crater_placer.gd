extends Node
class_name RuntimeCraterPlacer

## Runtime Crater Placer
##
## Attaches to a player or camera to allow placing craters at runtime.
## Usage: Add this node to your scene, preferably as a child of the player or camera.
## Press 'C' (default) to place a crater in front of you.

@export var trigger_action: String = "ui_accept" # Default to space/enter if no custom action
@export var crater_radius: float = 200.0
@export var crater_depth: float = 50.0
@export var place_distance: float = 500.0 # Distance in front of player
@export var voxel_terrain_path: NodePath = "../../../Makemake/VoxelLodTerrain" # Adjust based on scene tree

var _terrain: VoxelLodTerrain

func _ready():
	# Try to find terrain if path is valid
	if has_node(voxel_terrain_path):
		_terrain = get_node(voxel_terrain_path)
	else:
		# Fallback search
		var root = get_tree().root
		_terrain = _find_voxel_terrain(root)
		
	if _terrain:
		print("RuntimeCraterPlacer: Found terrain at ", _terrain.get_path())
	else:
		push_warning("RuntimeCraterPlacer: Could not find VoxelLodTerrain")


func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C: # Hardcoded for testing
			_place_crater()


func _place_crater():
	if not _terrain:
		push_error("RuntimeCraterPlacer: No terrain found")
		return

	var camera = get_viewport().get_camera_3d()
	if not camera:
		return

	# Calculate position in front of camera
	var forward = -camera.global_transform.basis.z
	var center_pos = camera.global_transform.origin + (forward * place_distance)
	
	# Project to planet surface (assuming planet center is 0,0,0 or close)
	# For Makemake, we might need to adjust if it's not at 0,0,0
	# But the graph expects local coordinates relative to the planet center usually
	# if the generator is local.
	
	# However, the VoxelGeneratorGraph usually works in local space of the VoxelLodTerrain.
	# So we need to convert world pos to local pos.
	var local_pos = _terrain.to_local(center_pos)
	
	# We only care about X and Z for the crater generator (2D projection on sphere)
	# But wait, the current crater generator implementation uses X/Z plane logic!
	# It assumes a flat plane or a specific projection.
	# The existing craters are at (0,0,0), (0,0,2000), etc.
	# This implies the graph is using a planar projection or the planet is huge and we are treating it as flat locally?
	# Let's look at the graph... it uses InputX and InputZ.
	# If it's a planet, usually it uses InputX, InputY, InputZ and converts to spherical?
	# Or maybe the "planet" is actually just using a heightmap on a sphere?
	
	# Re-reading CRATER_IMPLEMENTATION.md:
	# "크레이터는 XZ 평면(수평면)에서 중심점 (0, 0, -4500)으로부터의 2D 거리를 계산합니다"
	# This suggests the crater logic is indeed 2D XZ based.
	# This works well for a flat world, but for a sphere, it might be weird if not using 3D distance.
	# BUT, if the graph is for a planet, usually there's a "Planet" node or similar that maps 3D to 2D heightmap?
	# Or maybe it's just adding to the SDF based on 3D distance?
	
	# Let's check crater_generator.gd again.
	# It uses InputX (2) and InputZ (4).
	# And it calculates distance = sqrt(x^2 + z^2).
	# This is definitely 2D distance.
	# On a sphere, this would create a cylinder of craters through the planet along the Y axis!
	# Unless... the inputs X and Z are not raw coordinates but UVs?
	# No, VoxelGeneratorGraph inputs 2,3,4 are usually X,Y,Z.
	
	# Wait, if it's a planet, `InputX` and `InputZ` are world coordinates (or local to volume).
	# If we use 2D distance on a sphere, we get a cylinder.
	# The craters will appear on both top and bottom of the planet, and stretch vertically?
	# UNLESS the planet logic handles this.
	
	# Let's assume for now we just want to place it at (x, z) of the target position.
	
	var crater_def = CraterGenerator.CraterDef.new(
		Vector3(local_pos.x, 0, local_pos.z), # Y is ignored in generator logic
		crater_radius,
		crater_depth,
		crater_depth * 0.2 # Rim height
	)
	
	print("RuntimeCraterPlacer: Placing crater at ", crater_def.center)
	
	var generator = _terrain.generator
	if generator is VoxelGeneratorGraph:
		var crater_gen = CraterGenerator.new()
		crater_gen.add_craters_to_graph(generator, [crater_def])
		crater_gen.apply_changes(generator, _terrain)
		print("RuntimeCraterPlacer: Crater placed!")
	else:
		push_error("RuntimeCraterPlacer: Terrain generator is not a VoxelGeneratorGraph")


func _find_voxel_terrain(node: Node) -> VoxelLodTerrain:
	if node is VoxelLodTerrain:
		return node
	for child in node.get_children():
		var result = _find_voxel_terrain(child)
		if result:
			return result
	return null
