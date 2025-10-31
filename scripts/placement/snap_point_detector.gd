extends RefCounted
class_name SnapPointDetector

## Detects valid snap points (edges and corners) for building placement
##
## This class is responsible for finding all potential snap points around
## existing buildings and construction sites, calculating their distances,
## and prioritizing them based on type (edge vs corner) and proximity.

# Snap point types
enum SnapType {
	EDGE_NORTH,
	EDGE_SOUTH,
	EDGE_EAST,
	EDGE_WEST,
	CORNER_NE,
	CORNER_NW,
	CORNER_SE,
	CORNER_SW
}

# Snap point data structure
class SnapPoint:
	var position: Vector3
	var type: SnapType
	var target: Node
	var distance: float
	var priority: float  # Lower is better
	var edge_alignment: Vector2  # For edge snaps, stores alignment direction

	func _init(pos: Vector3, snap_type: SnapType, target_node: Node):
		position = pos
		type = snap_type
		target = target_node
		distance = 0.0
		priority = 0.0
		edge_alignment = Vector2.ZERO

# Constants
const EDGE_SNAP_PRIORITY: float = 1.0  # Lower priority = higher preference
const CORNER_SNAP_PRIORITY: float = 2.0  # Corners are lower preference than edges

## Find all valid snap points within range of the ghost building
##
## @param ghost_position: Current position of the ghost building
## @param ghost_size: Size of the ghost building
## @param targets: Array of buildings/construction sites to snap to
## @param max_distance: Maximum distance to consider for snapping
## @param use_spatial_partition: Whether to use spatial partitioning for performance
## @return: Array of SnapPoint objects sorted by priority
func find_snap_points(
	ghost_position: Vector3,
	ghost_size: Vector3,
	targets: Array,
	max_distance: float,
	use_spatial_partition: bool = false
) -> Array[SnapPoint]:
	var snap_points: Array[SnapPoint] = []

	# Filter targets by distance if using spatial partitioning
	var filtered_targets = targets
	if use_spatial_partition:
		filtered_targets = _filter_targets_by_distance(ghost_position, targets, max_distance * 2.0)

	# Find snap points for each target
	for target in filtered_targets:
		if not is_instance_valid(target):
			continue

		var target_size = _get_building_size(target)
		var target_pos = target.global_position

		# Calculate edge snap points
		snap_points.append_array(_find_edge_snap_points(
			ghost_position, ghost_size, target_pos, target_size, target
		))

		# Calculate corner snap points
		snap_points.append_array(_find_corner_snap_points(
			ghost_position, ghost_size, target_pos, target_size, target
		))

	# Calculate distances and priorities
	for snap_point in snap_points:
		snap_point.distance = ghost_position.distance_to(snap_point.position)
		snap_point.priority = _calculate_priority(snap_point)

	# Filter by max distance
	snap_points = snap_points.filter(func(sp): return sp.distance <= max_distance)

	# Sort by priority (lower is better)
	snap_points.sort_custom(func(a, b): return a.priority < b.priority)

	return snap_points

## Find edge-to-edge snap points for a target building
func _find_edge_snap_points(
	ghost_pos: Vector3,
	ghost_size: Vector3,
	target_pos: Vector3,
	target_size: Vector3,
	target: Node
) -> Array[SnapPoint]:
	var snap_points: Array[SnapPoint] = []

	var ghost_half_x = ghost_size.x / 2.0
	var ghost_half_z = ghost_size.z / 2.0
	var target_half_x = target_size.x / 2.0
	var target_half_z = target_size.z / 2.0

	# North edge (ghost placed north of target)
	var north_pos = Vector3(
		target_pos.x,
		ghost_pos.y,
		target_pos.z + target_half_z + ghost_half_z
	)
	var north_snap = SnapPoint.new(north_pos, SnapType.EDGE_NORTH, target)
	north_snap.edge_alignment = Vector2(0, 1)  # Aligned on Z axis
	snap_points.append(north_snap)

	# South edge (ghost placed south of target)
	var south_pos = Vector3(
		target_pos.x,
		ghost_pos.y,
		target_pos.z - target_half_z - ghost_half_z
	)
	var south_snap = SnapPoint.new(south_pos, SnapType.EDGE_SOUTH, target)
	south_snap.edge_alignment = Vector2(0, -1)  # Aligned on Z axis
	snap_points.append(south_snap)

	# East edge (ghost placed east of target)
	var east_pos = Vector3(
		target_pos.x + target_half_x + ghost_half_x,
		ghost_pos.y,
		target_pos.z
	)
	var east_snap = SnapPoint.new(east_pos, SnapType.EDGE_EAST, target)
	east_snap.edge_alignment = Vector2(1, 0)  # Aligned on X axis
	snap_points.append(east_snap)

	# West edge (ghost placed west of target)
	var west_pos = Vector3(
		target_pos.x - target_half_x - ghost_half_x,
		ghost_pos.y,
		target_pos.z
	)
	var west_snap = SnapPoint.new(west_pos, SnapType.EDGE_WEST, target)
	west_snap.edge_alignment = Vector2(-1, 0)  # Aligned on X axis
	snap_points.append(west_snap)

	return snap_points

## Find corner-to-corner snap points for a target building
func _find_corner_snap_points(
	ghost_pos: Vector3,
	ghost_size: Vector3,
	target_pos: Vector3,
	target_size: Vector3,
	target: Node
) -> Array[SnapPoint]:
	var snap_points: Array[SnapPoint] = []

	var ghost_half_x = ghost_size.x / 2.0
	var ghost_half_z = ghost_size.z / 2.0
	var target_half_x = target_size.x / 2.0
	var target_half_z = target_size.z / 2.0

	# Northeast corner
	var ne_pos = Vector3(
		target_pos.x + target_half_x + ghost_half_x,
		ghost_pos.y,
		target_pos.z + target_half_z + ghost_half_z
	)
	snap_points.append(SnapPoint.new(ne_pos, SnapType.CORNER_NE, target))

	# Northwest corner
	var nw_pos = Vector3(
		target_pos.x - target_half_x - ghost_half_x,
		ghost_pos.y,
		target_pos.z + target_half_z + ghost_half_z
	)
	snap_points.append(SnapPoint.new(nw_pos, SnapType.CORNER_NW, target))

	# Southeast corner
	var se_pos = Vector3(
		target_pos.x + target_half_x + ghost_half_x,
		ghost_pos.y,
		target_pos.z - target_half_z - ghost_half_z
	)
	snap_points.append(SnapPoint.new(se_pos, SnapType.CORNER_SE, target))

	# Southwest corner
	var sw_pos = Vector3(
		target_pos.x - target_half_x - ghost_half_x,
		ghost_pos.y,
		target_pos.z - target_half_z - ghost_half_z
	)
	snap_points.append(SnapPoint.new(sw_pos, SnapType.CORNER_SW, target))

	return snap_points

## Calculate priority for a snap point (lower is better)
## Edges have higher priority than corners
## Closer points have higher priority than far points
func _calculate_priority(snap_point: SnapPoint) -> float:
	var base_priority = EDGE_SNAP_PRIORITY if _is_edge_snap(snap_point.type) else CORNER_SNAP_PRIORITY
	# Add distance as a factor (normalized to 0-1 range, assuming max distance ~10 units)
	return base_priority + (snap_point.distance / 10.0)

## Check if snap type is an edge snap
func _is_edge_snap(snap_type: SnapType) -> bool:
	return snap_type in [SnapType.EDGE_NORTH, SnapType.EDGE_SOUTH, SnapType.EDGE_EAST, SnapType.EDGE_WEST]

## Get the size of a building or construction site
func _get_building_size(building: Node) -> Vector3:
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

## Filter targets by distance for spatial partitioning
func _filter_targets_by_distance(position: Vector3, targets: Array, max_distance: float) -> Array:
	var filtered: Array = []
	for target in targets:
		if not is_instance_valid(target):
			continue
		var distance = position.distance_to(target.global_position)
		if distance <= max_distance:
			filtered.append(target)
	return filtered

## Get snap type name for debugging
func get_snap_type_name(snap_type: SnapType) -> String:
	match snap_type:
		SnapType.EDGE_NORTH: return "Edge North"
		SnapType.EDGE_SOUTH: return "Edge South"
		SnapType.EDGE_EAST: return "Edge East"
		SnapType.EDGE_WEST: return "Edge West"
		SnapType.CORNER_NE: return "Corner NE"
		SnapType.CORNER_NW: return "Corner NW"
		SnapType.CORNER_SE: return "Corner SE"
		SnapType.CORNER_SW: return "Corner SW"
		_: return "Unknown"
