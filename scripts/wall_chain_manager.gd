extends Node
class_name WallChainManager

# Wall chain construction system
# Handles placing multiple connected wall segments in a chain

signal chain_started()
signal segment_added(position: Vector3, rotation: float)
signal chain_ended()

# Chain state
var is_chaining: bool = false
var chain_segments: Array = []  # Array of {position: Vector3, rotation: float}
var current_ghost: Node3D = null
var last_segment_position: Vector3 = Vector3.ZERO

# Wall configuration
const WALL_SEGMENT_LENGTH: float = 4.0
const WALL_THICKNESS: float = 0.5
const MAX_SEGMENT_DISTANCE: float = 8.0  # Maximum distance for next segment
const SNAP_DISTANCE: float = 2.0  # Distance to snap to other walls

# References
var terrain: Node = null
var camera: Camera3D = null

func set_terrain(terr: Node):
	terrain = terr

func set_camera(cam: Camera3D):
	camera = cam

func start_chain(initial_position: Vector3):
	"""Start a new wall chain"""
	is_chaining = true
	chain_segments.clear()
	last_segment_position = initial_position

	# Add initial segment
	add_segment(initial_position, 0.0)
	chain_started.emit()

func add_segment(position: Vector3, rotation: float):
	"""Add a segment to the chain"""
	var segment_data = {
		"position": position,
		"rotation": rotation
	}
	chain_segments.append(segment_data)
	last_segment_position = position
	segment_added.emit(position, rotation)

func update_next_segment_position(mouse_position: Vector3) -> Dictionary:
	"""
	Calculate the next wall segment position based on mouse position
	Returns: {position: Vector3, rotation: float, is_valid: bool, path: Array}
	"""
	if chain_segments.is_empty():
		return {"position": mouse_position, "rotation": 0.0, "is_valid": true, "path": []}

	var last_pos = last_segment_position
	var direction = (mouse_position - last_pos).normalized()
	direction.y = 0  # Keep horizontal

	# Calculate rotation to face the direction
	var rotation = atan2(direction.x, direction.z)

	# Check distance to mouse - if too far, place intermediate segments
	var distance = last_pos.distance_to(mouse_position)

	# Find path from last segment to mouse position
	var path = find_wall_path(last_pos, mouse_position)

	if path.is_empty():
		# No valid path found
		return {
			"position": mouse_position,
			"rotation": rotation,
			"is_valid": false,
			"path": []
		}

	# Use first point in path as next segment position
	var next_position = path[0] if path.size() > 0 else mouse_position

	# Check if we should snap to nearby walls
	var snap_result = check_wall_snap(next_position)
	if snap_result.should_snap:
		next_position = snap_result.snap_position
		rotation = snap_result.snap_rotation

	return {
		"position": next_position,
		"rotation": rotation,
		"is_valid": true,
		"path": path
	}

func find_wall_path(from: Vector3, to: Vector3) -> Array:
	"""
	Find a path for the wall segment, avoiding obstacles
	Returns an array of positions for wall segments
	"""
	var path = []

	# Simple pathfinding: try direct line first
	if is_path_clear(from, to):
		# Direct path is clear - place segments along the line
		var direction = (to - from).normalized()
		var distance = from.distance_to(to)
		var num_segments = int(distance / WALL_SEGMENT_LENGTH)

		for i in range(1, num_segments + 1):
			var segment_pos = from + direction * (WALL_SEGMENT_LENGTH * i)
			# Clamp to terrain height
			if terrain:
				segment_pos.y = terrain.get_height_at_position(segment_pos)
			path.append(segment_pos)

		return path

	# Path is blocked - try to find alternative path
	# For now, we'll use a simple approach: try left and right deflections
	var attempts = [
		Vector3(1, 0, 0),   # Right
		Vector3(-1, 0, 0),  # Left
		Vector3(0, 0, 1),   # Forward
		Vector3(0, 0, -1)   # Back
	]

	for deflection in attempts:
		var mid_point = (from + to) / 2.0 + deflection * WALL_SEGMENT_LENGTH
		if terrain:
			mid_point.y = terrain.get_height_at_position(mid_point)

		if is_path_clear(from, mid_point) and is_path_clear(mid_point, to):
			# Found a valid path through mid point
			var direction1 = (mid_point - from).normalized()
			var distance1 = from.distance_to(mid_point)
			var num_segments1 = max(1, int(distance1 / WALL_SEGMENT_LENGTH))

			for i in range(1, num_segments1 + 1):
				var segment_pos = from + direction1 * (WALL_SEGMENT_LENGTH * i)
				if terrain:
					segment_pos.y = terrain.get_height_at_position(segment_pos)
				path.append(segment_pos)

			return path

	# No path found
	return []

func is_path_clear(from: Vector3, to: Vector3) -> bool:
	"""Check if the path between two points is clear of obstacles"""
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return true  # Assume clear if no physics state

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 8  # Buildings layer
	query.exclude = []

	var result = space_state.intersect_ray(query)
	return result.is_empty()  # Clear if no collision

func check_wall_snap(position: Vector3) -> Dictionary:
	"""Check if we should snap to nearby wall segments"""
	# Find nearby walls
	var nearby_walls = find_nearby_walls(position, SNAP_DISTANCE)

	if nearby_walls.is_empty():
		return {"should_snap": false}

	# Find closest wall endpoint
	var closest_wall = null
	var closest_distance = INF
	var snap_position = position
	var snap_rotation = 0.0

	for wall in nearby_walls:
		if not wall.has_method("get_wall_endpoints"):
			continue

		var endpoints = wall.get_wall_endpoints()
		for endpoint in endpoints:
			var distance = position.distance_to(endpoint)
			if distance < closest_distance:
				closest_distance = distance
				closest_wall = wall
				snap_position = endpoint
				# Calculate rotation to face the wall
				snap_rotation = wall.rotation.y

	if closest_distance < SNAP_DISTANCE:
		return {
			"should_snap": true,
			"snap_position": snap_position,
			"snap_rotation": snap_rotation
		}

	return {"should_snap": false}

func find_nearby_walls(position: Vector3, radius: float) -> Array:
	"""Find all wall buildings near a position"""
	var walls = []
	var game_node = get_tree().root.get_node_or_null("Game")
	if not game_node:
		return walls

	# Find all Wall nodes
	for child in game_node.get_children():
		if child.name.begins_with("Wall") and child.has_method("get_wall_endpoints"):
			var distance = position.distance_to(child.global_position)
			if distance < radius:
				walls.append(child)

	return walls

func end_chain():
	"""End the wall chain"""
	is_chaining = false
	chain_ended.emit()

func get_chain_segments() -> Array:
	"""Get all segments in the current chain"""
	return chain_segments

func clear_chain():
	"""Clear the current chain"""
	chain_segments.clear()
	last_segment_position = Vector3.ZERO
