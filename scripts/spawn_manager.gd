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
		
		# Query NavMesh for correct spawn height
		if terrain:
			var nav_map = get_tree().root.get_world_3d().navigation_map
			var closest_point = NavigationServer3D.map_get_closest_point(nav_map, spawn_pos)
			spawn_pos.y = closest_point.y + 0.1
		
		# CHANGED: Use RPC to spawn on all clients
		spawn_unit_networked.rpc(player_id, i, spawn_pos)

@rpc("authority", "call_local", "reliable")
func spawn_unit_networked(player_id: int, unit_id: int, spawn_pos: Vector3):
	"""Spawn a unit on all clients"""
	var worker = WORKER_SCENE.instantiate()
	worker.global_position = spawn_pos
	worker.player_id = player_id
	worker.unit_id = unit_id
	worker.name = "Unit_P%d_U%d" % [player_id, unit_id]  # Unique name
	
	get_tree().root.get_node("Game").add_child(worker)
	
	if not spawned_units.has(player_id):
		spawned_units[player_id] = []
	spawned_units[player_id].append(worker)
	
	print("  Spawned worker ", unit_id, " for player ", player_id, " at ", spawn_pos)

func get_spawn_location_for_player(player_id: int, map_size: Vector2) -> Vector3:
	"""Calculate spawn location based on player ID"""
	var spawn_positions = [
		Vector3(map_size.x * 0.2, 0, map_size.y * 0.2),  # Bottom-left (player 1)
		Vector3(map_size.x * 0.8, 0, map_size.y * 0.8),  # Top-right (player 2)
		Vector3(map_size.x * 0.8, 0, map_size.y * 0.2),  # Bottom-right (player 3)
		Vector3(map_size.x * 0.2, 0, map_size.y * 0.8),  # Top-left (player 4)
	]
	
	# Get all player IDs and sort them to ensure consistent assignment
	var player_ids = NetworkManager.players.keys()
	player_ids.sort()
	
	# Find the index of this player_id in the sorted list
	var index = player_ids.find(player_id)
	if index == -1:
		index = 0
	
	index = index % spawn_positions.size()
	return spawn_positions[index]
