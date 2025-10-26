extends Node
class_name FlowField

## Simple flow field implementation for group movement
## Units follow a direction field toward a goal instead of individual paths

const GRID_CELL_SIZE: float = 2.0

static func calculate_flow_field(
	nav_map: RID,
	goal: Vector3,
	bounds_min: Vector3,
	bounds_max: Vector3
) -> Dictionary:
	"""
	Returns a dictionary mapping Vector3 grid positions to Vector3 directions
	Units sample this field to know which way to move
	"""
	var flow_field: Dictionary = {}
	
	# Create a grid covering the area
	var x = bounds_min.x
	while x <= bounds_max.x:
		var z = bounds_min.z
		while z <= bounds_max.z:
			var grid_pos = Vector3(x, 0, z)
			
			# Calculate path from this cell to goal
			var path = NavigationServer3D.map_get_path(nav_map, grid_pos, goal, true)
			
			if path.size() >= 2:
				# Direction is toward next waypoint
				var direction = (path[1] - path[0]).normalized()
				flow_field[grid_pos] = direction
			else:
				# No path, use direct line
				flow_field[grid_pos] = (goal - grid_pos).normalized()
			
			z += GRID_CELL_SIZE
		x += GRID_CELL_SIZE
	
	return flow_field

static func sample_flow_field(flow_field: Dictionary, position: Vector3) -> Vector3:
	"""Get direction from flow field at given position (with interpolation)"""
	
	# Find nearest grid cell
	var grid_x = round(position.x / GRID_CELL_SIZE) * GRID_CELL_SIZE
	var grid_z = round(position.z / GRID_CELL_SIZE) * GRID_CELL_SIZE
	var grid_pos = Vector3(grid_x, 0, grid_z)
	
	if flow_field.has(grid_pos):
		return flow_field[grid_pos]
	
	# Fallback: find closest cell
	var closest_pos = Vector3.ZERO
	var closest_dist = INF
	
	for cell_pos in flow_field.keys():
		var dist = position.distance_to(cell_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_pos = cell_pos
	
	if flow_field.has(closest_pos):
		return flow_field[closest_pos]
	
	return Vector3.ZERO
