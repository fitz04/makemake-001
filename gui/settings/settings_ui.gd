extends CenterContainer

const Settings = preload("res://settings.gd")
const Binding = preload("res://binding.gd")

@onready var _world_scale_x10_checkbox : CheckBox = \
	$PC/MC/VB/TabContainer/Game/GC/VBoxContainer/WorldScaleX10

@onready var _lens_flares_checkbox : CheckBox = $PC/MC/VB/TabContainer/Graphics/GC/LensFlares
@onready var _glow_checkbox : CheckBox = $PC/MC/VB/TabContainer/Graphics/GC/Glow
@onready var _shadows_checkbox : CheckBox = $PC/MC/VB/TabContainer/Graphics/GC/Shadows
@onready var _detail_rendering_selector : OptionButton = \
	$PC/MC/VB/TabContainer/Graphics/GC/DetailRenderingSelector

@onready var _main_volume_slider : Slider = $PC/MC/VB/TabContainer/Sound/GridContainer/MainVolume

@onready var _debug_text_checkbox : CheckBox = $PC/MC/VB/TabContainer/Debug/GC/ShowDebugText
@onready var _show_octree_nodes_checkbox : CheckBox = \
	$PC/MC/VB/TabContainer/Debug/GC/ShowOctreeNodes
@onready var _show_mesh_updates_checkbox : CheckBox = \
	$PC/MC/VB/TabContainer/Debug/GC/ShowMeshUpdates
@onready var _show_edited_data_blocks_checkbox : CheckBox = \
	$PC/MC/VB/TabContainer/Debug/GC/ShowEditedDataBlocks
@onready var _wireframe_checkbox : CheckBox = $PC/MC/VB/TabContainer/Debug/GC/Wireframe
@onready var _clouds_selector : OptionButton = $PC/MC/VB/TabContainer/Graphics/GC/CloudsSelector
@onready var _antialias_selector : OptionButton = \
	$PC/MC/VB/TabContainer/Graphics/GC/AntialiasSelector

@onready var _movement_accel_slider : Slider = $PC/MC/VB/TabContainer/Character/GC/HB1/MovementAccel
@onready var _movement_accel_value_label : Label = $PC/MC/VB/TabContainer/Character/GC/HB1/MovementAccelValue
@onready var _jump_speed_slider : Slider = $PC/MC/VB/TabContainer/Character/GC/HB2/JumpSpeed
@onready var _jump_speed_value_label : Label = $PC/MC/VB/TabContainer/Character/GC/HB2/JumpSpeedValue
@onready var _gravity_slider : Slider = $PC/MC/VB/TabContainer/Character/GC/HB3/Gravity
@onready var _gravity_value_label : Label = $PC/MC/VB/TabContainer/Character/GC/HB3/GravityValue
@onready var _damping_slider : Slider = $PC/MC/VB/TabContainer/Character/GC/HB4/Damping
@onready var _damping_value_label : Label = $PC/MC/VB/TabContainer/Character/GC/HB4/DampingValue

@onready var _ship_accel_slider : Slider = $PC/MC/VB/TabContainer/Character/GC/HB5/ShipAccel
@onready var _ship_accel_value_label : Label = $PC/MC/VB/TabContainer/Character/GC/HB5/ShipAccelValue
@onready var _ship_planet_speed_slider : Slider = $PC/MC/VB/TabContainer/Character/GC/HB6/ShipPlanetSpeed
@onready var _ship_planet_speed_value_label : Label = $PC/MC/VB/TabContainer/Character/GC/HB6/ShipPlanetSpeedValue
@onready var _ship_space_speed_slider : Slider = $PC/MC/VB/TabContainer/Character/GC/HB7/ShipSpaceSpeed
@onready var _ship_space_speed_value_label : Label = $PC/MC/VB/TabContainer/Character/GC/HB7/ShipSpaceSpeedValue


var _settings : Settings
var _updating_gui := false
var _bindings : Array[Binding.BindingBase] = []


func _ready():
	_detail_rendering_selector.clear()
	_detail_rendering_selector.add_item("Disabled", Settings.DETAIL_RENDERING_DISABLED)
	_detail_rendering_selector.add_item("CPU (slow)", Settings.DETAIL_RENDERING_CPU)
	_detail_rendering_selector.add_item("GPU (fast, requires Vulkan)", 
		Settings.DETAIL_RENDERING_GPU)


func set_settings(s: Settings):
	assert(_settings == null)
	
	_settings = s
	
	_bindings.append(Binding.create(_settings, "world_scale_x10", _world_scale_x10_checkbox))
	_bindings.append(Binding.create(_settings, "shadows_enabled", _shadows_checkbox))
	_bindings.append(Binding.create(_settings, "lens_flares_enabled", _lens_flares_checkbox))
	_bindings.append(Binding.create(_settings, "glow_enabled", _glow_checkbox))
	_bindings.append(Binding.create(_settings, "detail_rendering_mode", _detail_rendering_selector))
	# TODO Setting to toggle GPU generation
	_bindings.append(Binding.create(_settings, "main_volume_linear", _main_volume_slider))
	_bindings.append(Binding.create(_settings, "debug_text", _debug_text_checkbox))
	_bindings.append(Binding.create(_settings, "show_octree_nodes", _show_octree_nodes_checkbox))
	_bindings.append(Binding.create(_settings, "show_mesh_updates", _show_mesh_updates_checkbox))
	_bindings.append(Binding.create(_settings, "show_edited_data_blocks", 
		_show_edited_data_blocks_checkbox))
	_bindings.append(Binding.create(_settings, "wireframe", _wireframe_checkbox))
	_bindings.append(Binding.create(_settings, "clouds_quality", _clouds_selector))
	_bindings.append(Binding.create(_settings, "antialias", _antialias_selector))

	# Character physics bindings
	_bindings.append(Binding.create(_settings, "movement_acceleration", _movement_accel_slider))
	_bindings.append(Binding.create(_settings, "jump_speed", _jump_speed_slider))
	_bindings.append(Binding.create(_settings, "gravity", _gravity_slider))
	_bindings.append(Binding.create(_settings, "movement_damping", _damping_slider))

	# Ship physics bindings
	_bindings.append(Binding.create(_settings, "ship_linear_acceleration", _ship_accel_slider))
	_bindings.append(Binding.create(_settings, "ship_speed_cap_on_planet", _ship_planet_speed_slider))
	_bindings.append(Binding.create(_settings, "ship_speed_cap_in_space", _ship_space_speed_slider))

	# Connect sliders to update value labels (character)
	_movement_accel_slider.value_changed.connect(_on_movement_accel_changed)
	_jump_speed_slider.value_changed.connect(_on_jump_speed_changed)
	_gravity_slider.value_changed.connect(_on_gravity_changed)
	_damping_slider.value_changed.connect(_on_damping_changed)

	# Connect sliders to update value labels (ship)
	_ship_accel_slider.value_changed.connect(_on_ship_accel_changed)
	_ship_planet_speed_slider.value_changed.connect(_on_ship_planet_speed_changed)
	_ship_space_speed_slider.value_changed.connect(_on_ship_space_speed_changed)

	_update_ui()


func _update_ui():
	for binding in _bindings:
		binding.update_ui()


func _on_movement_accel_changed(value: float):
	_movement_accel_value_label.text = "%.1f" % value

func _on_jump_speed_changed(value: float):
	_jump_speed_value_label.text = "%.1f" % value

func _on_gravity_changed(value: float):
	_gravity_value_label.text = "%.1f" % value

func _on_damping_changed(value: float):
	_damping_value_label.text = "%.2f" % value

func _on_ship_accel_changed(value: float):
	_ship_accel_value_label.text = "%.1f" % value

func _on_ship_planet_speed_changed(value: float):
	_ship_planet_speed_value_label.text = "%.0f" % value

func _on_ship_space_speed_changed(value: float):
	_ship_space_speed_value_label.text = "%.0f" % value

func _on_Close_pressed():
	hide()

