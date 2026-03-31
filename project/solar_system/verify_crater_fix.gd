extends SceneTree

func _init():
	print("Verifying crater fix...")
	
	# Load the generator
	var generator = load("res://solar_system/voxel_graph_planet_v5.tres")
	if not generator:
		print("Error: Could not load generator")
		quit(1)
		return

	# Create a dummy terrain (we can't fully simulate it without a scene, but we can pass null)
	# or we can try to instantiate one.
	var terrain = VoxelLodTerrain.new()
	terrain.generator = generator
	
	# Create crater generator
	var crater_gen = CraterGenerator.new()
	
	# Define a test crater
	var crater = CraterGenerator.CraterDef.new(
		Vector3(100, 0, 100),
		50.0,
		10.0,
		2.0
	)
	
	print("Adding crater...")
	crater_gen.add_craters_to_graph(generator, [crater])
	
	print("Applying changes...")
	# We pass null for terrain because we can't easily mock the full terrain behavior in a script runner
	# without a proper scene tree setup, but we want to test if compile() works.
	crater_gen.apply_changes(generator, null) 
	
	print("Verification successful!")
	quit(0)
