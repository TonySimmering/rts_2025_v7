extends RefCounted
class_name GridManager

## Manages grid-based building placement
##
## This class handles snapping to a grid system and provides
## functionality for both grid-aligned and free-form placement.

# Grid settings
const DEFAULT_GRID_SIZE: float = 4.0  # Size of each grid cell
const MIN_GRID_SIZE: float = 0.5
const MAX_GRID_SIZE: float = 10.0

# Grid state
var grid_size: float = DEFAULT_GRID_SIZE
var grid_enabled: bool = true
var grid_origin: Vector3 = Vector3.ZERO

# Grid visualization
var show_grid: bool = false
var grid_color: Color = Color(0.5, 0.5, 0.5, 0.3)
var grid_extend: float = 50.0  # How far to extend grid in each direction

## Initialize the grid manager
func _init(initial_grid_size: float = DEFAULT_GRID_SIZE, origin: Vector3 = Vector3.ZERO):
	set_grid_size(initial_grid_size)
	grid_origin = origin

## Snap a position to the grid
##
## @param position: World position to snap
## @param building_size: Size of the building (for centering on grid)
## @return: Grid-snapped position
func snap_to_grid(position: Vector3, building_size: Vector3 = Vector3.ZERO) -> Vector3:
	if not grid_enabled:
		return position

	var snapped = position

	# Snap to grid cells
	snapped.x = round((position.x - grid_origin.x) / grid_size) * grid_size + grid_origin.x
	snapped.z = round((position.z - grid_origin.z) / grid_size) * grid_size + grid_origin.z

	# Keep Y coordinate unchanged (follows terrain)
	# snapped.y = position.y

	return snapped

## Check if a position is aligned with the grid
##
## @param position: World position to check
## @param tolerance: Allowed deviation from grid alignment
## @return: True if position is grid-aligned
func is_grid_aligned(position: Vector3, tolerance: float = 0.1) -> bool:
	var snapped = snap_to_grid(position)
	var distance = Vector2(position.x - snapped.x, position.z - snapped.z).length()
	return distance < tolerance

## Get the nearest grid cell center
##
## @param position: World position
## @return: Center of the nearest grid cell
func get_nearest_grid_cell(position: Vector3) -> Vector3:
	return snap_to_grid(position)

## Get grid cells within a radius
##
## @param center: Center position
## @param radius: Radius to search
## @return: Array of grid cell centers
func get_grid_cells_in_radius(center: Vector3, radius: float) -> Array[Vector3]:
	var cells: Array[Vector3] = []

	var min_x = floor((center.x - radius) / grid_size) * grid_size
	var max_x = ceil((center.x + radius) / grid_size) * grid_size
	var min_z = floor((center.z - radius) / grid_size) * grid_size
	var max_z = ceil((center.z + radius) / grid_size) * grid_size

	var x = min_x
	while x <= max_x:
		var z = min_z
		while z <= max_z:
			var cell_center = Vector3(x, center.y, z)
			if center.distance_to(cell_center) <= radius:
				cells.append(cell_center)
			z += grid_size
		x += grid_size

	return cells

## Set grid size
##
## @param size: New grid size (clamped to min/max)
func set_grid_size(size: float):
	grid_size = clamp(size, MIN_GRID_SIZE, MAX_GRID_SIZE)

## Get current grid size
func get_grid_size() -> float:
	return grid_size

## Enable or disable grid snapping
func set_grid_enabled(enabled: bool):
	grid_enabled = enabled

## Check if grid is enabled
func is_grid_enabled() -> bool:
	return grid_enabled

## Set grid origin
func set_grid_origin(origin: Vector3):
	grid_origin = origin

## Get grid origin
func get_grid_origin() -> Vector3:
	return grid_origin

## Toggle grid visibility
func set_grid_visible(visible: bool):
	show_grid = visible

## Check if grid is visible
func is_grid_visible() -> bool:
	return show_grid

## Get grid visualization data for rendering
##
## @param camera_position: Camera position for LOD
## @param view_distance: How far to render grid
## @return: Dictionary with grid line data
func get_grid_visualization_data(camera_position: Vector3, view_distance: float = 50.0) -> Dictionary:
	if not show_grid:
		return {}

	var lines: Array[Dictionary] = []

	# Calculate grid bounds around camera
	var min_x = floor((camera_position.x - view_distance) / grid_size) * grid_size
	var max_x = ceil((camera_position.x + view_distance) / grid_size) * grid_size
	var min_z = floor((camera_position.z - view_distance) / grid_size) * grid_size
	var max_z = ceil((camera_position.z + view_distance) / grid_size) * grid_size

	var y = camera_position.y  # Grid at camera height for visualization

	# Vertical lines (along Z axis)
	var x = min_x
	while x <= max_x:
		lines.append({
			"start": Vector3(x, y, min_z),
			"end": Vector3(x, y, max_z),
			"color": grid_color
		})
		x += grid_size

	# Horizontal lines (along X axis)
	var z = min_z
	while z <= max_z:
		lines.append({
			"start": Vector3(min_x, y, z),
			"end": Vector3(max_x, y, z),
			"color": grid_color
		})
		z += grid_size

	return {
		"lines": lines,
		"grid_size": grid_size,
		"origin": grid_origin
	}

## Calculate building footprint on grid
##
## @param position: Building position
## @param size: Building size
## @return: Array of grid cells occupied by building
func get_building_footprint_cells(position: Vector3, size: Vector3) -> Array[Vector3]:
	var cells: Array[Vector3] = []

	var half_x = size.x / 2.0
	var half_z = size.z / 2.0

	var min_x = floor((position.x - half_x) / grid_size) * grid_size
	var max_x = ceil((position.x + half_x) / grid_size) * grid_size
	var min_z = floor((position.z - half_z) / grid_size) * grid_size
	var max_z = ceil((position.z + half_z) / grid_size) * grid_size

	var x = min_x
	while x <= max_x:
		var z = min_z
		while z <= max_z:
			cells.append(Vector3(x, position.y, z))
			z += grid_size
		x += grid_size

	return cells

## Determine if magnetic snap should override grid snap
##
## @param magnetic_snap_active: Whether magnetic snapping is currently active
## @param distance_to_magnetic: Distance to nearest magnetic snap point
## @param magnetic_snap_threshold: Threshold for magnetic snapping
## @return: True if magnetic snap should take priority
func should_use_magnetic_snap(
	magnetic_snap_active: bool,
	distance_to_magnetic: float,
	magnetic_snap_threshold: float
) -> bool:
	# Magnetic snap always takes priority when active and close enough
	return magnetic_snap_active and distance_to_magnetic < magnetic_snap_threshold * 1.5
