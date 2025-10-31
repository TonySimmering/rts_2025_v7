extends Node3D
class_name BuildingGhost

# Ghost placement preview for buildings with modular snapping system

# Ghost state
var building_type: String = ""
var building_size: Vector3 = Vector3(4, 4, 4)
var rotation_angle: float = 0.0  # Y-axis rotation in radians
var is_valid_placement: bool = false

# Placement validation
const MAX_TERRAIN_SLOPE: float = 0.3  # Maximum slope angle for building

# Visual references
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var placement_indicator: MeshInstance3D = $PlacementIndicator

# Materials
var valid_material: StandardMaterial3D
var invalid_material: StandardMaterial3D

# Modular placement components
var snap_controller: BuildingSnapController
var grid_manager: GridManager
var visualizer: PlacementVisualizer

# Cached data for visualization
var nearby_snap_points: Array = []
var last_update_time: float = 0.0

func _ready():
	setup_materials()
	setup_mesh()
	setup_placement_components()
	update_placement_validity(false)

func setup_placement_components():
	"""Initialize modular placement components"""
	# Create snap controller
	snap_controller = BuildingSnapController.new()
	snap_controller.set_smooth_snapping(true)

	# Create grid manager
	grid_manager = GridManager.new(4.0)  # 4.0 grid size
	grid_manager.set_grid_enabled(true)

	# Create visualizer
	visualizer = PlacementVisualizer.new()
	add_child(visualizer)
	visualizer.set_snap_points_visible(true)
	visualizer.set_snap_lines_visible(true)
	visualizer.set_connections_visible(true)

func _process(delta):
	"""Update visualizations each frame"""
	# Update visualizer with current snap state
	if visualizer and snap_controller:
		var active_snap = null
		if snap_controller.is_currently_snapping():
			var snap_info = snap_controller.get_snap_info()
			# Create a minimal snap point for visualization
			if not snap_info.is_empty():
				active_snap = {
					"position": snap_info.position,
					"target": snap_info.target
				}

		# Get grid visualization data if needed
		var grid_data = {}
		if grid_manager and grid_manager.is_grid_visible():
			var camera_pos = get_viewport().get_camera_3d().global_position if get_viewport().get_camera_3d() else global_position
			grid_data = grid_manager.get_grid_visualization_data(camera_pos, 30.0)

		visualizer.update_visualization(
			global_position,
			nearby_snap_points,
			active_snap,
			grid_data
		)

func setup_materials():
	"""Create materials for valid/invalid placement"""
	# Valid placement - green transparent
	valid_material = StandardMaterial3D.new()
	valid_material.albedo_color = Color(0.2, 0.8, 0.2, 0.5)
	valid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	valid_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Invalid placement - red transparent
	invalid_material = StandardMaterial3D.new()
	invalid_material.albedo_color = Color(0.8, 0.2, 0.2, 0.5)
	invalid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	invalid_material.cull_mode = BaseMaterial3D.CULL_DISABLED

func setup_mesh():
	"""Create mesh based on building type"""
	if not mesh_instance:
		return

	var box_mesh = BoxMesh.new()
	box_mesh.size = building_size
	mesh_instance.mesh = box_mesh
	mesh_instance.position.y = building_size.y / 2.0

func set_building_type(type: String):
	"""Set the building type and update visuals"""
	building_type = type

	# Set size based on building type
	match building_type:
		"town_center":
			building_size = Vector3(8, 6, 8)
		"house":
			building_size = Vector3(4, 4, 4)
		"barracks":
			building_size = Vector3(6, 5, 6)

	setup_mesh()

func update_position(world_position: Vector3, terrain: Node):
	"""Update ghost position and validate placement"""
	# Apply grid snapping if not magnetically snapping
	var final_position = world_position

	if grid_manager and not snap_controller.is_currently_snapping():
		final_position = grid_manager.snap_to_grid(world_position, building_size)

	global_position = final_position

	# Check placement validity
	is_valid_placement = validate_placement(terrain)

	# Update visual feedback
	update_placement_validity(is_valid_placement)

func validate_placement(terrain: Node) -> bool:
	"""Check if placement is valid at current position"""
	if not terrain:
		return false

	# Check terrain slope
	if not is_terrain_suitable(terrain):
		return false

	# Check for obstacles (other buildings, construction sites)
	if has_obstacles():
		return false

	# Check if on navigable terrain
	if not is_on_navmesh():
		return false

	return true

func is_terrain_suitable(terrain: Node) -> bool:
	"""Check if terrain slope is acceptable"""
	# Sample multiple points around building footprint
	var sample_points = [
		global_position,
		global_position + Vector3(building_size.x/2, 0, 0),
		global_position + Vector3(-building_size.x/2, 0, 0),
		global_position + Vector3(0, 0, building_size.z/2),
		global_position + Vector3(0, 0, -building_size.z/2)
	]

	var heights = []
	for point in sample_points:
		var height = terrain.get_height_at_position(point)
		heights.append(height)

	# Check height variance
	var min_height = heights.min()
	var max_height = heights.max()
	var height_diff = max_height - min_height

	# Reject if slope is too steep
	return height_diff < building_size.x * MAX_TERRAIN_SLOPE

func has_obstacles() -> bool:
	"""Check for obstacles at placement position"""
	var space_state = get_world_3d().direct_space_state

	# Create a box shape for collision check
	var shape = BoxShape3D.new()
	shape.size = building_size  # Use full size for accurate edge-to-edge placement

	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position + Vector3(0, building_size.y/2, 0))
	query.collision_mask = 8  # Layer 4 - buildings

	# Exclude the building we're snapping to from collision detection
	var snap_target = snap_controller.get_snap_target() if snap_controller else null
	if snap_target and is_instance_valid(snap_target):
		query.exclude = [snap_target.get_rid()]

	var results = space_state.intersect_shape(query, 10)

	return results.size() > 0

func is_on_navmesh() -> bool:
	"""Check if position is on navigable terrain"""
	var nav_map = get_world_3d().navigation_map
	var closest = NavigationServer3D.map_get_closest_point(nav_map, global_position)

	# Check if closest point is reasonably close
	return global_position.distance_to(closest) < 2.0

func update_placement_validity(valid: bool):
	"""Update visual feedback based on placement validity"""
	is_valid_placement = valid

	if not mesh_instance:
		return

	if valid:
		mesh_instance.set_surface_override_material(0, valid_material)
	else:
		mesh_instance.set_surface_override_material(0, invalid_material)

func rotate_building(angle_delta: float):
	"""Rotate building by angle_delta radians"""
	rotation_angle += angle_delta
	rotation.y = rotation_angle

func check_for_snapping(player_id: int, mouse_world_pos: Vector3, delta: float = 0.0) -> bool:
	"""Check if ghost should snap to nearby buildings and construction sites (magnetic behavior)"""
	if not snap_controller:
		return false

	# Get both buildings AND construction sites
	var buildings = get_tree().get_nodes_in_group("player_%d_buildings" % player_id)
	var construction_sites = get_tree().get_nodes_in_group("player_%d_construction_sites" % player_id)

	# Combine into one array of targets
	var all_targets = buildings + construction_sites

	if all_targets.is_empty():
		return false

	# Update snapping using the controller
	var snapped_position = snap_controller.update_snapping(
		global_position,
		building_size,
		mouse_world_pos,
		all_targets,
		delta
	)

	# Get nearby snap points for visualization
	nearby_snap_points = snap_controller.get_nearby_snap_points(
		global_position,
		building_size,
		all_targets,
		snap_controller.get_snap_distance() * 2.0
	)

	# Apply the snapped position
	if snap_controller.is_currently_snapping():
		global_position = snapped_position
		return true

	return false

func apply_snapping():
	"""Apply snapped position to ghost (handled by snap controller now)"""
	# This is now handled by the snap controller in check_for_snapping
	pass

func get_placement_data() -> Dictionary:
	"""Get placement data for construction"""
	return {
		"building_type": building_type,
		"position": global_position,
		"rotation": rotation_angle,
		"size": building_size
	}
