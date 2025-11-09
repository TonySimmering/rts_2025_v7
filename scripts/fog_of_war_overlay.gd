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

# Curtain system to prevent seeing under the fog
var curtain_mesh_instance: MeshInstance3D
var curtain_height: float = 50.0  # How far down the curtain extends


func _ready() -> void:
	_create_fog_mesh()
	_create_fog_material()
	_create_curtain_mesh()


## Create a plane mesh covering the entire map
func _create_fog_mesh() -> void:
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(map_width, map_height)
	plane_mesh.subdivide_width = 1
	plane_mesh.subdivide_depth = 1

	mesh = plane_mesh

	# Position the fog plane at the terrain height
	# Note: PlaneMesh faces upward by default in Godot, no rotation needed
	position = Vector3(map_width / 2.0, 8.0, map_height / 2.0)  # Elevated to render over terrain
	rotation = Vector3.ZERO  # No rotation - plane faces up by default


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

	# Set material render priority to render after terrain
	fog_material.render_priority = 1

	# Configure rendering settings
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	print("Fog material created with texture size: ", map_width, "x", map_height)


## Create curtain mesh that drops down from fog plane
func _create_curtain_mesh() -> void:
	curtain_mesh_instance = MeshInstance3D.new()
	add_child(curtain_mesh_instance)

	# Use the same material as the fog plane
	curtain_mesh_instance.material_override = fog_material

	# Configure rendering settings
	curtain_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	curtain_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	print("Curtain mesh instance created")


## Update curtain geometry based on visibility data
func _update_curtain_geometry(visibility_data: PackedByteArray) -> void:
	if not curtain_mesh_instance:
		return

	if visibility_data.size() != map_width * map_height:
		return

	# Create arrays for mesh generation
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()

	# Cell size is 1x1 in world units
	var cell_size = 1.0
	var top_y = 0.0  # Relative to parent (fog plane is at position.y in world)
	var bottom_y = -curtain_height  # Bottom of curtain, relative to parent

	# Parent position offset (fog plane is centered at map_width/2, map_height/2)
	var offset_x = -map_width / 2.0
	var offset_z = -map_height / 2.0

	# Generate vertical walls for unexplored tiles
	# Create walls on all four sides of each unexplored tile for complete coverage
	for y in range(map_height):
		for x in range(map_width):
			var index = y * map_width + x
			var visibility = visibility_data[index]

			# Only create curtains for unexplored areas (value 0)
			if visibility == 0:
				# Local coordinates relative to parent
				var local_x = float(x) + offset_x
				var local_z = float(y) + offset_z

				# Check neighbors to avoid duplicate walls (only create wall if neighbor is not also unexplored)
				var north_unexplored = y > 0 and visibility_data[(y-1) * map_width + x] == 0
				var south_unexplored = y < map_height - 1 and visibility_data[(y+1) * map_width + x] == 0
				var west_unexplored = x > 0 and visibility_data[y * map_width + (x-1)] == 0
				var east_unexplored = x < map_width - 1 and visibility_data[y * map_width + (x+1)] == 0

				# North wall (at min Z edge) - visible from north, normal points -Z
				if not north_unexplored:
					_add_wall_quad(vertices, normals, uvs, indices,
						Vector3(local_x, top_y, local_z),                    # top-left
						Vector3(local_x, bottom_y, local_z),                 # bottom-left
						Vector3(local_x + cell_size, bottom_y, local_z),     # bottom-right
						Vector3(local_x + cell_size, top_y, local_z),        # top-right
						Vector3(0, 0, -1), x, y)

				# South wall (at max Z edge) - visible from south, normal points +Z
				if not south_unexplored:
					_add_wall_quad(vertices, normals, uvs, indices,
						Vector3(local_x + cell_size, top_y, local_z + cell_size),  # top-right
						Vector3(local_x + cell_size, bottom_y, local_z + cell_size), # bottom-right
						Vector3(local_x, bottom_y, local_z + cell_size),            # bottom-left
						Vector3(local_x, top_y, local_z + cell_size),               # top-left
						Vector3(0, 0, 1), x, y)

				# West wall (at min X edge) - visible from west, normal points -X
				if not west_unexplored:
					_add_wall_quad(vertices, normals, uvs, indices,
						Vector3(local_x, top_y, local_z + cell_size),       # top-left
						Vector3(local_x, bottom_y, local_z + cell_size),    # bottom-left
						Vector3(local_x, bottom_y, local_z),                # bottom-right
						Vector3(local_x, top_y, local_z),                   # top-right
						Vector3(-1, 0, 0), x, y)

				# East wall (at max X edge) - visible from east, normal points +X
				if not east_unexplored:
					_add_wall_quad(vertices, normals, uvs, indices,
						Vector3(local_x + cell_size, top_y, local_z),                  # top-left
						Vector3(local_x + cell_size, bottom_y, local_z),               # bottom-left
						Vector3(local_x + cell_size, bottom_y, local_z + cell_size),   # bottom-right
						Vector3(local_x + cell_size, top_y, local_z + cell_size),      # top-right
						Vector3(1, 0, 0), x, y)

	# Create mesh from arrays
	if vertices.size() > 0:
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices

		var array_mesh = ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		curtain_mesh_instance.mesh = array_mesh

		print("Curtain mesh updated with ", vertices.size(), " vertices")
	else:
		curtain_mesh_instance.mesh = null


## Helper function to add a quad (wall) to the mesh arrays
func _add_wall_quad(vertices: PackedVector3Array, normals: PackedVector3Array,
					uvs: PackedVector2Array, indices: PackedInt32Array,
					v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3,
					grid_x: int, grid_y: int) -> void:
	var base_index = vertices.size()

	# Add vertices
	vertices.append(v0)
	vertices.append(v1)
	vertices.append(v2)
	vertices.append(v3)

	# Add normals
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)

	# Add UVs based on grid position (for shader to sample visibility texture correctly)
	# Use grid coordinates to map to the visibility texture
	var uv_x = float(grid_x) / float(map_width)
	var uv_y = float(grid_y) / float(map_height)
	uvs.append(Vector2(uv_x, uv_y))
	uvs.append(Vector2(uv_x, uv_y))
	uvs.append(Vector2(uv_x, uv_y))
	uvs.append(Vector2(uv_x, uv_y))

	# Add indices for two triangles (quad) with correct counter-clockwise winding
	# When viewed from the front (where normal points), vertices should go counter-clockwise
	indices.append(base_index)
	indices.append(base_index + 3)
	indices.append(base_index + 2)

	indices.append(base_index)
	indices.append(base_index + 2)
	indices.append(base_index + 1)


func _process(delta: float) -> void:
	update_timer += delta

	# Update fog at intervals to reduce performance impact
	if update_timer >= update_interval:
		update_timer = 0.0
		_update_visibility_texture()


## Update the visibility texture from FogOfWarManager
func _update_visibility_texture() -> void:
	if not FogOfWarManager:
		print_debug("FogOfWarManager not available")
		return

	if not visibility_texture:
		print_debug("Visibility texture not initialized")
		return

	# Get visibility data from fog of war manager
	var visibility_data = FogOfWarManager.get_visibility_data(player_id)

	if visibility_data.size() == 0:
		print_debug("No visibility data for player ", player_id)
		return

	# Verify data size matches expected size
	var expected_size = map_width * map_height
	if visibility_data.size() != expected_size:
		push_error("Fog of War: Visibility data size mismatch. Expected %d, got %d" % [expected_size, visibility_data.size()])
		return

	# Count visibility states for debugging
	var unexplored_count = 0
	var explored_count = 0
	var visible_count = 0
	for byte in visibility_data:
		if byte == 0:
			unexplored_count += 1
		elif byte == 127:
			explored_count += 1
		elif byte == 255:
			visible_count += 1

	# Print visibility stats occasionally
	if Engine.get_process_frames() % 300 == 0:  # Every ~5 seconds at 60fps
		print("Fog of War: Unexplored: %d, Explored: %d, Visible: %d" % [unexplored_count, explored_count, visible_count])

	# Create image from visibility data
	var image = Image.create_from_data(map_width, map_height, false, Image.FORMAT_R8, visibility_data)

	# Update texture
	visibility_texture.update(image)

	# Update curtain geometry to match visibility
	_update_curtain_geometry(visibility_data)


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

	# Recreate curtain if it exists
	if curtain_mesh_instance:
		curtain_mesh_instance.queue_free()
	_create_curtain_mesh()
