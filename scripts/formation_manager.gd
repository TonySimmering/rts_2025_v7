extends Node
class_name FormationManager

enum FormationType {
	LINE,
	SQUARE,
	WEDGE,
	CIRCLE
}

const UNIT_SPACING: float = 2.0  # Distance between units
const LINE_WIDTH: int = 8  # Units per row in line formation

static func calculate_formation_positions(
	center: Vector3,
	unit_count: int,
	formation_type: FormationType,
	facing_angle: float = 0.0
) -> Array[Vector3]:
	
	var positions: Array[Vector3] = []
	
	match formation_type:
		FormationType.LINE:
			positions = _calculate_line_formation(center, unit_count, facing_angle)
		FormationType.SQUARE:
			positions = _calculate_square_formation(center, unit_count, facing_angle)
		FormationType.WEDGE:
			positions = _calculate_wedge_formation(center, unit_count, facing_angle)
		FormationType.CIRCLE:
			positions = _calculate_circle_formation(center, unit_count, facing_angle)
	
	return positions

static func _calculate_line_formation(center: Vector3, unit_count: int, facing_angle: float) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	
	var rows = ceili(float(unit_count) / float(LINE_WIDTH))
	var current_unit = 0
	
	for row in range(rows):
		var units_in_row = min(LINE_WIDTH, unit_count - current_unit)
		var row_width = (units_in_row - 1) * UNIT_SPACING
		var row_start_x = -row_width / 2.0
		
		for col in range(units_in_row):
			# Local position (relative to formation center)
			var local_x = row_start_x + col * UNIT_SPACING
			var local_z = row * UNIT_SPACING
			
			# Rotate around facing angle
			var rotated_x = local_x * cos(facing_angle) - local_z * sin(facing_angle)
			var rotated_z = local_x * sin(facing_angle) + local_z * cos(facing_angle)
			
			# World position
			var pos = center + Vector3(rotated_x, 0, rotated_z)
			positions.append(pos)
			
			current_unit += 1
	
	return positions

static func _calculate_square_formation(center: Vector3, unit_count: int, facing_angle: float) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var side_length = ceili(sqrt(unit_count))
	var current_unit = 0
	
	for row in range(side_length):
		for col in range(side_length):
			if current_unit >= unit_count:
				break
			
			var local_x = (col - side_length / 2.0) * UNIT_SPACING
			var local_z = (row - side_length / 2.0) * UNIT_SPACING
			
			var rotated_x = local_x * cos(facing_angle) - local_z * sin(facing_angle)
			var rotated_z = local_x * sin(facing_angle) + local_z * cos(facing_angle)
			
			var pos = center + Vector3(rotated_x, 0, rotated_z)
			positions.append(pos)
			current_unit += 1
	
	return positions

static func _calculate_wedge_formation(center: Vector3, unit_count: int, facing_angle: float) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var current_unit = 0
	var row = 0
	
	while current_unit < unit_count:
		var units_in_row = row + 1
		var row_width = (units_in_row - 1) * UNIT_SPACING
		var row_start_x = -row_width / 2.0
		
		for col in range(units_in_row):
			if current_unit >= unit_count:
				break
			
			var local_x = row_start_x + col * UNIT_SPACING
			var local_z = -row * UNIT_SPACING  # Negative to point forward
			
			var rotated_x = local_x * cos(facing_angle) - local_z * sin(facing_angle)
			var rotated_z = local_x * sin(facing_angle) + local_z * cos(facing_angle)
			
			var pos = center + Vector3(rotated_x, 0, rotated_z)
			positions.append(pos)
			current_unit += 1
		
		row += 1
	
	return positions

static func _calculate_circle_formation(center: Vector3, unit_count: int, facing_angle: float) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var radius = UNIT_SPACING * unit_count / (2.0 * PI)

	for i in range(unit_count):
		var angle = (float(i) / float(unit_count)) * TAU + facing_angle
		var local_x = cos(angle) * radius
		var local_z = sin(angle) * radius

		var pos = center + Vector3(local_x, 0, local_z)
		positions.append(pos)

	return positions

static func validate_and_adjust_positions(
	positions: Array[Vector3],
	world: World3D,
	nav_map: RID
) -> Array[Vector3]:
	"""
	Validate formation positions against obstacles and adjust if needed.
	Checks for physical obstacles (buildings, resources) and navmesh validity.
	"""
	var validated_positions: Array[Vector3] = []
	var space_state = world.direct_space_state

	for pos in positions:
		var final_pos = pos

		# First, snap to navmesh
		var navmesh_pos = NavigationServer3D.map_get_closest_point(nav_map, pos)

		# Check if there's a physical obstacle at this position
		var query = PhysicsRayQueryParameters3D.create(
			navmesh_pos + Vector3(0, 5, 0),  # Start above position
			navmesh_pos + Vector3(0, -1, 0)   # Cast down
		)
		query.collision_mask = 12  # Check buildings (layer 4) and resources (layer 3)

		var result = space_state.intersect_ray(query)

		if result:
			# Obstacle detected, try to find nearby clear position
			var adjusted_pos = _find_nearby_clear_position(
				navmesh_pos,
				space_state,
				nav_map
			)
			if adjusted_pos != Vector3.ZERO:
				final_pos = adjusted_pos
			else:
				# Use navmesh position as fallback
				final_pos = navmesh_pos
		else:
			final_pos = navmesh_pos

		validated_positions.append(final_pos)

	return validated_positions

static func _find_nearby_clear_position(
	blocked_pos: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	nav_map: RID
) -> Vector3:
	"""Find a nearby position that's clear of obstacles"""
	var search_offsets = [
		Vector3(1.5, 0, 0),
		Vector3(-1.5, 0, 0),
		Vector3(0, 0, 1.5),
		Vector3(0, 0, -1.5),
		Vector3(1.5, 0, 1.5),
		Vector3(-1.5, 0, -1.5),
		Vector3(1.5, 0, -1.5),
		Vector3(-1.5, 0, 1.5),
	]

	for offset in search_offsets:
		var test_pos = blocked_pos + offset
		var navmesh_pos = NavigationServer3D.map_get_closest_point(nav_map, test_pos)

		# Check if this position is clear
		var query = PhysicsRayQueryParameters3D.create(
			navmesh_pos + Vector3(0, 5, 0),
			navmesh_pos + Vector3(0, -1, 0)
		)
		query.collision_mask = 12

		var result = space_state.intersect_ray(query)

		if not result:
			return navmesh_pos

	return Vector3.ZERO  # No clear position found
