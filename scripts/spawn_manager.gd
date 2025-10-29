extends Node

# Spawn settings
const WORKERS_PER_PLAYER = 3
const SPAWN_RADIUS = 8.0  # Spawn workers around Town Center
const TOWN_CENTER_FLATTEN_RADIUS = 6.0  # Flatten this much terrain
const FLATTEN_BLEND_PADDING = 3.0  # Blend dirt texture to grass

# Preload scenes
const WORKER_SCENE = preload("res://scenes/units/worker.tscn")
const TOWN_CENTER_SCENE = preload("res://scenes/buildings/town_center.tscn")

var terrain: Node3D = null
var spawned_units: Dictionary = {}  # player_id -> Array[units]
var spawned_buildings: Dictionary = {}  # player_id -> Array[buildings]

func spawn_town_centers():
	"""Spawn Town Center for each player (server only)"""
	if not multiplayer.is_server():
		return
	
	print("\n=== SPAWNING TOWN CENTERS ===")
	
	var map_size = Vector2(128, 128)
	
	for player_id in NetworkManager.players:
		var spawn_center = get_spawn_location_for_player(player_id, map_size)
		
		# Flatten terrain at spawn location BEFORE spawning the Town Center
		if terrain and terrain.has_method("flatten_terrain_at_position"):
			await terrain.flatten_terrain_at_position(spawn_center, TOWN_CENTER_FLATTEN_RADIUS, FLATTEN_BLEND_PADDING)
			print("  Terrain flattened for player ", player_id, " at ", spawn_center)
		
		spawn_town_center_networked.rpc(player_id, spawn_center)
		print("  Spawned Town Center for player ", player_id, " at ", spawn_center)
	
	print("=== TOWN CENTERS SPAWNED ===\n")

@rpc("authority", "call_local", "reliable")
func spawn_town_center_networked(player_id: int, spawn_pos: Vector3):
	"""Spawn a Town Center on all clients"""
	var town_center = TOWN_CENTER_SCENE.instantiate()
	town_center.global_position = spawn_pos
	town_center.player_id = player_id
	town_center.building_id = player_id  # Building ID = player ID for Town Center
	town_center.name = "TownCenter_P%d" % player_id
	
	get_tree().root.get_node("Game").add_child(town_center)
	
	if not spawned_buildings.has(player_id):
		spawned_buildings[player_id] = []
	spawned_buildings[player_id].append(town_center)
	
	print("  Town Center spawned for player ", player_id, " at ", spawn_pos)

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
		
		spawn_unit_networked.rpc(player_id, i, spawn_pos)

@rpc("authority", "call_local", "reliable")
func spawn_unit_networked(player_id: int, unit_id: int, spawn_pos: Vector3):
	"""Spawn a unit on all clients"""
	var worker = WORKER_SCENE.instantiate()
	worker.global_position = spawn_pos
	worker.player_id = player_id
	worker.unit_id = unit_id
	worker.name = "Unit_P%d_U%d" % [player_id, unit_id]
	
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
	
	# Get the height at this position from terrain
	var spawn_pos = spawn_positions[index]
	if terrain and terrain.has_method("get_height_at_position"):
		spawn_pos.y = terrain.get_height_at_position(spawn_pos)
	
	return spawn_pos
