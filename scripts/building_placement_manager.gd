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

# Wall chain state
var is_wall_chain_mode: bool = false
var wall_chain_manager: WallChainManager = null
var wall_chain_ghosts: Array = []  # Visual ghosts for the chain

# References
var camera: Camera3D = null
var terrain: Node = null

# Building costs
const BUILDING_COSTS = {
	"town_center": {"wood": 400, "gold": 200},
	"house": {"wood": 50},
	"barracks": {"wood": 150, "gold": 50},
	"wall": {"wood": 10}
}

# Construction times
const CONSTRUCTION_TIMES = {
	"town_center": 60.0,
	"house": 20.0,
	"barracks": 30.0,
	"wall": 5.0
}

func _ready():
	# Initialize wall chain manager
	wall_chain_manager = WallChainManager.new()
	add_child(wall_chain_manager)

func set_camera(cam: Camera3D):
	camera = cam
	if wall_chain_manager:
		wall_chain_manager.set_camera(cam)

func set_terrain(terr: Node):
	terrain = terr
	if wall_chain_manager:
		wall_chain_manager.set_terrain(terr)

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
		elif event.keycode == KEY_TAB:
			toggle_snapping()  # Toggle snapping with TAB key
			get_viewport().set_input_as_handled()

	# Handle right-click to exit placement mode OR finish wall chain
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if is_wall_chain_mode:
			finish_wall_chain()
		else:
			end_placement_mode()
		get_viewport().set_input_as_handled()

	# Handle left-click to place building OR add wall segment
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if current_ghost and current_ghost.is_valid_placement:
			if is_wall_chain_mode:
				add_wall_segment()
			else:
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

	# Check if this is a wall (enable chain mode)
	if building_type == "wall":
		is_wall_chain_mode = true
		wall_chain_ghosts.clear()
		if wall_chain_manager:
			wall_chain_manager.clear_chain()
		print("Wall chain mode activated")

	create_ghost(building_type)

	print("Placement mode started: ", building_type)
	placement_mode_started.emit(building_type)

func end_placement_mode():
	"""Exit building placement mode"""
	if current_ghost:
		current_ghost.queue_free()
		current_ghost = null

	# Clean up wall chain
	if is_wall_chain_mode:
		cleanup_wall_chain()
		is_wall_chain_mode = false

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

		# Wall chain mode - use chain manager to calculate next segment
		if is_wall_chain_mode and wall_chain_manager.is_chaining:
			var next_segment = wall_chain_manager.update_next_segment_position(world_pos)

			current_ghost.global_position = next_segment.position
			current_ghost.rotation.y = next_segment.rotation

			# Update validation based on path availability
			current_ghost.is_valid_placement = next_segment.is_valid
			current_ghost.update_placement_validity(next_segment.is_valid)
		# Normal placement mode
		elif current_ghost.check_for_snapping(player_id, world_pos, delta, terrain):
			# Position already applied by snap controller (with terrain clamping)
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

func toggle_snapping():
	"""Toggle magnetic snapping on/off"""
	if current_ghost:
		current_ghost.toggle_snapping()

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
		# Wait a frame for the construction site to be fully ready
		await get_tree().process_frame
		assign_workers_to_site_rpc.rpc(site.get_path(), placement_data.assigned_workers, queue_mode)

@rpc("any_peer", "call_local", "reliable")
func assign_workers_to_site_rpc(site_path: NodePath, worker_paths: Array, queue_mode: bool):
	"""Assign workers to a construction site (can be called from anywhere)"""
	var site = get_node_or_null(site_path)
	if not site or not is_instance_valid(site):
		print("Construction site not found: ", site_path)
		return

	var assigned_count = 0
	for worker_data in worker_paths:
		var worker = null

		# Handle both NodePath and actual worker references
		if worker_data is NodePath:
			worker = get_node_or_null(worker_data)
		elif typeof(worker_data) == TYPE_OBJECT:
			worker = worker_data

		if not worker or not is_instance_valid(worker):
			continue

		if not worker.is_multiplayer_authority():
			continue

		if not worker.has_method("queue_command"):
			continue

		var command = UnitCommand.new(UnitCommand.CommandType.BUILD)
		command.target_position = site.global_position
		command.building_type = site.building_type
		command.metadata = {
			"position": site.global_position,
			"rotation": site.target_rotation,
			"size": site.building_size,
			"building_type": site.building_type
		}

		# Queue or replace based on queue_mode
		worker.queue_command(command, queue_mode)
		assigned_count += 1

	print("Assigned ", assigned_count, " workers to construction site (Queue: ", queue_mode, ")")

func assign_workers_to_construction_site(site: Node, workers: Array, queue_mode: bool = false):
	"""Helper function to assign workers to a specific construction site"""
	if not site or not is_instance_valid(site):
		return

	var worker_paths = []
	for worker in workers:
		if is_instance_valid(worker):
			worker_paths.append(worker)

	assign_workers_to_site_rpc.rpc(site.get_path(), worker_paths, queue_mode)

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

# Wall chain construction functions

func add_wall_segment():
	"""Add a wall segment to the current chain"""
	if not is_wall_chain_mode or not current_ghost:
		return

	var placement_data = current_ghost.get_placement_data()

	# Start chain with first segment
	if not wall_chain_manager.is_chaining:
		wall_chain_manager.start_chain(placement_data.position)
	else:
		# Add segment to chain
		wall_chain_manager.add_segment(placement_data.position, placement_data.rotation)

	# Create a visual ghost for this segment
	create_chain_ghost(placement_data.position, placement_data.rotation)

	print("Wall segment added to chain (", wall_chain_manager.get_chain_segments().size(), " segments)")

func create_chain_ghost(position: Vector3, rotation: float):
	"""Create a visual ghost for a placed chain segment"""
	var ghost_script = load("res://scripts/building_ghost.gd")
	var ghost = ghost_script.new()

	# Add required child nodes
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	ghost.add_child(mesh_instance)

	var placement_indicator = MeshInstance3D.new()
	placement_indicator.name = "PlacementIndicator"
	ghost.add_child(placement_indicator)

	# Add to scene
	get_tree().root.add_child(ghost)

	# Initialize ghost
	ghost.set_building_type("wall")
	ghost.global_position = position
	ghost.rotation.y = rotation

	# Make it semi-transparent to show it's placed
	if ghost.mesh_instance:
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.5, 0.8, 0.5, 0.4)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost.mesh_instance.set_surface_override_material(0, material)

	wall_chain_ghosts.append(ghost)

func finish_wall_chain():
	"""Finish the wall chain and place all segments"""
	if not is_wall_chain_mode:
		return

	var segments = wall_chain_manager.get_chain_segments()

	if segments.is_empty():
		print("No wall segments to place")
		cleanup_wall_chain()
		end_placement_mode()
		return

	print("Finishing wall chain with ", segments.size(), " segments")

	# Place each segment as a construction site
	for segment in segments:
		place_wall_segment(segment.position, segment.rotation)

	# Clean up and end chain mode
	cleanup_wall_chain()
	end_placement_mode()

func place_wall_segment(position: Vector3, rotation: float):
	"""Place a single wall segment"""
	var placement_data = {
		"position": position,
		"rotation": rotation,
		"building_type": "wall",
		"size": Vector3(4, 4, 0.5)
	}

	# Send to server if not authority
	if not multiplayer.is_server():
		request_place_building_rpc.rpc_id(1, placement_data, player_id)
	else:
		server_create_construction_site(placement_data, player_id)

func cleanup_wall_chain():
	"""Clean up all wall chain ghosts"""
	for ghost in wall_chain_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()

	wall_chain_ghosts.clear()

	if wall_chain_manager:
		wall_chain_manager.clear_chain()
		wall_chain_manager.end_chain()
