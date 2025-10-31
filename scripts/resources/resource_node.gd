extends StaticBody3D

enum ResourceType {
	GOLD,
	WOOD,
	STONE
}

@export var resource_type: ResourceType = ResourceType.GOLD
@export var starting_amount: int = 1000
@export var gather_rate: int = 10  # Amount per gather cycle
@export var resource_seed: int = 0  # Seed for procedural generation

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var label_3d: Label3D = $Label3D
@onready var nav_obstacle: NavigationObstacle3D = $NavigationObstacle3D

var current_amount: int = 0
var gatherers: Array = []  # Workers currently gathering
var procedural_rock: ProceduralRock = null  # Reference to procedural rock mesh

# Visual settings per type
const TYPE_COLORS = {
	ResourceType.GOLD: Color(1.0, 0.84, 0.0),      # Gold
	ResourceType.WOOD: Color(0.55, 0.27, 0.07),    # Brown
	ResourceType.STONE: Color(0.5, 0.5, 0.5)       # Gray
}

const TYPE_NAMES = {
	ResourceType.GOLD: "Gold",
	ResourceType.WOOD: "Wood",
	ResourceType.STONE: "Stone"
}

func _ready():
	add_to_group("resource_nodes")
	current_amount = starting_amount
	setup_visuals()
	setup_navigation_obstacle()
	
	collision_layer = 4
	collision_mask = 2  # Enable collision with units
	
	if label_3d:
		label_3d.visible = false
	
	set_multiplayer_authority(1)

func setup_visuals():
	# Different visuals based on type
	if resource_type == ResourceType.WOOD:
		# Trees are taller and thinner
		var cylinder_mesh = CylinderMesh.new()
		cylinder_mesh.top_radius = 0.3
		cylinder_mesh.bottom_radius = 0.4
		cylinder_mesh.height = 4.0
		mesh_instance.mesh = cylinder_mesh
		mesh_instance.position.y = 2.0

		# Collision for tree
		var shape = CylinderShape3D.new()
		shape.radius = 0.4
		shape.height = 4.0
		collision_shape.shape = shape
		collision_shape.position.y = 2.0
	else:
		# Stone and Gold: Use procedural rock generation
		_setup_procedural_rock()

func _setup_procedural_rock():
	"""Setup procedural rock mesh for stone and gold resources"""
	# Create ProceduralRock instance
	procedural_rock = ProceduralRock.new()

	# Determine rock type
	var rock_type = ProceduralRock.RockType.STONE
	if resource_type == ResourceType.GOLD:
		rock_type = ProceduralRock.RockType.GOLD

	# Generate rock with seed
	var seed_value = resource_seed if resource_seed != 0 else randi()
	procedural_rock.generate_rock(rock_type, seed_value, 1.5)

	# Replace the default MeshInstance3D with our procedural rock
	if mesh_instance:
		# Remove old mesh instance
		var parent = mesh_instance.get_parent()
		var old_position = mesh_instance.position
		mesh_instance.queue_free()

		# Add procedural rock
		procedural_rock.name = "MeshInstance3D"
		procedural_rock.position = Vector3(0, 0.5, 0)  # Center the rock
		parent.add_child(procedural_rock)

		# Update reference
		mesh_instance = procedural_rock

	# Setup collision shape using the procedural rock
	var shape = procedural_rock.get_collision_shape()
	collision_shape.shape = shape
	collision_shape.position.y = 0.5

func setup_navigation_obstacle():
	"""Configure NavigationObstacle3D based on resource type"""
	if not nav_obstacle:
		return

	# Wait for navigation system to be ready
	await get_tree().physics_frame

	if resource_type == ResourceType.WOOD:
		# Trees: tall cylinder
		nav_obstacle.radius = 0.5  # Slightly larger than visual for clearance
		nav_obstacle.height = 4.0
		nav_obstacle.position.y = 2.0  # Center of cylinder
	else:
		# Stone/Gold: box-like
		nav_obstacle.radius = 1.0  # Approximate radius for 1.5x1.5 box
		nav_obstacle.height = 1.0
		nav_obstacle.position.y = 0.5  # Center of box

	# Enable navigation avoidance for better pathfinding
	# This allows units to see and plan around resources in advance
	# Physical collision still provides hard barriers
	nav_obstacle.avoidance_enabled = true
	nav_obstacle.use_3d_avoidance = true

	# Configure avoidance layers
	# Resources are on avoidance layer 1, same as buildings
	nav_obstacle.set_avoidance_layer_value(1, true)

	print("  Resource navigation obstacle configured for ", TYPE_NAMES[resource_type], " - radius: ", nav_obstacle.radius, ", height: ", nav_obstacle.height)

func can_gather() -> bool:
	return current_amount > 0

func start_gathering(worker: Node):
	"""Called when worker starts gathering"""
	if not gatherers.has(worker):
		gatherers.append(worker)
		print(TYPE_NAMES[resource_type], " node: Worker started gathering (", gatherers.size(), " gatherers)")

func stop_gathering(worker: Node):
	"""Called when worker stops gathering"""
	if gatherers.has(worker):
		gatherers.erase(worker)
		print(TYPE_NAMES[resource_type], " node: Worker stopped gathering (", gatherers.size(), " gatherers)")

func gather(worker: Node) -> Dictionary:
	"""
	Attempt to gather resources
	Returns: { success: bool, amount: int, resource_type: String }
	"""
	if not multiplayer.is_server():
		return {"success": false, "amount": 0, "resource_type": ""}
	
	if current_amount <= 0:
		return {"success": false, "amount": 0, "resource_type": ""}
	
	var amount_gathered = min(gather_rate, current_amount)
	current_amount -= amount_gathered
	
	# Sync depletion to all clients
	update_amount.rpc(current_amount)
	
	if current_amount <= 0:
		print(TYPE_NAMES[resource_type], " node depleted!")
		deplete.rpc()
	
	return {
		"success": true,
		"amount": amount_gathered,
		"resource_type": TYPE_NAMES[resource_type].to_lower()
	}

@rpc("authority", "call_local", "reliable")
func update_amount(new_amount: int):
	"""Sync resource amount to all clients (no longer updates label)"""
	current_amount = new_amount

@rpc("authority", "call_local", "reliable")
func deplete():
	"""Remove this resource node when depleted"""
	# Notify gatherers
	for worker in gatherers:
		if is_instance_valid(worker):
			worker.resource_depleted()
	
	queue_free()

func get_resource_type_string() -> String:
	return TYPE_NAMES[resource_type].to_lower()
