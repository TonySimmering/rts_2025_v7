extends StaticBody3D
class_name ConstructionSite

signal construction_complete()
signal construction_progress_changed(progress: float)

# Network sync
@export var player_id: int = 0
@export var site_id: int = 0

# Construction properties
@export var building_type: String = ""  # "town_center", "house", "barracks"
@export var construction_time: float = 30.0  # seconds
@export var max_builders: int = 5  # Maximum workers that can build simultaneously

# Visual references
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var progress_indicator: Node3D = $ProgressIndicator
@onready var nav_obstacle: NavigationObstacle3D = $NavigationObstacle3D

# State
var construction_progress: float = 0.0  # 0.0 to construction_time
var active_builders: Array = []  # Array of worker references
var target_position: Vector3 = Vector3.ZERO
var target_rotation: float = 0.0  # Y-axis rotation in radians
var building_size: Vector3 = Vector3(4, 4, 4)  # Size of the final building

# Construction costs (stored for refund on cancel)
var construction_cost: Dictionary = {}

func _ready():
	add_to_group("construction_sites")
	add_to_group("player_%d_construction_sites" % player_id)

	set_multiplayer_authority(player_id)

	setup_collision()
	setup_construction_mesh()
	setup_navigation_obstacle()

	print("Construction site ready: ", building_type, " | Player: ", player_id, " | ID: ", site_id)

func _process(delta):
	if not multiplayer.is_server():
		return

	# Construction happens only when workers are building
	if active_builders.size() > 0:
		# Build speed increases with more workers (diminishing returns)
		var build_rate = calculate_build_rate()
		construction_progress += delta * build_rate

		# Update progress visually
		update_construction_visual()
		sync_progress.rpc(construction_progress)

		# Check if construction complete
		if construction_progress >= construction_time:
			complete_construction()

func setup_collision():
	"""Configure collision layers for construction sites"""
	collision_layer = 8  # Layer 4 (bit 3) - buildings
	collision_mask = 0   # Construction sites don't need to detect collisions

func setup_construction_mesh():
	"""Create visual representation of construction site"""
	if not mesh_instance:
		return

	# Create a semi-transparent box to represent the building under construction
	var box_mesh = BoxMesh.new()
	box_mesh.size = building_size
	mesh_instance.mesh = box_mesh
	mesh_instance.position.y = building_size.y / 2.0

	# Apply semi-transparent material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.8, 0.8, 0.3)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.set_surface_override_material(0, material)

func setup_navigation_obstacle():
	"""Configure navigation obstacle"""
	if not nav_obstacle:
		return

	await get_tree().physics_frame

	nav_obstacle.radius = building_size.x / 2.0
	nav_obstacle.height = building_size.y
	nav_obstacle.position.y = building_size.y / 2.0
	nav_obstacle.avoidance_enabled = true
	nav_obstacle.use_3d_avoidance = true

func calculate_build_rate() -> float:
	"""Calculate build rate based on number of workers with diminishing returns"""
	var builder_count = active_builders.size()
	if builder_count == 0:
		return 0.0

	# Diminishing returns: 1 worker = 1x, 2 = 1.5x, 3 = 1.8x, 4 = 2.0x, 5 = 2.2x
	var efficiency = sqrt(float(builder_count))
	return efficiency

func add_builder(worker: Node) -> bool:
	"""Add a worker to construction (server only)"""
	if not multiplayer.is_server():
		return false

	if active_builders.size() >= max_builders:
		return false

	if worker in active_builders:
		return false

	active_builders.append(worker)
	print("Worker added to construction. Total builders: ", active_builders.size())
	return true

func remove_builder(worker: Node):
	"""Remove a worker from construction"""
	if worker in active_builders:
		active_builders.erase(worker)
		print("Worker removed from construction. Total builders: ", active_builders.size())

func update_construction_visual():
	"""Update visual progress indicator"""
	if not mesh_instance:
		return

	var progress_percent = construction_progress / construction_time

	# Update alpha based on progress
	var material = mesh_instance.get_surface_override_material(0)
	if material:
		var alpha = 0.3 + (progress_percent * 0.7)  # 0.3 to 1.0
		material.albedo_color.a = alpha

func complete_construction():
	"""Complete construction and spawn the actual building (server only)"""
	if not multiplayer.is_server():
		return

	print("Construction complete: ", building_type)

	# Spawn the actual building
	spawn_building()

	# Emit completion signal
	construction_complete.emit()

	# Destroy construction site
	complete_construction_rpc.rpc()

func spawn_building():
	"""Spawn the final building at this location"""
	var building_scenes = {
		"town_center": "res://scenes/buildings/town_center.tscn",
		"house": "res://scenes/buildings/house.tscn",
		"barracks": "res://scenes/buildings/barracks.tscn"
	}

	var scene_path = building_scenes.get(building_type, "")
	if scene_path == "":
		push_error("Unknown building type: ", building_type)
		return

	# Load and instantiate building
	var building_scene = load(scene_path)
	if not building_scene:
		push_error("Failed to load building scene: ", scene_path)
		return

	var building = building_scene.instantiate()
	building.player_id = player_id
	building.building_id = site_id

	# Store position before adding to tree
	var spawn_position = global_position
	var spawn_rotation = target_rotation

	# Add to game world FIRST (Godot requirement)
	get_tree().root.get_node("Game").add_child(building, true)

	# THEN set position and rotation (after adding to tree)
	building.global_position = spawn_position
	building.global_rotation.y = spawn_rotation

	print("Building spawned: ", building_type, " at ", spawn_position)

@rpc("authority", "call_local", "reliable")
func sync_progress(progress: float):
	"""Sync construction progress to all clients"""
	construction_progress = progress
	update_construction_visual()
	construction_progress_changed.emit(progress / construction_time)

@rpc("authority", "call_local", "reliable")
func complete_construction_rpc():
	"""Remove construction site on all clients"""
	queue_free()

func cancel_construction():
	"""Cancel construction and refund resources (server only)"""
	if not multiplayer.is_server():
		return

	# Refund a percentage of resources based on progress
	var refund_percent = 1.0 - (construction_progress / construction_time)
	for resource_type in construction_cost:
		var refund_amount = int(construction_cost[resource_type] * refund_percent)
		if refund_amount > 0:
			ResourceManager.add_resource(player_id, resource_type, refund_amount)

	print("Construction cancelled. Refunded ", refund_percent * 100, "% of resources")

	cancel_construction_rpc.rpc()

@rpc("authority", "call_local", "reliable")
func cancel_construction_rpc():
	"""Cancel construction on all clients"""
	queue_free()

func get_progress_percent() -> float:
	"""Get construction progress as percentage (0.0 to 1.0)"""
	return construction_progress / construction_time

func is_in_build_range(unit_position: Vector3) -> bool:
	"""Check if unit is close enough to build"""
	const BUILD_RANGE = 5.0
	return global_position.distance_to(unit_position) <= BUILD_RANGE
