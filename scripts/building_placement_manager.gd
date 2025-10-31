extends Node
class_name BuildingPlacementManager

signal placement_mode_started(building_type: String)
signal placement_mode_ended()
signal building_placed(position: Vector3, rotation: float, building_type: String)

# Placement state
var is_placing: bool = false
var current_ghost: BuildingGhost = null
var building_queue: Array = []  # Queue of buildings to place
var selected_workers: Array = []  # Workers that will build
var player_id: int = 1

# References
var camera: Camera3D = null
var terrain: Node = null

# Building costs
const BUILDING_COSTS = {
	"town_center": {"wood": 400, "gold": 200},
	"house": {"wood": 50},
	"barracks": {"wood": 150, "gold": 50}
}

# Construction times
const CONSTRUCTION_TIMES = {
	"town_center": 60.0,
	"house": 20.0,
	"barracks": 30.0
}

func _ready():
	pass

func set_camera(cam: Camera3D):
	camera = cam

func set_terrain(terr: Node):
	terrain = terr

func set_player_id(pid: int):
	player_id = pid

func _input(event):
	if not is_placing:
		return

	# Handle rotation keys (J and K)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_J:
			rotate_ghost(-PI/4)  # -45 degrees
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_K:
			rotate_ghost(PI/4)  # +45 degrees
			get_viewport().set_input_as_handled()

	# Handle right-click to exit placement mode
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		end_placement_mode()
		get_viewport().set_input_as_handled()

	# Handle left-click to place building
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if current_ghost and current_ghost.is_valid_placement:
			var queue_mode = Input.is_key_pressed(KEY_SHIFT)
			place_building(queue_mode)
			get_viewport().set_input_as_handled()

func start_placement_mode(building_type: String, workers: Array):
	"""Start building placement mode"""
	if not can_afford_building(building_type):
		print("Cannot afford building: ", building_type)
		return

	is_placing = true
	selected_workers = workers
	building_queue = [building_type]  # Start with one building

	create_ghost(building_type)

	print("Placement mode started: ", building_type)
	placement_mode_started.emit(building_type)

func end_placement_mode():
	"""Exit building placement mode"""
	if current_ghost:
		current_ghost.queue_free()
		current_ghost = null

	is_placing = false
	building_queue.clear()

	print("Placement mode ended")
	placement_mode_ended.emit()

func create_ghost(building_type: String):
	"""Create a new ghost for placement"""
	if current_ghost:
		current_ghost.queue_free()

	# Load and instantiate the BuildingGhost script
	var ghost_script = load("res://scripts/building_ghost.gd")
	current_ghost = ghost_script.new()

	# Add required child nodes BEFORE adding to tree (for @onready references)
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	current_ghost.add_child(mesh_instance)

	var placement_indicator = MeshInstance3D.new()
	placement_indicator.name = "PlacementIndicator"
	current_ghost.add_child(placement_indicator)

	# Add to scene
	get_tree().root.add_child(current_ghost)

	# Initialize ghost
	current_ghost.set_building_type(building_type)

func _process(delta):
	"""Update ghost position each frame for smooth snapping"""
	if is_placing and current_ghost:
		var mouse_pos = get_viewport().get_mouse_position()
		update_ghost_position(mouse_pos, delta)

func update_ghost_position(mouse_pos: Vector2, delta: float = 0.0):
	"""Update ghost position based on mouse position"""
	if not current_ghost or not camera or not terrain:
		return

	# Raycast to terrain
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0

	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)

	if result:
		var world_pos = result.position

		# Check for snapping to nearby buildings (magnetic behavior)
		if current_ghost.check_for_snapping(player_id, world_pos, delta):
			# Position already applied by snap controller
			pass
		else:
			current_ghost.update_position(world_pos, terrain)

func rotate_ghost(angle_delta: float):
	"""Rotate the ghost building"""
	if current_ghost:
		current_ghost.rotate_building(angle_delta)
		# Re-validate after rotation
		if terrain:
			current_ghost.update_position(current_ghost.global_position, terrain)

func place_building(queue_mode: bool = false):
	"""Place the building and create construction site"""
	if not current_ghost or not current_ghost.is_valid_placement:
		return

	var placement_data = current_ghost.get_placement_data()

	# Check resources locally (for immediate feedback)
	if not can_afford_building(placement_data.building_type):
		print("Cannot afford building: ", placement_data.building_type)
		return

	# Store queue mode for later use
	placement_data["queue_mode"] = queue_mode

	# Convert workers to NodePaths for RPC serialization
	var worker_paths = []
	for worker in selected_workers:
		if is_instance_valid(worker):
			worker_paths.append(worker.get_path())
	placement_data["assigned_workers"] = worker_paths

	# Request construction site creation from server
	if not multiplayer.is_server():
		request_place_building_rpc.rpc_id(1, placement_data, player_id)
	else:
		# Server creates directly
		server_create_construction_site(placement_data, player_id)

	# Emit signal
	building_placed.emit(placement_data.position, placement_data.rotation, placement_data.building_type)

	# Continue placement mode for queue building
	# Create new ghost for next placement
	create_ghost(placement_data.building_type)

	print("Building placed: ", placement_data.building_type, " at ", placement_data.position, " (Queue: ", queue_mode, ")")

@rpc("any_peer", "call_remote", "reliable")
func request_place_building_rpc(placement_data: Dictionary, requester_player_id: int):
	"""Client requests server to create construction site"""
	if not multiplayer.is_server():
		return

	server_create_construction_site(placement_data, requester_player_id)

func server_create_construction_site(placement_data: Dictionary, owner_player_id: int):
	"""Server-side construction site creation with resource validation"""
	if not multiplayer.is_server():
		return

	# Validate and spend resources on server
	var cost = BUILDING_COSTS[placement_data.building_type]
	if not ResourceManager.spend_resources(owner_player_id, cost):
		print("Server: Cannot afford building for player ", owner_player_id)
		return

	# Create construction site
	create_construction_site_internal(placement_data, owner_player_id)

func create_construction_site_internal(placement_data: Dictionary, owner_player_id: int):
	"""Internal function to create construction site (server only)"""
	# Flatten terrain at building position
	if terrain:
		var flatten_radius = placement_data.size.x / 2.0 + 1.0
		await terrain.flatten_terrain_at_position(placement_data.position, flatten_radius, 2.0)

	# Load and instantiate construction site script
	var site_script = load("res://scripts/construction_site.gd")
	var site = site_script.new()

	# Add required child nodes BEFORE adding to tree (for @onready references)
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	site.add_child(mesh_instance)

	var progress_indicator = Node3D.new()
	progress_indicator.name = "ProgressIndicator"
	site.add_child(progress_indicator)

	var nav_obstacle = NavigationObstacle3D.new()
	nav_obstacle.name = "NavigationObstacle3D"
	site.add_child(nav_obstacle)

	# Add collision shape for physical blocking
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var box_shape = BoxShape3D.new()
	box_shape.size = placement_data.size
	collision_shape.shape = box_shape
	collision_shape.position.y = placement_data.size.y / 2.0  # Center the collision
	site.add_child(collision_shape)

	# Setup construction site properties
	site.player_id = owner_player_id
	site.site_id = generate_site_id()
	site.building_type = placement_data.building_type
	site.building_size = placement_data.size
	site.target_rotation = placement_data.rotation
	site.construction_time = CONSTRUCTION_TIMES[placement_data.building_type]
	site.construction_cost = BUILDING_COSTS[placement_data.building_type]

	# Add to game world FIRST
	get_tree().root.get_node("Game").add_child(site, true)

	# THEN set position and rotation (after adding to tree)
	site.global_position = placement_data.position
	site.global_rotation.y = placement_data.rotation

	print("Construction site created at ", placement_data.position, " for player ", owner_player_id)

	# Auto-assign workers if they were selected when placing
	if placement_data.has("assigned_workers"):
		var queue_mode = placement_data.get("queue_mode", false)
		await get_tree().process_frame
		var worker_paths: Array = []
		for worker_entry in placement_data.assigned_workers:
			if worker_entry is NodePath:
				worker_paths.append(worker_entry)
			elif typeof(worker_entry) == TYPE_OBJECT and is_instance_valid(worker_entry):
				worker_paths.append(worker_entry.get_path())

		if not worker_paths.is_empty():
			CommandManager.request_build_command(worker_paths, site.get_path(), queue_mode)

func assign_workers_to_construction_site(site: Node, workers: Array, queue_mode: bool = false):
        """Helper function to assign workers to a specific construction site"""
        if not site or not is_instance_valid(site):
                return

	var worker_paths: Array = []
	for worker in workers:
		if is_instance_valid(worker):
			worker_paths.append(worker.get_path())

	if not worker_paths.is_empty():
		CommandManager.request_build_command(worker_paths, site.get_path(), queue_mode)

func can_afford_building(building_type: String) -> bool:
	"""Check if player can afford the building"""
	if not BUILDING_COSTS.has(building_type):
		return false

	var cost = BUILDING_COSTS[building_type]
	return ResourceManager.can_afford(player_id, cost)

func generate_site_id() -> int:
	"""Generate unique construction site ID"""
	return int(Time.get_ticks_msec() % 100000)

func get_building_cost(building_type: String) -> Dictionary:
	"""Get building cost"""
	return BUILDING_COSTS.get(building_type, {})

func get_construction_time(building_type: String) -> float:
	"""Get construction time"""
	return CONSTRUCTION_TIMES.get(building_type, 30.0)
