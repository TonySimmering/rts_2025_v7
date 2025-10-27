extends StaticBody3D

enum ResourceType {
	GOLD,
	WOOD,
	STONE
}

@export var resource_type: ResourceType = ResourceType.GOLD
@export var starting_amount: int = 1000
@export var gather_rate: int = 10  # Amount per gather cycle

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var label_3d: Label3D = $Label3D

var current_amount: int = 0
var gatherers: Array = []  # Workers currently gathering

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
	update_label()
	
	# Only server manages depletion
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
		# Stone and Gold are smaller rocks/deposits
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(1.5, 1.0, 1.5)
		mesh_instance.mesh = box_mesh
		mesh_instance.position.y = 0.5
		
		# Collision for rocks
		var shape = BoxShape3D.new()
		shape.size = Vector3(1.5, 1.0, 1.5)
		collision_shape.shape = shape
		collision_shape.position.y = 0.5
	
	# Apply color based on type
	var material = StandardMaterial3D.new()
	material.albedo_color = TYPE_COLORS[resource_type]
	mesh_instance.set_surface_override_material(0, material)

func update_label():
	if label_3d:
		label_3d.text = TYPE_NAMES[resource_type] + "\n" + str(current_amount)
		# Position label above the resource
		if resource_type == ResourceType.WOOD:
			label_3d.position.y = 4.5  # Above tree
		else:
			label_3d.position.y = 1.5  # Above rock/deposit

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
	"""Sync resource amount to all clients"""
	current_amount = new_amount
	update_label()

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
