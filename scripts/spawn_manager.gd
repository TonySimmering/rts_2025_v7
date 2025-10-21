extends Node

# Spawn settings
const WORKERS_PER_PLAYER = 3
const SPAWN_RADIUS = 5.0

# Preload scenes
const WORKER_SCENE = preload("res://scenes/units/worker.tscn")

var terrain: Node3D = null
var spawned_units: Dictionary = {}  # player_id -> Array[units]

func spawn_starting_units(player_id: int, spawn_center: Vector3):
	"""Spawn initial units for a player at the given location"""
	print("Spawning units for player ", player_id, " at ", spawn_center)
	
	if not spawned_units.has(player_id):
		spawned_units[player_id] = []
	
	for i in range(WORKERS_PER_PLAYER):
		var angle = (float(i) / WORKERS_PER_PLAYER) * TAU
		var offset = Vector3(
			cos(angle) * SPAWN_RADIUS,
			0,
			sin(angle) * SPAWN_RADIUS
		)
		
		var spawn_pos = spawn_center + offset
		
		# FIX: Query NavMesh for correct spawn height instead of terrain heightmap
		if terrain:
			var nav_map = get_tree().root.get_world_3d().navigation_map
			var closest_point = NavigationServer3D.map_get_closest_point(nav_map, spawn_pos)
			spawn_pos.y = closest_point.y + 0.1  # Slightly above NavMesh
		
		var worker = WORKER_SCENE.instantiate()
		worker.global_position = spawn_pos
		worker.player_id = player_id
		worker.unit_id = i
		
		get_tree().root.get_node("Game").add_child(worker)
		spawned_units[player_id].append(worker)
		
		print("  Spawned worker ", i, " at ", spawn_pos)

func get_spawn_location_for_player(player_id: int, map_size: Vector2) -> Vector3:
	"""Calculate spawn location based on player ID"""
	var spawn_positions = [
		Vector3(map_size.x * 0.2, 0, map_size.y * 0.2),  # Bottom-left
		Vector3(map_size.x * 0.8, 0, map_size.y * 0.8),  # Top-right
		Vector3(map_size.x * 0.8, 0, map_size.y * 0.2),  # Bottom-right
		Vector3(map_size.x * 0.2, 0, map_size.y * 0.8),  # Top-left
	]
	
	var index = (player_id - 1) % spawn_positions.size()
	return spawn_positions[index]
