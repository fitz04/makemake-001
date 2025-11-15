
# Scripts

const StellarBody = preload("./stellar_body.gd")
const Settings = preload("res://settings.gd")
const PlanetAtmosphere = preload("res://addons/zylann.atmosphere/planet_atmosphere.gd")

# Assets 

const VolumetricAtmosphereScene = preload("res://addons/zylann.atmosphere/planet_atmosphere.tscn")
const BigRock1Scene = preload("../props/big_rocks/big_rock1.tscn")
const Rock1Scene = preload("../props/rocks/rock1.tscn")
const GrassScene = preload("res://props/grass/grass.tscn")

const AtmosphereCloudsHighShader = preload(
	"res://addons/zylann.atmosphere/shaders/planet_atmosphere_v1_clouds_high.gdshader")
const AtmosphereCloudsShader = preload(
	"res://addons/zylann.atmosphere/shaders/planet_atmosphere_v1_clouds.gdshader")
const AtmosphereNoCloudsShader = preload(
	"res://addons/zylann.atmosphere/shaders/planet_atmosphere_v1_no_clouds.gdshader")
const AtmosphereScatteredCloudsHighShader = preload(
	"res://addons/zylann.atmosphere/shaders/planet_atmosphere_clouds_high.gdshader")
const AtmosphereScatteredCloudsShader = preload(
	"res://addons/zylann.atmosphere/shaders/planet_atmosphere_clouds.gdshader")
const AtmosphereScatteredNoCloudsShader = preload(
	"res://addons/zylann.atmosphere/shaders/planet_atmosphere_no_clouds.gdshader")

const CloudShapeTexture3D = preload("./atmosphere/noise_texture_3d.res")
const CloudCoverageTextureEarth = preload("./atmosphere/cloud_coverage_earth.tres")
const CloudCoverageTextureMars = preload("./atmosphere/cloud_coverage_mars.tres")
const CloudCoverageTextureGas = preload("./atmosphere/cloud_coverage_gas.tres")

const SunMaterial = preload("./materials/sun_yellow.tres")
const PlanetRockyMaterial = preload("./materials/planet_material_rocky.tres")
const PlanetGrassyMaterial = preload("./materials/planet_material_grassy.tres")
const WaterSeaMaterial = preload("./materials/water_sea_material.tres")
const RockMaterial = preload("res://props/rocks/rock_material.tres")

const Pebble1Mesh = preload("res://props/pebbles/pebble1.obj")
const Rock1Mesh = preload("res://props/rocks/rock1.obj")
const BigRock1Mesh = preload("res://props/big_rocks/big_rock1.obj")

const BasePlanetVoxelGraph = preload("./voxel_graph_planet_v5.tres")

const EarthDaySound = preload("res://sounds/earth_surface_day.ogg")
const EarthNightSound = preload("res://sounds/earth_surface_night.ogg")
const WindSound = preload("res://sounds/wind.ogg")

const SAVE_FOLDER_PATH = "debug_data"

# Scale used when the large world setting is enabled
const LARGE_SCALE = 10.0


static func create_solar_system_data(settings: Settings) -> Array[StellarBody]:
	var bodies : Array[StellarBody] = []

	var sun := StellarBody.new()
	sun.type = StellarBody.TYPE_SUN
	sun.radius = 1500.0
	sun.self_revolution_time = 60.0
	sun.orbit_revolution_time = 60.0
	sun.name = "Sun"
	bodies.append(sun)

	# Makemake - only planet in the system for performance
	var planet := StellarBody.new()
	planet.name = "Makemake"
	planet.type = StellarBody.TYPE_ROCKY
	# Planet radius - automatically synced to voxel terrain via set_node_default_input()
	# This value determines both spawn position AND actual terrain size
	planet.radius = 8000.0  # Change this value to resize the entire planet
	planet.parent_id = 0
	planet.distance_to_parent = 120000.0  # Far outer solar system
	planet.self_revolution_time = 15.0 * 60.0
	planet.orbit_revolution_time = 500.0 * 60.0
	planet.atmosphere_mode = StellarBody.ATMOSPHERE_DISABLED  # No atmosphere
	planet.orbit_revolution_progress = 0.2
	planet.day_ambient_sound = WindSound
	bodies.append(planet)

	var scale := 1.0
	if settings.world_scale_x10:
		scale = LARGE_SCALE

	for body in bodies:
		body.radius *= scale
		var speed := body.distance_to_parent * TAU / body.orbit_revolution_time
		body.distance_to_parent *= scale
		body.orbit_revolution_time = body.distance_to_parent * TAU / speed
	
	return bodies


static func _setup_sun(body: StellarBody, root: Node3D) -> DirectionalLight3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = body.radius
	mesh.height = 2.0 * mesh.radius
	mi.mesh = mesh
	mi.material_override = SunMaterial
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Ignore camera near/far culling for the sun
	mi.ignore_occlusion_culling = true
	mi.extra_cull_margin = 16384.0  # Large margin to prevent culling
	# Ensure sun renders in front when visible
	mi.sorting_offset = 1000.0
	# Force visibility in all rendering scenarios
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end_margin = 0.0
	mi.visibility_range_begin_margin = 0.0

	root.add_child(mi)
	
	var directional_light := DirectionalLight3D.new()
	directional_light.shadow_enabled = true
	# The environment in this game is a space background so it's very dark. Sky is actually a post
	# effect because you can fly out and it's a planet... And still you can also have shadows while
	# in your ship. We workaround this by making shadows not 100% opaque, and by adding a very
	# faint ambient light to the environment
	directional_light.shadow_opacity = 0.99
	directional_light.shadow_normal_bias = 0.2
	directional_light.directional_shadow_split_1 = 0.1
	directional_light.directional_shadow_split_2 = 0.2
	directional_light.directional_shadow_split_3 = 0.5
	directional_light.directional_shadow_blend_splits = true
	directional_light.directional_shadow_max_distance = 20000.0
	directional_light.name = "DirectionalLight"
	body.node.add_child(directional_light)
	
	return directional_light


static func update_atmosphere_settings(body: StellarBody, settings: Settings):
	var atmo : PlanetAtmosphere = body.atmosphere
	
	var has_clouds := (body.clouds_coverage_cubemap != null 
		and settings.clouds_quality != Settings.CLOUDS_DISABLED)

	if has_clouds:
		if body.atmosphere_mode == StellarBody.ATMOSPHERE_WITH_SCATTERING:
			if settings.clouds_quality == Settings.CLOUDS_HIGH:
				atmo.custom_shader = AtmosphereScatteredCloudsHighShader
			else:
				atmo.custom_shader = AtmosphereScatteredCloudsShader
		else:
			if settings.clouds_quality == Settings.CLOUDS_HIGH:
				atmo.custom_shader = AtmosphereCloudsHighShader
			else:
				atmo.custom_shader = AtmosphereCloudsShader
	else:
		if body.atmosphere_mode == StellarBody.ATMOSPHERE_WITH_SCATTERING:
			atmo.custom_shader = AtmosphereScatteredNoCloudsShader
		else:
			atmo.custom_shader = AtmosphereNoCloudsShader
	
	#atmo.scale = Vector3(1, 1, 1) * (0.99 * body.radius)
	if settings.world_scale_x10:
		atmo.planet_radius = body.radius * 1.0
		atmo.atmosphere_height = 125.0 * LARGE_SCALE
	else:
		atmo.planet_radius = body.radius * 1.03
		atmo.atmosphere_height = 0.15 * body.radius

	var atmo_density := 0.001

	if body.atmosphere_mode == StellarBody.ATMOSPHERE_WITH_SCATTERING:
		# Scattered atmosphere settings
		atmo_density = 0.04 if settings.world_scale_x10 else 0.05
		atmo.set_shader_parameter(&"u_atmosphere_modulate", body.atmosphere_color)
		atmo.set_shader_parameter(&"u_scattering_strength", 
			1.0 if settings.world_scale_x10 else 6.0)
		atmo.set_shader_parameter(&"u_atmosphere_ambient_color", body.atmosphere_ambient_color)
	else:
		if body.type == StellarBody.TYPE_GAS:
			if settings.world_scale_x10:
				# TODO Need to investigate this, atmosphere currently blows up HDR when large and dense
				atmo_density /= LARGE_SCALE
		# Settings for the fake color atmospheres
		atmo.set_shader_parameter(&"u_day_color0", body.atmosphere_color)
		atmo.set_shader_parameter(&"u_day_color1", body.atmosphere_color.lerp(Color(1,1,1), 0.5))
		atmo.set_shader_parameter(&"u_night_color0", body.atmosphere_color.darkened(0.8))
		atmo.set_shader_parameter(&"u_night_color1", 
			body.atmosphere_color.darkened(0.8).lerp(Color(1,1,1), 0.0))

	atmo.set_shader_parameter(&"u_density", atmo_density)
#	atmo.set_shader_param("u_attenuation_distance", 50.0)

	if has_clouds:
		atmo.set_shader_parameter(&"u_cloud_density_scale", 
			0.01 if settings.world_scale_x10 else 0.02)
		atmo.set_shader_parameter(&"u_cloud_shape_texture", CloudShapeTexture3D)
		atmo.set_shader_parameter(&"u_cloud_coverage_cubemap", body.clouds_coverage_cubemap)
		atmo.set_shader_parameter(&"u_cloud_shape_factor", 0.4)
		atmo.set_shader_parameter(&"u_cloud_shape_scale", 
			0.001 if settings.world_scale_x10 else 0.005)
		atmo.set_shader_parameter(&"u_cloud_coverage_bias", body.clouds_coverage_bias)
		atmo.set_shader_parameter(&"u_cloud_shape_invert", 1.0)
		atmo.clouds_rotation_speed = 0.05 if settings.world_scale_x10 else 0.5


static func _setup_atmosphere(body: StellarBody, root: Node3D, settings: Settings):
	var atmo : PlanetAtmosphere = VolumetricAtmosphereScene.instantiate()
	body.atmosphere = atmo
	
	# TODO This is kinda bad to hardcode the path, need to find another robust way
	atmo.sun_path = "/root/Main/GameWorld/Sun/DirectionalLight"

	update_atmosphere_settings(body, settings)

	# This is clunky, can't save as .tres, FLAG_BUNDLE_RESOURCES doesn't save anything,
	# and Godot throws lots of errors when inspecting the resulting scene...	
#	var debug_packed_scene := PackedScene.new()
#	var pack_result := debug_packed_scene.pack(atmo)
#	print("Pack: ", pack_result)
#	var debug_packed_scene_fpath := str("debug_dump_atmosphere_", body.name, ".res")
#	var save_result := ResourceSaver.save(debug_packed_scene, 
#		debug_packed_scene_fpath)
#	print("Save ", debug_packed_scene_fpath, ": ", save_result)
	
	root.add_child(atmo)


static func _setup_sea(body: StellarBody, root: Node3D):
	var sea_mesh := SphereMesh.new()
	sea_mesh.radius = body.radius * 0.985
	sea_mesh.height = 2.0 * sea_mesh.radius
	var sea_mesh_instance := MeshInstance3D.new()
	sea_mesh_instance.mesh = sea_mesh
	sea_mesh_instance.material_override = WaterSeaMaterial
	root.add_child(sea_mesh_instance)


static func _setup_rocky_planet(body: StellarBody, root: Node3D, settings: Settings):
	var mat : ShaderMaterial
	# TODO Dont hardcode this
	if body.name == "Earth":
		mat = PlanetGrassyMaterial.duplicate()
	else:
		mat = PlanetRockyMaterial.duplicate()
	mat.set_shader_parameter(&"u_mountain_height", body.radius + 80.0)

	if body.name == "Mars":
		mat.set_shader_parameter(&"u_top_modulate", Color(1.0, 0.6, 0.3))
	elif body.name == "Makemake":
		# Ice dwarf planet - bright grayish-white surface
		mat.set_shader_parameter(&"u_top_modulate", Color(0.9, 0.95, 1.0))

		# Biome system setup
		mat.set_shader_parameter(&"u_planet_radius", body.radius)

		# Landing Basin - spawn area (center of planet)
		mat.set_shader_parameter(&"u_landing_basin_center", Vector3(0, 0, 0))
		mat.set_shader_parameter(&"u_landing_basin_radius", 1200.0)

		# Fire-Ice Basin - FAR SOUTH crater (well separated)
		mat.set_shader_parameter(&"u_fire_ice_center", Vector3(0, 0, -4500))
		mat.set_shader_parameter(&"u_fire_ice_radius", 1800.0)

		# Living Lode Canyon - FAR WEST ravine (well separated)
		mat.set_shader_parameter(&"u_canyon_min_x", -5500.0)
		mat.set_shader_parameter(&"u_canyon_max_x", -3000.0)
		mat.set_shader_parameter(&"u_canyon_min_z", -1500.0)
		mat.set_shader_parameter(&"u_canyon_max_z", 1500.0)

		# Biome colors - Realistic Makemake surface (tholin + methane ice)
		mat.set_shader_parameter(&"u_landing_basin_color", Color(0.95, 0.90, 0.85))  # Bright cream (fresh methane ice)
		mat.set_shader_parameter(&"u_cryo_plains_color", Color(0.85, 0.75, 0.70))    # Light reddish-brown (main surface)
		mat.set_shader_parameter(&"u_ore_highlands_color", Color(0.75, 0.60, 0.50))  # Medium brown (mixed surface)
		mat.set_shader_parameter(&"u_fire_ice_color", Color(0.65, 0.55, 0.50))       # Dark brown (old tholin in crater)
		mat.set_shader_parameter(&"u_canyon_color", Color(0.50, 0.40, 0.35))         # Very dark brown (exposed old surface)
	
	var generator : VoxelGeneratorGraph = BasePlanetVoxelGraph.duplicate(true)

	# Add craters to the terrain - 6 well-spaced craters with varied sizes
	var crater_gen = CraterGenerator.new()
	var craters = []

	# Crater 1: Landing Basin at spawn (largest)
	var crater1 = CraterGenerator.CraterDef.new(
		Vector3(0, 0, 0),
		500.0,   # 500m radius
		100.0,   # 100m deep
		15.0     # 25m rim
	)
	craters.append(crater1)
	print("Crater 0: Landing Basin (0, 0) r=500m")

	# Crater 2: North (large)
	var crater2 = CraterGenerator.CraterDef.new(
		Vector3(0, 0, 2000),
		400.0,   # 400m radius
		80.0,    # 80m deep
		20.0     # 20m rim
	)
	craters.append(crater2)
	print("Crater 1: North (0, 2000) r=400m")

	# Crater 3: South (large)
	var crater3 = CraterGenerator.CraterDef.new(
		Vector3(0, 0, -2000),
		400.0,
		80.0,
		20.0
	)
	craters.append(crater3)
	print("Crater 2: South (0, -2000) r=400m")

	# Crater 4: East (medium)
	var crater4 = CraterGenerator.CraterDef.new(
		Vector3(2000, 0, 0),
		350.0,   # 350m radius
		70.0,    # 70m deep
		18.0     # 18m rim
	)
	craters.append(crater4)
	print("Crater 3: East (2000, 0) r=350m")

	# Crater 5: West (medium)
	var crater5 = CraterGenerator.CraterDef.new(
		Vector3(-2000, 0, 0),
		350.0,
		70.0,
		18.0
	)
	craters.append(crater5)
	print("Crater 4: West (-2000, 0) r=350m")

	# Crater 6: Northeast (smaller)
	var crater6 = CraterGenerator.CraterDef.new(
		Vector3(1400, 0, 1400),
		300.0,   # 300m radius
		60.0,    # 60m deep
		15.0     # 15m rim
	)
	craters.append(crater6)
	print("Crater 5: Northeast (1400, 1400) r=300m")

	crater_gen.add_craters_to_graph(generator, craters)

	# Pass crater data to shader for dust rendering
	var crater_centers = PackedVector3Array()
	var crater_radii = PackedFloat32Array()
	for crater in craters:
		crater_centers.append(crater.center)
		crater_radii.append(crater.radius)

	# Pad arrays to size 10 (shader expects fixed array size)
	while crater_centers.size() < 10:
		crater_centers.append(Vector3.ZERO)
		crater_radii.append(0.0)

	mat.set_shader_parameter("u_crater_count", craters.size())
	mat.set_shader_parameter("u_crater_centers", crater_centers)
	mat.set_shader_parameter("u_crater_radii", crater_radii)

	# Add dust fog volumes to craters
	_add_crater_dust_volumes(body, root, craters)

	var graph : VoxelGraphFunction = generator.get_main_function()
	var sphere_node_id := graph.find_node_by_name("planet_sphere")
	# Set planet sphere radius (input index 3 in Voxel Tools 1.5+)
	# Dynamically syncs terrain size with body.radius value
	graph.set_node_default_input(sphere_node_id, 3, body.radius)

	# Complex terrain setup (restored from backup)
	var ravine_blend_noise_node_id := graph.find_node_by_name("ravine_blend_noise")
	var noise_param_id := 0
	if ravine_blend_noise_node_id != -1:
		var ravine_blend_noise = graph.get_node_param(ravine_blend_noise_node_id, noise_param_id)
		if ravine_blend_noise != null:
			ravine_blend_noise.seed = body.name.hash()

	var cave_height_node_id := graph.find_node_by_name("cave_height_subtract")
	if cave_height_node_id != -1:
		graph.set_node_default_input(cave_height_node_id, 1, body.radius - 100.0)

	var cave_noise_node_id := graph.find_node_by_name("cave_noise")
	if cave_noise_node_id != -1:
		var cave_noise = graph.get_node_param(cave_noise_node_id, noise_param_id)
		if cave_noise != null:
			cave_noise.period = 900.0 / body.radius

	var ravine_depth_multiplier_node_id := graph.find_node_by_name("ravine_depth_multiplier")
	if ravine_depth_multiplier_node_id != -1:
		var ravine_depth_value = graph.get_node_default_input(ravine_depth_multiplier_node_id, 1)
		if ravine_depth_value != null:
			var ravine_depth : float = ravine_depth_value
			if settings.world_scale_x10:
				ravine_depth *= LARGE_SCALE
	# graph.set_node_default_input(ravine_depth_multiplier_node_id, 1, ravine_depth)
	# var cave_height_multiplier_node_id = generator.find_node_by_name("cave_height_multiplier")
	# generator.set_node_default_input(cave_height_multiplier_node_id, 1, 0.015)
	generator.compile()

	generator.use_subdivision = true
	generator.subdivision_size = 8
	#generator.sdf_clip_threshold = 10.0
	generator.use_optimized_execution_map = true

	# ResourceSaver.save(generator, str("debug_data/generator_", body.name, ".tres"),
	# 			ResourceSaver.FLAG_BUNDLE_RESOURCES)

	#var sphere_normalmap = Image.new()
	#sphere_normalmap.create(512, 256, false, Image.FORMAT_RGB8)
	#generator.bake_sphere_normalmap(sphere_normalmap, body.radius * 0.95, 200.0 / body.radius)
	#sphere_normalmap.save_png(str("debug_data/test_sphere_normalmap_", body.name, ".png"))
	#var sphere_normalmap_tex = ImageTexture.create_from_image(sphere_normalmap)
	#mat.set_shader_parameter("u_global_normalmap", sphere_normalmap_tex)

	var stream := VoxelStreamSQLite.new()
	stream.database_path = str(SAVE_FOLDER_PATH, "/", body.name, ".sqlite")

	var extra_lods := 0
	if settings.world_scale_x10:
		var temp := int(LARGE_SCALE)
		while temp > 1:
			extra_lods += 1
			temp /= 2

	var pot := 1024
	while body.radius >= pot:
		pot *= 2

	var volume := VoxelLodTerrain.new()
	volume.lod_count = 7 + extra_lods
	volume.lod_distance = 80.0  # Increased from 60 to reduce LOD transitions
	volume.collision_lod_count = 2
	volume.generator = generator
	volume.stream = stream
	var view_distance := 100000.0
	if settings.world_scale_x10:
		view_distance *= LARGE_SCALE
	volume.view_distance = view_distance
	volume.voxel_bounds = AABB(Vector3(-pot, -pot, -pot), Vector3(2 * pot, 2 * pot, 2 * pot))
	volume.lod_fade_duration = 0.5  # Increased from 0.3 for smoother transitions
	volume.threaded_update_enabled = true
	# Keep all edited blocks loaded. Leaving this off enables data streaming, but it is slower
	volume.full_load_mode_enabled = true

	# Disable normalmap temporarily - causes chunk seams and artifacts with craters
	volume.normalmap_enabled = false
	volume.normalmap_tile_resolution_min = 4
	volume.normalmap_tile_resolution_max = 8
	volume.normalmap_begin_lod_index = 2
	volume.normalmap_max_deviation_degrees = 50
	volume.normalmap_octahedral_encoding_enabled = false
	volume.normalmap_use_gpu = true

	volume.material = mat
	# TODO Set before setting voxel bounds?
	volume.mesh_block_size = 32

	volume.mesher = VoxelMesherTransvoxel.new()
	#volume.mesher.mesh_optimization_enabled = true
	volume.mesher.mesh_optimization_error_threshold = 0.0025
	#volume.set_process_mode(VoxelLodTerrain.PROCESS_MODE_PHYSICS)
	body.volume = volume
	root.add_child(volume)

	_configure_instancing_for_planet(body, volume)


static func _configure_instancing_for_planet(body: StellarBody, volume: VoxelLodTerrain):
	for mesh in [Pebble1Mesh, Rock1Mesh, BigRock1Mesh]:
		mesh.surface_set_material(0, RockMaterial)

	var instancer := VoxelInstancer.new()
	instancer.set_up_mode(VoxelInstancer.UP_MODE_SPHERE)

	var library := VoxelInstanceLibrary.new()
	# Usually most of this is done in editor, but some features can only be setup by code atm.
	# Also if we want to procedurally-generate some of this, we may need code anyways.

	var instance_generator := VoxelInstanceGenerator.new()
	instance_generator.density = 0.015
	instance_generator.min_scale = 0.2
	instance_generator.max_scale = 0.4
	instance_generator.min_slope_degrees = 0
	instance_generator.max_slope_degrees = 40
	#instance_generator.set_layer_min_height(layer_index, body.radius * 0.95)
	instance_generator.random_vertical_flip = true
	instance_generator.vertical_alignment = 0.0
	instance_generator.emit_mode = VoxelInstanceGenerator.EMIT_FROM_FACES
	instance_generator.noise = FastNoiseLite.new()
	instance_generator.noise.frequency = 1.0 / 16.0
	instance_generator.noise.fractal_octaves = 2
	instance_generator.noise_on_scale = 1
	#instance_generator.noise.noise_type = FastNoiseLite.TYPE_PERLIN
	var item := VoxelInstanceLibraryMultiMeshItem.new()
	
	if body.name == "Earth":
		var grass_mesh : Node = GrassScene.instantiate()
		item.setup_from_template(grass_mesh)
		grass_mesh.free()

		#instance_generator.density = 0.32
		instance_generator.density = 2.0
		instance_generator.min_scale = 0.8
		instance_generator.max_scale = 1.6
		instance_generator.random_vertical_flip = false
		instance_generator.max_slope_degrees = 30

		item.name = "grass"
		
	else:
		item.set_mesh(Pebble1Mesh, 0)
		item.name = "pebbles"

	item.generator = instance_generator
	item.persistent = false
	item.lod_index = 0
	library.add_item(2, item)

	instance_generator = VoxelInstanceGenerator.new()
	instance_generator.density = 0.02
	instance_generator.min_scale = 0.5
	instance_generator.max_scale = 0.8
	instance_generator.min_slope_degrees = 0
	instance_generator.max_slope_degrees = 12
	instance_generator.vertical_alignment = 0.0
	item = VoxelInstanceLibraryMultiMeshItem.new()
	var rock1_template : Node = Rock1Scene.instantiate()
	item.setup_from_template(rock1_template)
	rock1_template.free()
	item.generator = instance_generator
	item.persistent = true
	item.lod_index = 2
	item.name = "rock"
	library.add_item(0, item)

	instance_generator = VoxelInstanceGenerator.new()
	instance_generator.density = 0.01
	instance_generator.min_scale = 0.6
	instance_generator.max_scale = 1.2
	instance_generator.min_slope_degrees = 0
	instance_generator.max_slope_degrees = 10
	instance_generator.vertical_alignment = 0.0
	item = VoxelInstanceLibraryMultiMeshItem.new()
	item.set_mesh(BigRock1Mesh, 0)
	item.generator = instance_generator
	item.persistent = true
	item.lod_index = 3
	item.name = "big_rock"
	library.add_item(1, item)

	instance_generator = VoxelInstanceGenerator.new()
	instance_generator.noise = FastNoiseLite.new()
	instance_generator.noise.frequency = 1.0 / 16.0
	instance_generator.noise.fractal_octaves = 2
	instance_generator.noise_on_scale = 1
	instance_generator.density = 0.02
	instance_generator.min_scale = 0.6
	instance_generator.max_scale = 3.0
	instance_generator.scale_distribution = VoxelInstanceGenerator.DISTRIBUTION_CUBIC
	instance_generator.min_slope_degrees = 140
	instance_generator.max_slope_degrees = 180
	instance_generator.vertical_alignment = 1.0
	instance_generator.offset_along_normal = -0.5
	item = VoxelInstanceLibraryMultiMeshItem.new()
	var cone := CylinderMesh.new()
	cone.radial_segments = 8
	cone.rings = 0
	cone.top_radius = 0.5
	cone.bottom_radius = 0.1
	cone.height = 2.5
	cone.material = RockMaterial
	item.set_mesh(cone, 0)
	item.generator = instance_generator
	item.persistent = true
	item.lod_index = 0
	item.name = "stalactite"
	library.add_item(3, item)

	instancer.library = library

	volume.add_child(instancer)
	body.instancer = instancer


static func setup_stellar_body(body: StellarBody, parent: Node, 
	settings: Settings) -> DirectionalLight3D:
	
	var root := Node3D.new()
	root.name = body.name
	body.node = root
	parent.add_child(root)
	
	var sun_light : DirectionalLight3D = null

	if body.type == StellarBody.TYPE_SUN:
		sun_light = _setup_sun(body, root)
	
	elif body.type == StellarBody.TYPE_ROCKY:
		_setup_rocky_planet(body, root, settings)

	if body.sea:
		_setup_sea(body, root)
	
	if body.atmosphere_mode != StellarBody.ATMOSPHERE_DISABLED:
		_setup_atmosphere(body, root, settings)
	
	return sun_light


## Add dust fog volumes to crater areas for atmospheric effect
static func _add_crater_dust_volumes(body: StellarBody, root: Node3D, craters: Array) -> void:
	print("Adding dust fog volumes to ", craters.size(), " craters")

	for i in range(craters.size()):
		var crater = craters[i]

		# Create FogVolume node
		var fog_volume = FogVolume.new()
		fog_volume.name = "CraterDust_%d" % i

		# Size: cover crater area with some height (FogVolume is always box-shaped in Godot 4)
		var box_size = Vector3(
			crater.radius * 2.2,  # Wider than crater
			60.0,                 # 60m tall dust cloud
			crater.radius * 2.2
		)
		fog_volume.size = box_size

		# Create FogMaterial with dust properties
		var fog_material = FogMaterial.new()
		fog_material.density = 0.15  # Subtle - not too thick
		fog_material.albedo = Color(0.75, 0.70, 0.60)  # Match crater dust color
		fog_material.emission = Color(0.05, 0.05, 0.05)  # Very subtle glow
		fog_volume.material = fog_material

		# Position: crater center + height offset (fog floats above ground)
		var world_pos = crater.center + Vector3(0, body.radius + 30, 0)  # 30m above surface
		fog_volume.position = world_pos

		# Add to planet's root node
		root.add_child(fog_volume)

		print("  Added dust volume at ", crater.center, " (world: ", world_pos, ")")
