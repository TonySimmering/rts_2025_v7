extends BuildingBase

signal production_queue_changed(queue: Array)
signal unit_produced(unit: Node3D)

# Barracks building - produces military units

# Production settings
const SOLDIER_COST = {"gold": 60, "wood": 20}
const SOLDIER_TRAIN_TIME = 15.0  # seconds
const MAX_QUEUE_SIZE = 5
const BARRACKS_COST = {"wood": 150, "gold": 50}

# Production state
var production_queue: Array = []  # Array of {unit_type: String, progress: float, total_time: float}
var rally_point: Vector3 = Vector3.ZERO
var is_producing: bool = false

func _ready():
	building_name = "Barracks"
	max_health = 1200
	vision_range = 15.0

	super._ready()

	# Set initial rally point
	rally_point = global_position + Vector3(5, 0, 0)

	setup_building_mesh()
	setup_navigation_obstacle()

func _process(delta):
	if not multiplayer.is_server():
		return

	process_production(delta)

func setup_building_mesh():
	"""Create visual representation"""
	if not mesh_instance:
		return

	# Rectangular box for Barracks (will replace with model later)
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(6, 5, 6)
	mesh_instance.mesh = box_mesh
	mesh_instance.position.y = 2.5

	# Apply player color with darker tint (military building)
	apply_player_color()

func setup_navigation_obstacle():
	"""Configure navigation obstacle"""
	if not nav_obstacle:
		return

	await get_tree().physics_frame

	nav_obstacle.radius = 3.5
	nav_obstacle.height = 5.0
	nav_obstacle.position.y = 2.5
	nav_obstacle.avoidance_enabled = true
	nav_obstacle.use_3d_avoidance = true

# ============ UNIT PRODUCTION ============

func can_train_soldier() -> bool:
	"""Check if we can add soldier to queue"""
	if production_queue.size() >= MAX_QUEUE_SIZE:
		return false

	return ResourceManager.can_afford(player_id, SOLDIER_COST)

func train_soldier():
	"""Add soldier to production queue (called by UI)"""
	if not multiplayer.is_server():
		return

	if not can_train_soldier():
		print("Cannot train soldier: insufficient resources or queue full")
		return

	# Spend resources
	if not ResourceManager.spend_resources(player_id, SOLDIER_COST):
		return

	# Check population capacity
	if not ResourceManager.can_train_unit(player_id):
		print("Cannot train soldier: population limit reached")
		return

	# Add to queue
	var production_item = {
		"unit_type": "soldier",
		"progress": 0.0,
		"total_time": SOLDIER_TRAIN_TIME
	}

	production_queue.append(production_item)
	sync_production_queue.rpc(production_queue)

	print("Soldier added to production queue (", production_queue.size(), "/", MAX_QUEUE_SIZE, ")")

func process_production(delta: float):
	"""Process production queue (server only)"""
	if production_queue.is_empty():
		return

	# Process first item in queue
	var current = production_queue[0]
	current.progress += delta

	# Check if production complete
	if current.progress >= current.total_time:
		complete_production()
	else:
		# Sync progress periodically
		sync_production_queue.rpc(production_queue)

func complete_production():
	"""Spawn completed unit (server only)"""
	if production_queue.is_empty():
		return

	var completed = production_queue.pop_front()

	match completed.unit_type:
		"soldier":
			spawn_soldier()

	sync_production_queue.rpc(production_queue)
	print("Unit production complete. Queue size: ", production_queue.size())

func spawn_soldier():
	"""Spawn a soldier unit at rally point"""
	var spawn_pos = get_spawn_position()

	# Use spawn manager's network spawn function
	# TODO: Create soldier unit and spawn function
	# For now we'll skip this as soldiers don't exist yet
	var spawn_manager = get_tree().root.get_node_or_null("Game/SpawnManager")
	if spawn_manager:
		# var soldier_count = get_tree().get_nodes_in_group("player_%d_units" % player_id).size()
		# spawn_manager.spawn_soldier_networked.rpc(player_id, building_id * 100 + soldier_count, spawn_pos)
		print("Barracks would spawn soldier for player ", player_id, " at ", spawn_pos)
		# For MVP, we'll just add to population count
		ResourceManager.add_population_used(player_id, 1)
	else:
		push_error("SpawnManager not found!")

func get_spawn_position() -> Vector3:
	"""Calculate spawn position near building"""
	var spawn_offset = Vector3(6, 0, 0)  # Spawn to the right of building
	var spawn_pos = global_position + spawn_offset

	# Validate with NavMesh
	var nav_map = get_world_3d().navigation_map
	var closest = NavigationServer3D.map_get_closest_point(nav_map, spawn_pos)

	return closest

@rpc("authority", "call_local", "reliable")
func sync_production_queue(queue_data: Array):
	"""Sync production queue to all clients"""
	production_queue = queue_data
	production_queue_changed.emit(production_queue)

func get_rally_point() -> Vector3:
	return rally_point

func set_rally_point(point: Vector3):
	"""Set where produced units should move after spawning"""
	rally_point = point
	print("Rally point set to: ", rally_point)

# ============ SELECTION OVERRIDES ============

func select():
	super.select()
	# TODO: Show production UI

func deselect():
	super.deselect()
	# TODO: Hide production UI

func get_production_progress() -> float:
	"""Get progress of current production (0.0 to 1.0)"""
	if production_queue.is_empty():
		return 0.0

	var current = production_queue[0]
	return current.progress / current.total_time

func get_queue_size() -> int:
	return production_queue.size()
