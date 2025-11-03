extends MeshInstance3D

## Fog of War Overlay
## Creates a visual overlay mesh that displays fog of war
## Updates each frame based on player visibility data

@export var player_id: int = 0
@export var map_width: int = 128
@export var map_height: int = 128
@export var update_interval: float = 0.1  # Update fog every 0.1 seconds

var visibility_texture: ImageTexture
var fog_material: ShaderMaterial
var update_timer: float = 0.0


func _ready() -> void:
	_create_fog_mesh()
	_create_fog_material()


## Create a plane mesh covering the entire map
func _create_fog_mesh() -> void:
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(map_width, map_height)
	plane_mesh.subdivide_width = 1
	plane_mesh.subdivide_depth = 1

	mesh = plane_mesh

	# Position the fog plane slightly above terrain (y=1) to avoid z-fighting
	position = Vector3(map_width / 2.0, 1.0, map_height / 2.0)
	rotation.x = -PI / 2  # Rotate to be horizontal


## Create the fog material with shader
func _create_fog_material() -> void:
	# Load the fog of war shader
	var shader = load("res://shaders/fog_of_war.gdshader")
	if not shader:
		push_error("Failed to load fog of war shader")
		return

	# Create shader material
	fog_material = ShaderMaterial.new()
	fog_material.shader = shader

	# Create visibility texture
	var image = Image.create(map_width, map_height, false, Image.FORMAT_R8)
	image.fill(Color(0, 0, 0, 1))  # Start with black (unexplored)

	visibility_texture = ImageTexture.create_from_image(image)

	# Set shader parameters
	fog_material.set_shader_parameter("visibility_map", visibility_texture)
	fog_material.set_shader_parameter("map_size", Vector2(map_width, map_height))
	fog_material.set_shader_parameter("unexplored_color", Color(0.0, 0.0, 0.0, 1.0))
	fog_material.set_shader_parameter("explored_color", Color(0.0, 0.0, 0.0, 0.5))
	fog_material.set_shader_parameter("visible_alpha", 0.0)

	# Apply material
	material_override = fog_material

	# Enable transparency rendering
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	update_timer += delta

	# Update fog at intervals to reduce performance impact
	if update_timer >= update_interval:
		update_timer = 0.0
		_update_visibility_texture()


## Update the visibility texture from FogOfWarManager
func _update_visibility_texture() -> void:
	if not FogOfWarManager:
		return

	if not visibility_texture:
		return

	# Get visibility data from fog of war manager
	var visibility_data = FogOfWarManager.get_visibility_data(player_id)

	if visibility_data.size() == 0:
		return

	# Verify data size matches expected size
	var expected_size = map_width * map_height
	if visibility_data.size() != expected_size:
		push_error("Fog of War: Visibility data size mismatch. Expected %d, got %d" % [expected_size, visibility_data.size()])
		return

	# Create image from visibility data
	var image = Image.create_from_data(map_width, map_height, false, Image.FORMAT_R8, visibility_data)

	# Update texture
	visibility_texture.update(image)


## Set which player's fog to display
func set_player_id(new_player_id: int) -> void:
	player_id = new_player_id


## Set map dimensions
func set_map_dimensions(width: int, height: int) -> void:
	map_width = width
	map_height = height

	# Recreate mesh and material with new dimensions
	_create_fog_mesh()
	_create_fog_material()
