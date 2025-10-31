extends RefCounted
class_name BuildingSnapController

## Controls magnetic snapping behavior for building placement
##
## This class manages the snapping state, determines when to snap/unsnap,
## and applies smooth transitions between snapped and free placement modes.

# Snap thresholds (in world units)
const SNAP_DISTANCE: float = 4.5  # Distance to trigger snapping (under 5 units as required)
const UNSNAP_DISTANCE: float = 7.0  # Distance to release snap (magnetic feel)
const SMOOTH_SNAP_SPEED: float = 10.0  # Interpolation speed for smooth snapping

# Current snap state
var is_snapping: bool = false
var snap_position: Vector3 = Vector3.ZERO
var current_snap_point: SnapPointDetector.SnapPoint = null
var last_mouse_position: Vector3 = Vector3.ZERO

# Snap detector
var snap_detector: SnapPointDetector = SnapPointDetector.new()

# Smooth snapping interpolation
var use_smooth_snapping: bool = true
var snap_lerp_weight: float = 0.0

## Update snapping state based on current ghost position and mouse position
##
## @param ghost_position: Current position of the ghost building
## @param ghost_size: Size of the ghost building
## @param mouse_world_pos: World position of the mouse cursor
## @param targets: Array of buildings/construction sites to snap to
## @param delta: Time delta for smooth interpolation
## @return: Updated position (either snapped or original)
func update_snapping(
	ghost_position: Vector3,
	ghost_size: Vector3,
	mouse_world_pos: Vector3,
	targets: Array,
	delta: float = 0.0
) -> Vector3:
	last_mouse_position = mouse_world_pos

	# If already snapping, check if we should unsnap
	if is_snapping:
		var distance_from_snap = mouse_world_pos.distance_to(snap_position)
		if distance_from_snap > UNSNAP_DISTANCE:
			_release_snap()
			return ghost_position
		else:
			# Still within threshold, maintain snap
			if use_smooth_snapping and delta > 0:
				snap_lerp_weight = min(snap_lerp_weight + delta * SMOOTH_SNAP_SPEED, 1.0)
				return ghost_position.lerp(snap_position, snap_lerp_weight)
			else:
				return snap_position

	# Not currently snapping, look for snap points
	var snap_points = snap_detector.find_snap_points(
		ghost_position,
		ghost_size,
		targets,
		SNAP_DISTANCE,
		true  # Use spatial partitioning
	)

	if snap_points.is_empty():
		return ghost_position

	# Get the best snap point (already sorted by priority)
	var best_snap = snap_points[0]

	# Activate snap
	_activate_snap(best_snap)

	if use_smooth_snapping and delta > 0:
		snap_lerp_weight = 0.0
		return ghost_position.lerp(snap_position, snap_lerp_weight)
	else:
		return snap_position

## Get all nearby snap points for visualization
##
## @param ghost_position: Current position of the ghost building
## @param ghost_size: Size of the ghost building
## @param targets: Array of buildings/construction sites to snap to
## @param max_distance: Maximum distance to show snap points
## @return: Array of SnapPoint objects
func get_nearby_snap_points(
	ghost_position: Vector3,
	ghost_size: Vector3,
	targets: Array,
	max_distance: float = SNAP_DISTANCE * 2.0
) -> Array[SnapPointDetector.SnapPoint]:
	return snap_detector.find_snap_points(
		ghost_position,
		ghost_size,
		targets,
		max_distance,
		true
	)

## Get the current snap target (building being snapped to)
func get_snap_target() -> Node:
	if current_snap_point and is_instance_valid(current_snap_point.target):
		return current_snap_point.target
	return null

## Get information about the current snap
func get_snap_info() -> Dictionary:
	if not is_snapping or not current_snap_point:
		return {}

	return {
		"is_snapping": is_snapping,
		"position": snap_position,
		"target": current_snap_point.target,
		"type": snap_detector.get_snap_type_name(current_snap_point.type),
		"distance": current_snap_point.distance,
		"alignment": current_snap_point.edge_alignment
	}

## Force release the current snap
func force_unsnap():
	_release_snap()

## Check if currently snapping
func is_currently_snapping() -> bool:
	return is_snapping

## Get current snap position
func get_snap_position() -> Vector3:
	return snap_position if is_snapping else Vector3.ZERO

## Activate snapping to a specific snap point
func _activate_snap(snap_point: SnapPointDetector.SnapPoint):
	is_snapping = true
	current_snap_point = snap_point
	snap_position = snap_point.position
	snap_lerp_weight = 0.0

## Release the current snap
func _release_snap():
	is_snapping = false
	current_snap_point = null
	snap_position = Vector3.ZERO
	snap_lerp_weight = 0.0

## Set whether to use smooth snapping interpolation
func set_smooth_snapping(enabled: bool):
	use_smooth_snapping = enabled

## Get snap distance threshold
func get_snap_distance() -> float:
	return SNAP_DISTANCE

## Get unsnap distance threshold
func get_unsnap_distance() -> float:
	return UNSNAP_DISTANCE
