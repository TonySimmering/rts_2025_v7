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
			place_building()
			get_viewport().set_input_as_handled()

	# Handle mouse motion to update ghost position
	if event is InputEventMouseMotion:
		update_ghost_position(event.position)

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

	# Add visual components
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	current_ghost.add_child(mesh_instance)

	# Add to scene
	get_tree().root.add_child(current_ghost)

	# Initialize ghost
	current_ghost.set_building_type(building_type)

func update_ghost_position(mouse_pos: Vector2):
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

		# Check for snapping to nearby buildings
		if current_ghost.check_for_snapping(player_id):
			current_ghost.apply_snapping()
		else:
			current_ghost.update_position(world_pos, terrain)

func rotate_ghost(angle_delta: float):
	"""Rotate the ghost building"""
	if current_ghost:
		current_ghost.rotate_building(angle_delta)
		# Re-validate after rotation
		if terrain:
			current_ghost.update_position(current_ghost.global_position, terrain)

func place_building():
	"""Place the building and create construction site"""
	if not current_ghost or not current_ghost.is_valid_placement:
		return

	var placement_data = current_ghost.get_placement_data()

	# Check resources again (in case they changed)
	if not can_afford_building(placement_data.building_type):
		print("Cannot afford building: ", placement_data.building_type)
		return

	# Spend resources on server
	if multiplayer.is_server():
		var cost = BUILDING_COSTS[placement_data.building_type]
		if not ResourceManager.spend_resources(player_id, cost):
			print("Failed to spend resources for building")
			return

	# Create construction site
	create_construction_site(placement_data)

	# Issue build commands to workers
	issue_build_commands(placement_data)

	# Emit signal
	building_placed.emit(placement_data.position, placement_data.rotation, placement_data.building_type)

	# Continue placement mode for queue building
	# Create new ghost for next placement
	create_ghost(placement_data.building_type)

	print("Building placed: ", placement_data.building_type, " at ", placement_data.position)

func create_construction_site(placement_data: Dictionary):
	"""Create a construction site at the placement position"""
	if not multiplayer.is_server():
		# Send RPC to server to create construction site
		create_construction_site_rpc.rpc_id(1, placement_data)
		return

	# Flatten terrain at building position
	if terrain:
		var flatten_radius = placement_data.size.x / 2.0 + 1.0
		terrain.flatten_terrain_at_position(placement_data.position, flatten_radius, 2.0)

	# Load construction site scene
	var site_scene_path = "res://scripts/construction_site.gd"
	var site = Node3D.new()
	site.set_script(load(site_scene_path))

	# Setup construction site
	site.player_id = player_id
	site.site_id = generate_site_id()
	site.building_type = placement_data.building_type
	site.building_size = placement_data.size
	site.target_rotation = placement_data.rotation
	site.construction_time = CONSTRUCTION_TIMES[placement_data.building_type]
	site.construction_cost = BUILDING_COSTS[placement_data.building_type]

	# Add visual components to site
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	site.add_child(mesh_instance)

	var nav_obstacle = NavigationObstacle3D.new()
	nav_obstacle.name = "NavigationObstacle3D"
	site.add_child(nav_obstacle)

	# Set position and rotation
	site.global_position = placement_data.position
	site.global_rotation.y = placement_data.rotation

	# Add to game world
	get_tree().root.get_node("Game").add_child(site, true)

	print("Construction site created at ", placement_data.position)

@rpc("any_peer", "call_local", "reliable")
func create_construction_site_rpc(placement_data: Dictionary):
	"""RPC to create construction site on server"""
	create_construction_site(placement_data)

func issue_build_commands(placement_data: Dictionary):
	"""Issue build commands to selected workers"""
	var queue_mode = true  # Always queue build commands

	for worker in selected_workers:
		if is_instance_valid(worker) and worker.is_multiplayer_authority():
			if not worker.has_method("queue_command"):
				continue

			var command = UnitCommand.new(UnitCommand.CommandType.BUILD)
			command.target_position = placement_data.position
			command.building_type = placement_data.building_type
			command.metadata = placement_data

			# Queue the build command
			worker.queue_command(command, queue_mode)

	print("Build commands issued to ", selected_workers.size(), " workers")

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
