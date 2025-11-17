extends BuildingBase

# Wall building - defensive structure
# Can be chained together to form continuous walls

const WALL_WIDTH: float = 4.0
const WALL_HEIGHT: float = 4.0
const WALL_THICKNESS: float = 0.5

func _ready():
	building_name = "Wall"
	max_health = 500
	vision_range = 8.0

	super._ready()

	setup_building_mesh()
	apply_player_color()

func setup_building_mesh():
	if not mesh_instance:
		return

	# Thin rectangular box for wall segment
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(WALL_WIDTH, WALL_HEIGHT, WALL_THICKNESS)
	mesh_instance.mesh = box_mesh
	mesh_instance.position.y = WALL_HEIGHT / 2.0

	# Apply player color
	apply_player_color()

func get_wall_endpoints() -> Array:
	"""Returns the two endpoints of this wall segment in global coordinates"""
	var half_width = WALL_WIDTH / 2.0
	var forward = -global_transform.basis.z  # Forward direction

	var endpoint_a = global_position + forward * half_width
	var endpoint_b = global_position - forward * half_width

	return [endpoint_a, endpoint_b]
