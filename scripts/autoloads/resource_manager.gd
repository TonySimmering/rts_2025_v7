extends Node

signal resources_changed(player_id: int, resources: Dictionary)
signal population_changed(player_id: int, used: int, capacity: int)

# Resource storage per player
var player_resources: Dictionary = {}  # player_id -> { gold: 0, wood: 0, stone: 0 }

# Population storage per player
var player_population_capacity: Dictionary = {}  # player_id -> capacity
var player_population_used: Dictionary = {}  # player_id -> used

# Starting resources
const STARTING_GOLD = 500
const STARTING_WOOD = 200
const STARTING_STONE = 200
const STARTING_POPULATION_CAPACITY = 10  # From Town Center

func _ready():
	# Initialize resources when players join
	NetworkManager.player_connected.connect(_on_player_connected)

func _on_player_connected(peer_id: int, _player_info: Dictionary):
	initialize_player_resources(peer_id)

func initialize_player_resources(player_id: int):
	"""Set starting resources for a player"""
	if not player_resources.has(player_id):
		player_resources[player_id] = {
			"gold": STARTING_GOLD,
			"wood": STARTING_WOOD,
			"stone": STARTING_STONE
		}
		print("Initialized resources for player ", player_id, ": ", player_resources[player_id])
		resources_changed.emit(player_id, player_resources[player_id])

	# Initialize population
	if not player_population_capacity.has(player_id):
		player_population_capacity[player_id] = STARTING_POPULATION_CAPACITY
		player_population_used[player_id] = 0
		print("Initialized population for player ", player_id, ": 0/", STARTING_POPULATION_CAPACITY)
		population_changed.emit(player_id, 0, STARTING_POPULATION_CAPACITY)

func add_resource(player_id: int, resource_type: String, amount: int):
	"""Add resources to a player (server authority)"""
	if not multiplayer.is_server():
		return
	
	if not player_resources.has(player_id):
		initialize_player_resources(player_id)
	
	player_resources[player_id][resource_type] += amount
	
	# Sync to all clients
	sync_resources.rpc(player_id, player_resources[player_id])
	
	print("Player ", player_id, " +", amount, " ", resource_type, " (Total: ", player_resources[player_id][resource_type], ")")

@rpc("authority", "call_local", "reliable")
func sync_resources(player_id: int, resources: Dictionary):
	"""Sync resources from server to all clients"""
	player_resources[player_id] = resources
	resources_changed.emit(player_id, resources)

func get_player_resources(player_id: int) -> Dictionary:
	"""Get resource dictionary for a player"""
	if not player_resources.has(player_id):
		return {"gold": 0, "wood": 0, "stone": 0}
	return player_resources[player_id]

func can_afford(player_id: int, cost: Dictionary) -> bool:
	"""Check if player can afford a cost"""
	var resources = get_player_resources(player_id)
	for resource_type in cost:
		if resources.get(resource_type, 0) < cost[resource_type]:
			return false
	return true

func spend_resources(player_id: int, cost: Dictionary) -> bool:
	"""Deduct resources from player (server authority)"""
	if not multiplayer.is_server():
		return false
	
	if not can_afford(player_id, cost):
		return false
	
	for resource_type in cost:
		player_resources[player_id][resource_type] -= cost[resource_type]
	
	sync_resources.rpc(player_id, player_resources[player_id])
	return true

# ============ POPULATION SYSTEM ============

func add_population_capacity(player_id: int, amount: int):
	"""Add population capacity (e.g., from building a House)"""
	if not multiplayer.is_server():
		return

	if not player_population_capacity.has(player_id):
		player_population_capacity[player_id] = 0

	player_population_capacity[player_id] += amount
	sync_population.rpc(player_id, player_population_used.get(player_id, 0), player_population_capacity[player_id])

	print("Player ", player_id, " +", amount, " population capacity (Total: ", player_population_capacity[player_id], ")")

func remove_population_capacity(player_id: int, amount: int):
	"""Remove population capacity (e.g., from destroying a House)"""
	if not multiplayer.is_server():
		return

	if not player_population_capacity.has(player_id):
		return

	player_population_capacity[player_id] = max(0, player_population_capacity[player_id] - amount)
	sync_population.rpc(player_id, player_population_used.get(player_id, 0), player_population_capacity[player_id])

	print("Player ", player_id, " -", amount, " population capacity (Total: ", player_population_capacity[player_id], ")")

func add_population_used(player_id: int, amount: int):
	"""Add to population used (e.g., training a unit)"""
	if not multiplayer.is_server():
		return

	if not player_population_used.has(player_id):
		player_population_used[player_id] = 0

	player_population_used[player_id] += amount
	sync_population.rpc(player_id, player_population_used[player_id], player_population_capacity.get(player_id, 0))

	print("Player ", player_id, " +", amount, " population used (", player_population_used[player_id], "/", player_population_capacity.get(player_id, 0), ")")

func remove_population_used(player_id: int, amount: int):
	"""Remove from population used (e.g., unit dies)"""
	if not multiplayer.is_server():
		return

	if not player_population_used.has(player_id):
		return

	player_population_used[player_id] = max(0, player_population_used[player_id] - amount)
	sync_population.rpc(player_id, player_population_used[player_id], player_population_capacity.get(player_id, 0))

	print("Player ", player_id, " -", amount, " population used (", player_population_used[player_id], "/", player_population_capacity.get(player_id, 0), ")")

func can_train_unit(player_id: int) -> bool:
	"""Check if player has population space to train a unit"""
	var used = player_population_used.get(player_id, 0)
	var capacity = player_population_capacity.get(player_id, 0)
	return used < capacity

func get_population(player_id: int) -> Dictionary:
	"""Get population data for a player"""
	return {
		"used": player_population_used.get(player_id, 0),
		"capacity": player_population_capacity.get(player_id, 0)
	}

@rpc("authority", "call_local", "reliable")
func sync_population(player_id: int, used: int, capacity: int):
	"""Sync population from server to all clients"""
	player_population_used[player_id] = used
	player_population_capacity[player_id] = capacity
	population_changed.emit(player_id, used, capacity)
