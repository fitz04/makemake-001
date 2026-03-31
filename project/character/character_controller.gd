extends Node

const StellarBody = preload("../solar_system/stellar_body.gd")
const Ship = preload("../ship/ship.gd")
const Util = preload("../util/util.gd")
const CollisionLayers = preload("../collision_layers.gd")
const SolarSystem = preload("../solar_system/solar_system.gd")
# TODO This is very close to Godot's CharacterBody3D. Introduce prefixes?
# It could be confusing to not realize this is actually from the project and not Godot
const CharacterBody = preload("res://addons/zylann.3d_basics/character/character.gd")
const SplitChunkRigidBodyComponent = preload("../solar_system/split_chunk_rigidbody_component.gd")
const CharacterAudio = preload("./character_audio.gd")
const Waypoint = preload("res://waypoints/waypoint.gd")
const HeightmapItem = preload("../solar_system/heightmap_item.gd")
const Settings = preload("res://settings.gd")
const RuntimeCraterPlacer = preload("../solar_system/runtime_crater_placer.gd")

const WaypointScene = preload("../waypoints/waypoint.tscn")

const VERTICAL_CORRECTION_SPEED = PI
const MOVE_ACCELERATION = 80.0
const MOVE_DAMP_FACTOR = 0.1
const JUMP_COOLDOWN_TIME = 0.3
const JUMP_SPEED = 8.0

@onready var _head : Node3D = get_node("../Head")
@onready var _visual_root : Node3D = get_node("../Visual")
@onready var _visual_head : Node3D = get_node("../Visual/Head")
@onready var _flashlight : SpotLight3D = get_node("../Visual/FlashLight")
@onready var _audio : CharacterAudio = get_node("../Audio")

var _velocity := Vector3()
var _dig_cmd := false
var _interact_cmd := false
var _build_cmd := false
var _waypoint_cmd := false
var _last_motor := Vector3()

# Heightmap system
var _heightmaps: Array[HeightmapItem] = []
var _current_heightmap_idx: int = 0
var _use_heightmaps: bool = true  # Toggle between sphere and heightmap mode
var _preview_data: Array = []  # Preview spheres for current raycast
var _last_hit_position: Vector3 = Vector3.ZERO  # Last raycast hit position
var _last_hit_normal: Vector3 = Vector3.ZERO  # Last raycast hit normal
var _preview_update_timer: float = 0.0  # Timer for throttling preview updates
var _last_preview_heightmap_idx: int = -1  # Track which heightmap was last previewed

var _crater_placer : RuntimeCraterPlacer

func _ready():
	_load_heightmaps()
	
	# Initialize runtime crater placer
	_crater_placer = RuntimeCraterPlacer.new()
	add_child(_crater_placer)
	print("Character: RuntimeCraterPlacer attached")



func _physics_process(delta):
	var motor := Vector3()

	if Input.is_key_pressed(KEY_W):
		motor += Vector3(0, 0, -1)
	if Input.is_key_pressed(KEY_S):
		motor += Vector3(0, 0, 1)
	if Input.is_key_pressed(KEY_A):
		motor += Vector3(-1, 0, 0)
	if Input.is_key_pressed(KEY_D):
		motor += Vector3(1, 0, 0)

	var character_body := _get_body()
	character_body.set_motor(motor)

	var planet_center := Vector3()
	var gtrans := character_body.global_transform
	var planet_up := (gtrans.origin - planet_center).normalized()
	character_body.set_planet_up(planet_up)

	_process_actions()
	_process_undig()

	# Update preview timer
	_preview_update_timer += delta
	_visualize_heightmap_area()

	_last_motor = motor

  
func _process_undig():
	var solar_system := _get_solar_system()
	if solar_system == null:
		# In testing scene?
		return
	var ref_body := solar_system.get_reference_stellar_body()
	if ref_body == null or ref_body.volume == null:
		# Planet not yet loaded or no voxel terrain
		return
	var volume := ref_body.volume
	var vt : VoxelToolLodTerrain = volume.get_voxel_tool()
	var to_local := volume.global_transform.affine_inverse()
	var character_body := _get_body()
	var local_pos := to_local * character_body.global_transform.origin
	vt.channel = VoxelBuffer.CHANNEL_SDF
	var sdf := vt.get_voxel_f_interpolated(local_pos)
	DDD.set_text("SDF at feet", sdf)
	if sdf < -0.001:
		# We got buried, teleport at nearest safe location
		print("Character is buried, teleporting back to air")
		var up := local_pos.normalized()
		var offset_local_pos := local_pos
		for i in 10:
			print("Undig attempt ", i)
			offset_local_pos += 0.2 * up
			sdf = vt.get_voxel_f_interpolated(offset_local_pos)
			if sdf > 0.0005:
				break
		var gtrans := character_body.global_transform
		gtrans.origin = volume.get_global_transform() * offset_local_pos
		character_body.global_transform = gtrans


func _process_actions():
	if _interact_cmd:
		_interact_cmd = false
		_interact()

	var character_body := _get_body()
	
	var camera := get_viewport().get_camera_3d()
	var front := -camera.global_transform.basis.z
	var cam_pos := camera.global_transform.origin
	var space_state := character_body.get_world_3d().direct_space_state
	
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = cam_pos
	ray_query.to = cam_pos + front * 50.0
	ray_query.exclude = [character_body.get_rid()]
	var hit = space_state.intersect_ray(ray_query)

	if not hit.is_empty():
		if hit.collider is VoxelLodTerrain:
			DDD.draw_box(hit.position, Vector3(0.5,0.5,0.5), Color(1,1,0))

	if not hit.is_empty():
		if hit.collider is VoxelLodTerrain:
			var volume : VoxelLodTerrain = hit.collider
			var hit_position : Vector3 = hit.position

			# Calculate planet "up" direction from hit position
			# This is the outward-facing normal from planet center
			var planet_center = Vector3.ZERO
			var surface_normal = (hit_position - planet_center).normalized()

			# Visualize surface normal as green ray
			DDD.draw_ray_3d(hit_position, surface_normal, 2.0, Color(0, 1, 0))

			if _dig_cmd:
				_dig_cmd = false
				_audio.play_dig(hit_position)

				if _use_heightmaps:
					# Apply heightmap with Settings scale
					var heightmap = _get_current_heightmap()
					if heightmap:
						print("\n🔨 LEFT CLICK - Applying heightmap '%s'" % heightmap.name)
						# Create temporary copy with scaled values
						var scaled_hm = HeightmapItem.new()
						scaled_hm.name = heightmap.name
						scaled_hm.image = heightmap.image
						scaled_hm.blend_mode = heightmap.blend_mode
						scaled_hm.radius = heightmap.radius * _get_settings().heightmap_radius_scale
						scaled_hm.scale_intensity = heightmap.scale_intensity * _get_settings().heightmap_intensity_scale

						print("Settings: radius=%.1fm (base=%.1f × scale=%.2f), intensity=%.2f (base=%.2f × scale=%.2f)" %
							[scaled_hm.radius, heightmap.radius, _get_settings().heightmap_radius_scale,
							 scaled_hm.scale_intensity, heightmap.scale_intensity, _get_settings().heightmap_intensity_scale])

						# Pass calculated surface normal (from planet center outward)
						var spheres_created = scaled_hm.apply_to_terrain(volume, hit_position, surface_normal)

						if spheres_created > 0:
							print("✅ Terrain modification complete! (%d spheres applied)" % spheres_created)
						else:
							print("❌ WARNING: No terrain was modified!")

						# Visualize stamp area
						_visualize_stamp_area(hit_position, scaled_hm.radius)
				else:
					# Legacy sphere-based digging
					var vt : VoxelToolLodTerrain = volume.get_voxel_tool()
					var pos := volume.get_global_transform().affine_inverse() * hit_position
					var sphere_size := 3.5
					vt.channel = VoxelBuffer.CHANNEL_SDF
					vt.mode = VoxelTool.MODE_REMOVE
					vt.do_sphere(pos, sphere_size)

					var splitter_aabb := AABB(pos, Vector3()).grow(16.0)
					var bodies := vt.separate_floating_chunks(splitter_aabb, camera.get_parent())
					print("Created ", len(bodies), " bodies")
					for body in bodies:
						var cmp := SplitChunkRigidBodyComponent.new()
						body.add_child(cmp)
					DDD.draw_box_aabb(splitter_aabb, Color(0,1,0), 60)

			if _build_cmd:
				_build_cmd = false
				_audio.play_dig(hit_position)

				if _use_heightmaps:
					# Apply heightmap with Settings scale
					var heightmap = _get_current_heightmap()
					if heightmap:
						print("\n🛠️ RIGHT CLICK - Applying heightmap '%s'" % heightmap.name)
						# Create temporary copy with scaled values
						var scaled_hm = HeightmapItem.new()
						scaled_hm.name = heightmap.name
						scaled_hm.image = heightmap.image
						scaled_hm.blend_mode = heightmap.blend_mode
						scaled_hm.radius = heightmap.radius * _get_settings().heightmap_radius_scale
						scaled_hm.scale_intensity = heightmap.scale_intensity * _get_settings().heightmap_intensity_scale

						print("Settings: radius=%.1fm (base=%.1f × scale=%.2f), intensity=%.2f (base=%.2f × scale=%.2f)" %
							[scaled_hm.radius, heightmap.radius, _get_settings().heightmap_radius_scale,
							 scaled_hm.scale_intensity, heightmap.scale_intensity, _get_settings().heightmap_intensity_scale])

						# Pass calculated surface normal (from planet center outward)
						var spheres_created = scaled_hm.apply_to_terrain(volume, hit_position, surface_normal)

						if spheres_created > 0:
							print("✅ Terrain modification complete! (%d spheres applied)" % spheres_created)
						else:
							print("❌ WARNING: No terrain was modified!")

						# Visualize stamp area
						_visualize_stamp_area(hit_position, scaled_hm.radius)
				else:
					# Legacy sphere-based building
					var vt : VoxelTool = volume.get_voxel_tool()
					var pos := volume.get_global_transform().affine_inverse() * hit_position
					vt.channel = VoxelBuffer.CHANNEL_SDF
					vt.mode = VoxelTool.MODE_ADD
					vt.do_sphere(pos, 3.5)
			
			if _waypoint_cmd:
				_waypoint_cmd = false
				var planet := _get_solar_system().get_reference_stellar_body()
				var waypoint : Waypoint = WaypointScene.instantiate()
				waypoint.transform = Transform3D(character_body.transform.basis, hit_position)
				planet.node.add_child(waypoint)
				planet.waypoints.append(waypoint)
				_audio.play_waypoint()


func _unhandled_input(event: InputEvent):
	if event is InputEventKey:
		if event.pressed and not event.is_echo():
			match event.keycode:
				KEY_SPACE:
					var body := _get_body()
					body.jump()
				KEY_E:
					_interact_cmd = true
				KEY_F:
					_flashlight.visible = not _flashlight.visible
					if _flashlight.visible:
						_audio.play_light_on()
					else:
						_audio.play_light_off()
				KEY_T:
					_waypoint_cmd = true
				KEY_Q:  # Previous heightmap
					_prev_heightmap()
					get_tree().root.set_input_as_handled()
				KEY_R:  # Next heightmap
					_next_heightmap()
					get_tree().root.set_input_as_handled()
				KEY_H:  # Toggle heightmap/sphere mode
					_use_heightmaps = not _use_heightmaps
					print("Heightmap mode: ", _use_heightmaps)
					DDD.set_text("Mode", "Heightmap" if _use_heightmaps else "Sphere")
					get_tree().root.set_input_as_handled()
					
	elif event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					_dig_cmd = true
				MOUSE_BUTTON_RIGHT:
					_build_cmd = true


func _interact():
	var character_body := _get_body()
	var space_state := character_body.get_world_3d().direct_space_state
	var camera := get_viewport().get_camera_3d()
	var front := -camera.global_transform.basis.z
	var pos := camera.global_transform.origin

	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = pos
	ray_query.to = pos + front * 10.0
	ray_query.collision_mask = CollisionLayers.DEFAULT
	ray_query.collide_with_bodies = false
	ray_query.collide_with_areas = true
	var hit := space_state.intersect_ray(ray_query)

	if not hit.is_empty():
		if hit.collider.name == "CommandPanel":
			var ship : Ship = Util.find_parent_by_type(hit.collider, Ship)
			if ship != null:
				_enter_ship(ship)


func _enter_ship(ship: Ship):
	var camera = get_viewport().get_camera_3d()
	camera.set_target(ship)
	ship.enable_controller()
	_get_body().queue_free()


func _process(delta: float):
	var character_body := _get_body()
	var gtrans := character_body.global_transform

	# We want to rotate only along local Y
	var head_basis := _head.global_transform.basis
	var forward_projected := get_flat_forward_not_normalized(head_basis, _visual_root.global_transform.basis.y)

	var up := gtrans.basis.y
	
	# Visual can be offset.
	# We need global transfotm tho cuz look_at wants a global position
	gtrans.origin = _visual_root.global_transform.origin
	
	var old_root_basis := _visual_root.transform.basis.orthonormalized()
	_visual_root.transform.basis = old_root_basis
	_visual_root.look_at(gtrans.origin + forward_projected, up)
	_visual_root.transform.basis = old_root_basis.slerp(_visual_root.transform.basis, delta * 8.0)
	
	# TODO Temporarily removed Mannequinny, it did not port well to Godot4
	#_process_visual_animated(forward, character_body)
	
	_visual_head.global_transform.basis = head_basis


func _load_heightmaps():
	# Load heightmaps from PNG files in res://textures/heightmaps/

	# Crater_Out.exr from Gaea (16-bit EXR format for precision)
	var crater_out = HeightmapItem.new()
	crater_out.name = "Crater Out"
	crater_out.scale_intensity = 1.5  # Increased for more visible changes
	crater_out.radius = 70.0  # Doubled from 35.0
	crater_out.blend_mode = HeightmapItem.BlendMode.REPLACE
	crater_out.image = load("res://textures/heightmaps/Crater_Out.exr") as Texture2D
	if crater_out.image:
		_heightmaps.append(crater_out)
		print("✓ Crater_Out.exr 로드됨")
	else:
		print("✗ Crater_Out.exr 로드 실패")

	# Slump_Out.png from Gaea
	var slump_out = HeightmapItem.new()
	slump_out.name = "Slump Out"
	slump_out.scale_intensity = 1.5  # Increased for more visible changes
	slump_out.radius = 80.0  # Doubled from 40.0
	slump_out.blend_mode = HeightmapItem.BlendMode.ADD
	slump_out.image = load("res://textures/heightmaps/Slump_Out.exr") as Texture2D
	if slump_out.image:
		_heightmaps.append(slump_out)
		print("✓ Slump_Out.png 로드됨")
	else:
		print("✗ Slump_Out.png 로드 실패")

	# Fallback test heightmaps if no PNG files loaded
	if _heightmaps.is_empty():
		print("PNG 높이맵을 찾을 수 없음. 테스트 높이맵 로드 중...")

		# Test heightmap 1: Simple mountain (white center, black edges)
		var mountain = HeightmapItem.new()
		mountain.name = "Mountain"
		mountain.scale_intensity = 1.0
		mountain.radius = 20.0
		mountain.blend_mode = HeightmapItem.BlendMode.ADD
		mountain.image = _create_test_heightmap_mountain()
		_heightmaps.append(mountain)

		# Test heightmap 2: Crater (black center, white edges)
		var crater = HeightmapItem.new()
		crater.name = "Crater"
		crater.scale_intensity = 0.8
		crater.radius = 25.0
		crater.blend_mode = HeightmapItem.BlendMode.REPLACE
		crater.image = _create_test_heightmap_crater()
		_heightmaps.append(crater)

		# Test heightmap 3: Plateau (half black, half white)
		var plateau = HeightmapItem.new()
		plateau.name = "Plateau"
		plateau.scale_intensity = 1.0
		plateau.radius = 30.0
		plateau.blend_mode = HeightmapItem.BlendMode.ADD
		plateau.image = _create_test_heightmap_plateau()
		_heightmaps.append(plateau)

	print("총 %d개 높이맵 로드됨" % _heightmaps.size())


func _create_test_heightmap_mountain() -> Texture2D:
	# Create a simple mountain heightmap (white in center, black at edges)
	var img = Image.create(256, 256, false, Image.FORMAT_L8)
	for y in range(256):
		for x in range(256):
			var center_x = 128.0
			var center_y = 128.0
			var dist = sqrt(pow(x - center_x, 2) + pow(y - center_y, 2))
			var max_dist = 128.0
			var height = max(0.0, 1.0 - (dist / max_dist))
			img.set_pixel(x, y, Color(height, height, height, 1.0))

	var tex = ImageTexture.create_from_image(img)
	return tex


func _create_test_heightmap_crater() -> Texture2D:
	# Create a crater heightmap (black in center, white at edges)
	var img = Image.create(256, 256, false, Image.FORMAT_L8)
	for y in range(256):
		for x in range(256):
			var center_x = 128.0
			var center_y = 128.0
			var dist = sqrt(pow(x - center_x, 2) + pow(y - center_y, 2))
			var max_dist = 128.0
			var height = (dist / max_dist)
			height = clamp(height, 0.0, 1.0)
			img.set_pixel(x, y, Color(height, height, height, 1.0))

	var tex = ImageTexture.create_from_image(img)
	return tex


func _create_test_heightmap_plateau() -> Texture2D:
	# Create a plateau heightmap (half white, half black)
	var img = Image.create(256, 256, false, Image.FORMAT_L8)
	for y in range(256):
		for x in range(256):
			var height = 1.0 if x > 128 else 0.0
			img.set_pixel(x, y, Color(height, height, height, 1.0))

	var tex = ImageTexture.create_from_image(img)
	return tex


func _get_current_heightmap() -> HeightmapItem:
	if _heightmaps.is_empty():
		return null
	return _heightmaps[_current_heightmap_idx % _heightmaps.size()]


func _next_heightmap():
	_current_heightmap_idx = (_current_heightmap_idx + 1) % _heightmaps.size()
	var current = _get_current_heightmap()
	if current:
		print("Switched to heightmap: ", current.name)
		DDD.set_text("Heightmap", current.name)


func _prev_heightmap():
	_current_heightmap_idx = (_current_heightmap_idx - 1) % _heightmaps.size()
	var current = _get_current_heightmap()
	if current:
		print("Switched to heightmap: ", current.name)
		DDD.set_text("Heightmap", current.name)


func _get_solar_system() -> SolarSystem:
	# TODO That looks really bad. Probably need to use injection some day
	return get_parent().get_parent() as SolarSystem


func _get_settings() -> Settings:
	var solar_system = _get_solar_system()
	if solar_system:
		# solar_system has _settings as a member variable
		return solar_system._settings as Settings
	# Fallback: create new instance
	return Settings.new()


func _visualize_heightmap_area():
	# Continuous visualization of heightmap area when in heightmap mode
	if not _use_heightmaps:
		return

	var character_body := _get_body()
	var camera := get_viewport().get_camera_3d()
	var front := -camera.global_transform.basis.z
	var cam_pos := camera.global_transform.origin
	var space_state := character_body.get_world_3d().direct_space_state

	# Raycast to find terrain
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = cam_pos
	ray_query.to = cam_pos + front * 50.0
	ray_query.exclude = [character_body.get_rid()]
	var hit = space_state.intersect_ray(ray_query)

	if not hit.is_empty() and hit.collider is VoxelLodTerrain:
		var hit_pos = hit.position
		var volume : VoxelLodTerrain = hit.collider

		# Calculate planet "up" direction from hit position
		var planet_center = Vector3.ZERO
		var surface_normal = (hit_pos - planet_center).normalized()

		var heightmap = _get_current_heightmap()
		if heightmap:
			var scaled_radius = heightmap.radius * _get_settings().heightmap_radius_scale
			_draw_stamp_circle(hit_pos, scaled_radius)

			# Preview system disabled for performance
			# TODO: Re-enable with better optimization or toggle option
			# var distance_moved = hit_pos.distance_to(_last_hit_position)
			# var preview_update_threshold = 5.0
			# var time_threshold = 0.25
			# var heightmap_changed = _current_heightmap_idx != _last_preview_heightmap_idx
			# if distance_moved > preview_update_threshold or _preview_update_timer > time_threshold or heightmap_changed or _preview_data.is_empty():
			# 	_update_preview(volume, hit_pos, surface_normal, heightmap)
			# 	_preview_update_timer = 0.0
			# 	_last_preview_heightmap_idx = _current_heightmap_idx
			# _render_preview(volume)


func _draw_stamp_circle(center: Vector3, radius: float):
	# Draw circular outline showing stamp area
	var segments = 24
	var color = Color(0, 1, 1, 0.8)  # Cyan

	for i in range(segments):
		var angle1 = (float(i) / segments) * TAU
		var angle2 = (float(i + 1) / segments) * TAU

		# 지형의 법선을 고려한 평면에 원 그리기
		var p1 = center + Vector3(cos(angle1) * radius, 0, sin(angle1) * radius)
		var p2 = center + Vector3(cos(angle2) * radius, 0, sin(angle2) * radius)

		DDD.draw_ray_3d(p1, (p2 - p1).normalized(), radius * 0.02, color)

	# Draw center point
	DDD.draw_box(center, Vector3(1.5, 1.5, 1.5), color)

	# Display radius info
	DDD.set_text("Stamp Radius", "%.1fm" % radius)


func _visualize_stamp_area(center: Vector3, radius: float):
	# Single-call visualization (legacy, now uses _visualize_heightmap_area)
	_draw_stamp_circle(center, radius)


func _update_preview(volume: VoxelLodTerrain, hit_pos: Vector3, surface_normal: Vector3, heightmap: HeightmapItem):
	# Update preview data for the current heightmap at hit position
	# Create scaled copy for preview calculation
	var scaled_hm = HeightmapItem.new()
	scaled_hm.name = heightmap.name
	scaled_hm.image = heightmap.image
	scaled_hm.blend_mode = heightmap.blend_mode
	scaled_hm.radius = heightmap.radius * _get_settings().heightmap_radius_scale
	scaled_hm.scale_intensity = heightmap.scale_intensity * _get_settings().heightmap_intensity_scale

	# Get preview data (array of {pos, radius, is_add})
	_preview_data = scaled_hm.preview_heightmap_application(volume, hit_pos, surface_normal)
	_last_hit_position = hit_pos
	_last_hit_normal = surface_normal


func _render_preview(volume: VoxelLodTerrain):
	# Render semi-transparent spheres showing what will be applied
	if _preview_data.is_empty():
		DDD.set_text("Preview Spheres", "0")
		return

	var add_count = 0
	var remove_count = 0
	var world_transform = volume.get_global_transform()

	for sphere_data in _preview_data:
		var local_pos = sphere_data["pos"]
		var radius = sphere_data["radius"]
		var is_add = sphere_data["is_add"]

		# Convert local position to world position
		var world_pos = world_transform * local_pos

		# Color: green for ADD, red for REMOVE, semi-transparent
		var color = Color(0, 1, 0, 0.3) if is_add else Color(1, 0, 0, 0.3)

		# Draw semi-transparent sphere
		DDD.draw_box(world_pos, Vector3(radius, radius, radius) * 2.0, color)

		if is_add:
			add_count += 1
		else:
			remove_count += 1

	# Display preview statistics
	DDD.set_text("Preview Spheres", "%d total (ADD: %d, REMOVE: %d)" % [_preview_data.size(), add_count, remove_count])


func _get_body() -> CharacterBody:
	return get_parent() as CharacterBody


# Gets a vector pointing forwards from the specified basis, projected along the ground plane with specified normal.
# That vector's direction is unaffected by the vertical angle of the basis relative to the ground plane,
# so it may be used to orient a character's body based on its head rotation.
static func get_flat_forward_not_normalized(basis: Basis, ground_up: Vector3) -> Vector3:
	var plane := Plane(ground_up, 0)
	var forward_projected := plane.project(-basis.z)
	# Godot math functions are very sensitive so we have to handle fallbacks otherwise we get lots of warnings
	if forward_projected.length_squared() < 0.01:
		if basis.z.dot(ground_up) > 0:
			# Looking down (z points back)
			forward_projected = plane.project(basis.y)
		else:
			# Looking up
			forward_projected = plane.project(-basis.y)
	# Output is not normalized because it is not always necessary depending on usage
	return forward_projected
