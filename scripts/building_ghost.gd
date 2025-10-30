extends Node3D
class_name BuildingGhost

# Ghost placement preview for buildings

# Ghost state
var building_type: String = ""
var building_size: Vector3 = Vector3(4, 4, 4)
var rotation_angle: float = 0.0  # Y-axis rotation in radians
var is_valid_placement: bool = false
var snap_position: Vector3 = Vector3.ZERO
var is_snapping: bool = false

# Placement validation
const MAX_TERRAIN_SLOPE: float = 0.3  # Maximum slope angle for building
const SNAP_DISTANCE: float = 8.0  # Distance to trigger snapping
const SNAP_GRID_SIZE: float = 4.0  # Grid size for snapping

# Visual references
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var placement_indicator: MeshInstance3D = $PlacementIndicator

# Materials
var valid_material: StandardMaterial3D
var invalid_material: StandardMaterial3D

func _ready():
	setup_materials()
	setup_mesh()
	update_placement_validity(false)

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
	global_position = world_position

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
	shape.size = building_size * 0.9  # Slightly smaller for clearance

	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position + Vector3(0, building_size.y/2, 0))
	query.collision_mask = 8  # Layer 4 - buildings

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

func check_for_snapping(player_id: int) -> bool:
	"""Check if ghost should snap to nearby buildings and construction sites"""
	# Get both buildings AND construction sites
	var buildings = get_tree().get_nodes_in_group("player_%d_buildings" % player_id)
	var construction_sites = get_tree().get_nodes_in_group("player_%d_construction_sites" % player_id)

	# Combine into one array of targets
	var all_targets = buildings + construction_sites

	if all_targets.is_empty():
		is_snapping = false
		return false

	# Find the nearest corner-to-corner snap position
	var best_snap_data = find_nearest_corner_snap(all_targets)

	if not best_snap_data.is_empty():
		snap_position = best_snap_data.position
		is_snapping = true
		return true
	else:
		is_snapping = false
		return false

func get_building_size(building: Node) -> Vector3:
	"""Get the size of a building or construction site"""
	# Check if it's a construction site with building_size property
	if "building_size" in building:
		return building.building_size

	# Try to find CollisionShape3D child
	for child in building.get_children():
		if child is CollisionShape3D:
			var shape = child.shape
			if shape is BoxShape3D:
				return shape.size

	# Fallback to default size if not found
	return Vector3(4, 4, 4)

func get_corners_2d(center: Vector3, size: Vector3) -> Array:
	"""Get the 4 corners of a building in 2D (XZ plane)"""
	var half_x = size.x / 2.0
	var half_z = size.z / 2.0

	return [
		Vector2(center.x - half_x, center.z - half_z),  # Bottom-left
		Vector2(center.x + half_x, center.z - half_z),  # Bottom-right
		Vector2(center.x - half_x, center.z + half_z),  # Top-left
		Vector2(center.x + half_x, center.z + half_z),  # Top-right
	]

func find_nearest_corner_snap(targets: Array) -> Dictionary:
	"""Find the nearest corner-to-corner snap position among all targets"""
	var ghost_corners = get_corners_2d(global_position, building_size)
	var best_snap_distance = SNAP_DISTANCE
	var best_snap_position = null

	for target in targets:
		if not is_instance_valid(target):
			continue

		var target_size = get_building_size(target)
		var target_corners = get_corners_2d(target.global_position, target_size)

		# Check all corner-to-corner combinations
		for ghost_corner_idx in range(ghost_corners.size()):
			var ghost_corner = ghost_corners[ghost_corner_idx]

			for target_corner_idx in range(target_corners.size()):
				var target_corner = target_corners[target_corner_idx]

				# Calculate distance between these two corners
				var distance = ghost_corner.distance_to(target_corner)

				if distance < best_snap_distance:
					# Calculate where ghost center would be if this corner aligned
					var corner_offset = ghost_corner - Vector2(global_position.x, global_position.z)
					var new_center = Vector3(
						target_corner.x - corner_offset.x,
						global_position.y,
						target_corner.y - corner_offset.y
					)

					# Snap to grid
					new_center.x = round(new_center.x / SNAP_GRID_SIZE) * SNAP_GRID_SIZE
					new_center.z = round(new_center.z / SNAP_GRID_SIZE) * SNAP_GRID_SIZE

					best_snap_distance = distance
					best_snap_position = new_center

	if best_snap_position != null:
		return {"position": best_snap_position, "distance": best_snap_distance}
	else:
		return {}  # Return empty dictionary instead of null

func apply_snapping():
	"""Apply snapped position to ghost"""
	if is_snapping:
		global_position = snap_position

func get_placement_data() -> Dictionary:
	"""Get placement data for construction"""
	return {
		"building_type": building_type,
		"position": global_position,
		"rotation": rotation_angle,
		"size": building_size
	}
