extends BuildingBase

# House building - increases population capacity

const POPULATION_PROVIDED = 5
const HOUSE_COST = {"wood": 50}

func _ready():
	building_name = "House"
	max_health = 500
	vision_range = 10.0

	super._ready()

	setup_building_mesh()
	setup_navigation_obstacle()

	# Add population when constructed
	if is_constructed and multiplayer.is_server():
		add_population()

func setup_building_mesh():
	"""Create visual representation"""
	if not mesh_instance:
		return

	# Medium box for House (will replace with model later)
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(4, 4, 4)
	mesh_instance.mesh = box_mesh
	mesh_instance.position.y = 2.0

	# Apply player color
	apply_player_color()

func setup_navigation_obstacle():
	"""Configure navigation obstacle"""
	if not nav_obstacle:
		return

	await get_tree().physics_frame

	nav_obstacle.radius = 2.5
	nav_obstacle.height = 4.0
	nav_obstacle.position.y = 2.0
	nav_obstacle.avoidance_enabled = true
	nav_obstacle.use_3d_avoidance = true

func add_population():
	"""Add population capacity to player (server only)"""
	if not multiplayer.is_server():
		return

	ResourceManager.add_population_capacity(player_id, POPULATION_PROVIDED)
	print("House added ", POPULATION_PROVIDED, " population capacity for player ", player_id)

func remove_population():
	"""Remove population capacity when building destroyed"""
	if not multiplayer.is_server():
		return

	ResourceManager.remove_population_capacity(player_id, POPULATION_PROVIDED)
	print("House removed ", POPULATION_PROVIDED, " population capacity for player ", player_id)

func destroy():
	"""Override to remove population before destruction"""
	if multiplayer.is_server():
		remove_population()
	super.destroy()
