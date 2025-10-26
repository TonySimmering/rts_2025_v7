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
