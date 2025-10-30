extends StaticBody3D
class_name BuildingBase

signal building_selected(building: BuildingBase)
signal building_deselected(building: BuildingBase)
signal health_changed(current: int, max: int)
signal destroyed()

# Network sync
@export var player_id: int = 0
@export var building_id: int = 0

# Building properties
@export var building_name: String = "Building"
@export var max_health: int = 1000
@export var vision_range: float = 15.0

# Visual references
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var selection_indicator: Node3D = $SelectionIndicator
@onready var nav_obstacle: NavigationObstacle3D = $NavigationObstacle3D

# State
var current_health: int = 0
var is_selected: bool = false
var is_constructed: bool = true  # For future construction system

func _ready():
	add_to_group("buildings")
	add_to_group("player_%d_buildings" % player_id)

	current_health = max_health
	set_multiplayer_authority(player_id)

	setup_collision()
	setup_navigation_obstacle()
	apply_player_color()

	if selection_indicator:
		selection_indicator.visible = false

	print("Building ready: ", building_name, " | Player: ", player_id, " | ID: ", building_id)

func setup_collision():
	"""Configure collision layers for buildings"""
	collision_layer = 8  # Layer 4 (bit 3) - buildings
	collision_mask = 0   # Buildings don't need to detect collisions

func setup_navigation_obstacle():
	"""Configure NavigationObstacle3D for pathfinding avoidance"""
	if not nav_obstacle:
		return

	# Wait for navigation system to be ready
	await get_tree().physics_frame

	# Disable dynamic avoidance for static buildings
	# Buildings should rely on physical collision only
	# NavigationObstacle3D avoidance is for moving obstacles
	nav_obstacle.avoidance_enabled = false
	nav_obstacle.use_3d_avoidance = false

	# Units will pathfind naturally and be stopped by physical collision
	print("  Building collision configured - radius: ", nav_obstacle.radius, ", height: ", nav_obstacle.height)

func apply_player_color():
	"""Apply player color to building (simple team colors)"""
	if not mesh_instance:
		return
	
	var player_colors = [
		Color(0.8, 0.2, 0.2),  # Player 1: Red
		Color(0.2, 0.2, 0.8),  # Player 2: Blue
		Color(0.2, 0.8, 0.2),  # Player 3: Green
		Color(0.8, 0.8, 0.2),  # Player 4: Yellow
	]
	
	var color_index = (player_id - 1) % player_colors.size()
	var player_color = player_colors[color_index]
	
	var material = StandardMaterial3D.new()
	material.albedo_color = player_color
	mesh_instance.set_surface_override_material(0, material)

func select():
	"""Called when building is selected"""
	is_selected = true
	if selection_indicator:
		selection_indicator.visible = true
	building_selected.emit(self)

func deselect():
	"""Called when building is deselected"""
	is_selected = false
	if selection_indicator:
		selection_indicator.visible = false
	building_deselected.emit(self)

func take_damage(amount: int, attacker_id: int = 0):
	"""Apply damage to building (server authority)"""
	if not multiplayer.is_server():
		return
	
	current_health = max(0, current_health - amount)
	sync_health.rpc(current_health)
	
	if current_health <= 0:
		destroy()

@rpc("authority", "call_local", "reliable")
func sync_health(new_health: int):
	"""Sync health to all clients"""
	current_health = new_health
	health_changed.emit(current_health, max_health)

func destroy():
	"""
	Destroy this building.

	NOTE: Terrain modifications (flattening and dirt texture) are NOT reverted when a building
	is destroyed. The terrain remains modified for the entire runtime session. This is intentional
	to allow players to rebuild on the same flattened ground without re-flattening.
	"""
	if not multiplayer.is_server():
		return

	print("🏚️ Building destroyed: ", building_name, " (terrain modifications remain)")
	destroyed.emit()
	destroy_rpc.rpc()

@rpc("authority", "call_local", "reliable")
func destroy_rpc():
	"""Destroy building on all clients"""
	queue_free()

func get_dropoff_position() -> Vector3:
	"""Get position where units should dropoff resources (override in subclasses)"""
	return global_position

func can_dropoff_resources() -> bool:
	"""Whether this building accepts resource dropoffs (override in subclasses)"""
	return false

func get_rally_point() -> Vector3:
	"""Get rally point for produced units (override in subclasses)"""
	return global_position + Vector3(5, 0, 0)
