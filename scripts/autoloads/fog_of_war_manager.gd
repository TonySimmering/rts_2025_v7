extends Node

## Fog of War Manager
## Manages visibility state for all players in the game
## Three states: UNEXPLORED (black fog), EXPLORED (grey fog), VISIBLE (clear)

enum VisibilityState {
	UNEXPLORED = 0,  # Never seen - black fog
	EXPLORED = 1,    # Seen before but not currently visible - grey fog
	VISIBLE = 2      # Currently visible - no fog
}

# Map dimensions (must match terrain size)
var map_width: int = 128
var map_height: int = 128

# Per-player visibility grids
# Key: player_id (int), Value: 2D array of VisibilityState
var player_visibility: Dictionary = {}

# Fog of war enabled/disabled
var fog_enabled: bool = true

# Cache for vision providers (units and buildings)
var vision_providers: Array = []


func _ready() -> void:
	print("FogOfWarManager initialized")


## Initialize fog of war for a specific player
func initialize_player(player_id: int) -> void:
	if player_id in player_visibility:
		return

	# Create 2D visibility grid initialized to UNEXPLORED
	var grid: Array = []
	for y in range(map_height):
		var row: Array = []
		row.resize(map_width)
		row.fill(VisibilityState.UNEXPLORED)
		grid.append(row)

	player_visibility[player_id] = grid
	print("Initialized fog of war for player ", player_id)


## Set map dimensions (call this from terrain)
func set_map_dimensions(width: int, height: int) -> void:
	map_width = width
	map_height = height
	print("Fog of War map dimensions set to: ", width, "x", height)


## Update visibility for all players based on their units and buildings
func update_visibility() -> void:
	if not fog_enabled:
		return

	# First pass: decay all VISIBLE tiles to EXPLORED
	for player_id in player_visibility.keys():
		var grid = player_visibility[player_id]
		for y in range(map_height):
			for x in range(map_width):
				if grid[y][x] == VisibilityState.VISIBLE:
					grid[y][x] = VisibilityState.EXPLORED

	# Second pass: add vision from all units and buildings
	_update_vision_from_entities()


## Update vision from units and buildings
func _update_vision_from_entities() -> void:
	var building_count = 0
	var unit_count = 0

	# Process all buildings
	for building in get_tree().get_nodes_in_group("buildings"):
		if building.has_method("get_player_id") and building.has_method("get_vision_range"):
			var player_id = building.get_player_id()
			var vision_range = building.get_vision_range()
			var pos = building.global_position

			if player_id >= 0 and player_id in player_visibility:
				_reveal_circle(player_id, pos.x, pos.z, vision_range)
				building_count += 1

	# Process all units
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.has_method("get_player_id") and unit.has_method("get_vision_range"):
			var player_id = unit.get_player_id()
			var vision_range = unit.get_vision_range()
			var pos = unit.global_position

			if player_id >= 0 and player_id in player_visibility:
				_reveal_circle(player_id, pos.x, pos.z, vision_range)
				unit_count += 1

	# Debug output occasionally
	if Engine.get_process_frames() % 300 == 0:
		print("FogOfWarManager: Processing vision from %d buildings and %d units" % [building_count, unit_count])


## Reveal a circular area around a world position
func _reveal_circle(player_id: int, world_x: float, world_z: float, radius: float) -> void:
	if not player_id in player_visibility:
		return

	var grid = player_visibility[player_id]

	# Convert world coordinates to grid coordinates
	var center_x = int(world_x)
	var center_y = int(world_z)

	# Calculate bounds
	var min_x = max(0, int(center_x - radius))
	var max_x = min(map_width - 1, int(center_x + radius))
	var min_y = max(0, int(center_y - radius))
	var max_y = min(map_height - 1, int(center_y + radius))

	# Reveal tiles in circle
	var radius_squared = radius * radius
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx = x - center_x
			var dy = y - center_y
			var dist_squared = dx * dx + dy * dy

			if dist_squared <= radius_squared:
				grid[y][x] = VisibilityState.VISIBLE


## Get visibility state at world position for a player
func get_visibility_at(player_id: int, world_x: float, world_z: float) -> VisibilityState:
	if not fog_enabled:
		return VisibilityState.VISIBLE

	if not player_id in player_visibility:
		return VisibilityState.UNEXPLORED

	var grid_x = int(world_x)
	var grid_y = int(world_z)

	# Check bounds
	if grid_x < 0 or grid_x >= map_width or grid_y < 0 or grid_y >= map_height:
		return VisibilityState.UNEXPLORED

	return player_visibility[player_id][grid_y][grid_x]


## Check if position is visible for a player
func is_visible(player_id: int, world_x: float, world_z: float) -> bool:
	return get_visibility_at(player_id, world_x, world_z) == VisibilityState.VISIBLE


## Check if position is explored (seen before) for a player
func is_explored(player_id: int, world_x: float, world_z: float) -> bool:
	var state = get_visibility_at(player_id, world_x, world_z)
	return state == VisibilityState.EXPLORED or state == VisibilityState.VISIBLE


## Get visibility data for a specific player as a flat array (for shader/texture)
func get_visibility_data(player_id: int) -> PackedByteArray:
	if not player_id in player_visibility:
		return PackedByteArray()

	var data = PackedByteArray()
	data.resize(map_width * map_height)

	var grid = player_visibility[player_id]
	var index = 0
	for y in range(map_height):
		for x in range(map_width):
			# Convert enum to byte: 0 = unexplored, 127 = explored, 255 = visible
			match grid[y][x]:
				VisibilityState.UNEXPLORED:
					data[index] = 0
				VisibilityState.EXPLORED:
					data[index] = 127
				VisibilityState.VISIBLE:
					data[index] = 255
			index += 1

	return data


## Clear all fog for a player (debug/cheat)
func reveal_all(player_id: int) -> void:
	if not player_id in player_visibility:
		return

	var grid = player_visibility[player_id]
	for y in range(map_height):
		for x in range(map_width):
			grid[y][x] = VisibilityState.VISIBLE


## Reset fog for a player
func reset_fog(player_id: int) -> void:
	if not player_id in player_visibility:
		return

	var grid = player_visibility[player_id]
	for y in range(map_height):
		for x in range(map_width):
			grid[y][x] = VisibilityState.UNEXPLORED


## Enable or disable fog of war
func set_fog_enabled(enabled: bool) -> void:
	fog_enabled = enabled
