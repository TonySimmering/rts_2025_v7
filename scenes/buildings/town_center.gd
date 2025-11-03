extends BuildingBase

signal production_queue_changed(queue: Array)
signal unit_produced(unit: Node3D)

# Production settings
const WORKER_COST = {"gold": 50}
const WORKER_TRAIN_TIME = 10.0  # seconds
const MAX_QUEUE_SIZE = 5

# Production state
var production_queue: Array = []  # Array of {unit_type: String, progress: float, total_time: float}
var rally_point: Vector3 = Vector3.ZERO
var rally_resource_node: Node = null  # Resource node at rally point (if any)
var is_producing: bool = false

# Rally point visual
var rally_point_indicator: Node3D = null

# Dropoff settings
const DROPOFF_RANGE: float = 6.0

func _ready():
	building_name = "Town Center"
	max_health = 2000
	vision_range = 20.0

	super._ready()

	# Set initial rally point
	rally_point = global_position + Vector3(5, 0, 0)

	# Add initial population capacity (Town Center provides 10 population)
	if is_constructed and multiplayer.is_server():
		ResourceManager.add_population_capacity(player_id, 10)

	setup_building_mesh()
	setup_navigation_obstacle()

func _exit_tree():
	"""Clean up rally point indicator when building is destroyed"""
	if rally_point_indicator and is_instance_valid(rally_point_indicator):
		rally_point_indicator.queue_free()
		rally_point_indicator = null

func _process(delta):
	if not multiplayer.is_server():
		return
	
	process_production(delta)

func setup_building_mesh():
	"""Create visual representation"""
	if not mesh_instance:
		return
	
	# Large box for Town Center (will replace with model later)
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(8, 6, 8)
	mesh_instance.mesh = box_mesh
	mesh_instance.position.y = 3.0
	
	# Apply player color
	apply_player_color()

func setup_navigation_obstacle():
	"""Configure navigation obstacle"""
	if not nav_obstacle:
		return
	
	await get_tree().physics_frame
	
	nav_obstacle.radius = 5.0  # Larger than visual for clearance
	nav_obstacle.height = 6.0
	nav_obstacle.position.y = 3.0
	nav_obstacle.avoidance_enabled = true
	nav_obstacle.use_3d_avoidance = true

# ============ RESOURCE DROPOFF ============

func can_dropoff_resources() -> bool:
	return true

func get_dropoff_position() -> Vector3:
	"""Return position where workers should stand to dropoff"""
	return global_position

func is_in_dropoff_range(unit_position: Vector3) -> bool:
	"""Check if unit is close enough to dropoff"""
	return global_position.distance_to(unit_position) <= DROPOFF_RANGE

func accept_resources(worker: Node, resources: Dictionary) -> bool:
	"""Accept resources from worker (server only)"""
	if not multiplayer.is_server():
		return false
	
	# Award resources to building owner
	for resource_type in resources:
		var amount = resources[resource_type]
		if amount > 0:
			ResourceManager.add_resource(player_id, resource_type, amount)
			print("Town Center accepted ", amount, " ", resource_type, " from worker (Player ", player_id, ")")
	
	return true

# ============ UNIT PRODUCTION ============

func can_train_worker() -> bool:
	"""Check if we can add worker to queue"""
	if production_queue.size() >= MAX_QUEUE_SIZE:
		return false
	
	return ResourceManager.can_afford(player_id, WORKER_COST)

func train_worker():
	"""Add worker to production queue (called by UI)"""
	if not multiplayer.is_server():
		return
	
	if not can_train_worker():
		print("Cannot train worker: insufficient resources or queue full")
		return
	
	# Spend resources
	if not ResourceManager.spend_resources(player_id, WORKER_COST):
		return
	
	# Add to queue
	var production_item = {
		"unit_type": "worker",
		"progress": 0.0,
		"total_time": WORKER_TRAIN_TIME
	}
	
	production_queue.append(production_item)
	sync_production_queue.rpc(production_queue)
	
	print("Worker added to production queue (", production_queue.size(), "/", MAX_QUEUE_SIZE, ")")

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
		"worker":
			spawn_worker()
	
	sync_production_queue.rpc(production_queue)
	print("Unit production complete. Queue size: ", production_queue.size())

func spawn_worker():
	"""Spawn a worker unit at rally point"""
	# Check population capacity
	if not ResourceManager.can_train_unit(player_id):
		print("Cannot spawn worker: population limit reached")
		return

	var spawn_pos = get_spawn_position()

	# Use spawn manager's network spawn function
	var spawn_manager = get_tree().root.get_node_or_null("Game/SpawnManager")
	if spawn_manager:
		var worker_count = get_tree().get_nodes_in_group("player_%d_units" % player_id).size()
		spawn_manager.spawn_unit_networked.rpc(player_id, building_id * 100 + worker_count, spawn_pos)

		# Add to population used
		ResourceManager.add_population_used(player_id, 1)

		# Issue rally point command to the worker after spawning
		await get_tree().create_timer(0.1).timeout
		_issue_rally_command_to_new_worker()

		print("Town Center spawned worker for player ", player_id)
	else:
		push_error("SpawnManager not found!")

func _issue_rally_command_to_new_worker():
	"""Issue move/gather command to the most recently spawned worker"""
	# Find the most recently spawned worker
	var workers = get_tree().get_nodes_in_group("player_%d_units" % player_id)
	if workers.is_empty():
		return

	# Get the last worker (most recently added)
	var worker = workers[workers.size() - 1]

	# Only issue command if we control this worker
	if not worker.is_multiplayer_authority():
		return

	# Create appropriate command based on rally point
	var command = null

	if rally_resource_node and is_instance_valid(rally_resource_node):
		# Rally point is on a resource - issue gather command
		command = UnitCommand.new(UnitCommand.CommandType.GATHER)
		command.target_entity = rally_resource_node
		command.target_position = rally_point
		print("Worker auto-gathering at rally point: ", rally_resource_node.get_resource_type_string())
	else:
		# Regular rally point - issue move command
		command = UnitCommand.new(UnitCommand.CommandType.MOVE)
		command.target_position = rally_point
		print("Worker moving to rally point: ", rally_point)

	# Queue the command (don't replace existing commands)
	if worker.has_method("queue_command"):
		worker.queue_command(command, false)

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
	rally_resource_node = null
	print("Rally point set to: ", rally_point)

	# Sync to all clients
	if multiplayer.is_server():
		sync_rally_point.rpc(rally_point, NodePath())

	update_rally_point_indicator()

func set_rally_point_with_resource(point: Vector3, resource_node: Node):
	"""Set rally point with optional resource node for auto-gathering"""
	rally_point = point
	rally_resource_node = resource_node

	var resource_path = NodePath()
	if resource_node and is_instance_valid(resource_node):
		resource_path = resource_node.get_path()
		print("Rally point set to resource: ", resource_node.get_resource_type_string())
	else:
		print("Rally point set to: ", rally_point)

	# Sync to all clients
	if multiplayer.is_server():
		sync_rally_point.rpc(rally_point, resource_path)

	update_rally_point_indicator()

@rpc("authority", "call_local", "reliable")
func sync_rally_point(point: Vector3, resource_path: NodePath):
	"""Sync rally point to all clients"""
	rally_point = point

	# Resolve resource node from path
	if resource_path != NodePath():
		rally_resource_node = get_node_or_null(resource_path)
	else:
		rally_resource_node = null

	update_rally_point_indicator()

func update_rally_point_indicator():
	"""Update or create visual indicator for rally point"""
	# Remove old indicator
	if rally_point_indicator and is_instance_valid(rally_point_indicator):
		rally_point_indicator.queue_free()
		rally_point_indicator = null

	# Create new indicator
	rally_point_indicator = Node3D.new()
	rally_point_indicator.name = "RallyPointIndicator"
	get_tree().root.add_child(rally_point_indicator)

	# Create flag pole
	var pole = MeshInstance3D.new()
	var pole_mesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.05
	pole_mesh.height = 2.0
	pole.mesh = pole_mesh
	pole.position = rally_point + Vector3(0, 1.0, 0)
	rally_point_indicator.add_child(pole)

	# Create flag
	var flag = MeshInstance3D.new()
	var flag_mesh = PlaneMesh.new()
	flag_mesh.size = Vector2(0.8, 0.5)
	flag.mesh = flag_mesh
	flag.position = rally_point + Vector3(0.4, 1.5, 0)

	# Apply player color to flag
	var material = StandardMaterial3D.new()
	material.albedo_color = _get_player_color()
	flag.set_surface_override_material(0, material)
	rally_point_indicator.add_child(flag)

	# Create ground circle
	var circle = MeshInstance3D.new()
	var circle_mesh = CylinderMesh.new()
	circle_mesh.top_radius = 0.5
	circle_mesh.bottom_radius = 0.5
	circle_mesh.height = 0.1
	circle.mesh = circle_mesh
	circle.position = rally_point + Vector3(0, 0.05, 0)

	var circle_material = StandardMaterial3D.new()
	circle_material.albedo_color = _get_player_color()
	circle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	circle_material.albedo_color.a = 0.3
	circle.set_surface_override_material(0, circle_material)
	rally_point_indicator.add_child(circle)

	# Only show if building is selected
	rally_point_indicator.visible = is_selected

func _get_player_color() -> Color:
	"""Get color for this building's player"""
	var player_colors = [
		Color(0.8, 0.2, 0.2),  # Player 1: Red
		Color(0.2, 0.2, 0.8),  # Player 2: Blue
		Color(0.2, 0.8, 0.2),  # Player 3: Green
		Color(0.8, 0.8, 0.2),  # Player 4: Yellow
	]
	var color_index = (player_id - 1) % player_colors.size()
	return player_colors[color_index]

# ============ SELECTION OVERRIDES ============

func select():
	super.select()
	# Show rally point indicator when selected
	if rally_point_indicator and is_instance_valid(rally_point_indicator):
		rally_point_indicator.visible = true

func deselect():
	super.deselect()
	# Hide rally point indicator when deselected
	if rally_point_indicator and is_instance_valid(rally_point_indicator):
		rally_point_indicator.visible = false

func get_production_progress() -> float:
	"""Get progress of current production (0.0 to 1.0)"""
	if production_queue.is_empty():
		return 0.0
	
	var current = production_queue[0]
	return current.progress / current.total_time

func get_queue_size() -> int:
	return production_queue.size()
