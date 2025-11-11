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

	# Curtain dimensions
	var top_y = 0.0  # At fog plane level (relative to parent)
	var bottom_y = -curtain_height  # Drops down below terrain

	# Parent position offset (fog plane is centered)
	var offset_x = -map_width / 2.0
	var offset_z = -map_height / 2.0

	# Build vertical walls around unexplored regions
	# For each unexplored tile, check if neighbors are explored/visible and create walls
	for y in range(map_height):
		for x in range(map_width):
			var index = y * map_width + x
			var visibility = visibility_data[index]

			# Only create walls for unexplored tiles (value 0)
			if visibility == 0:
				var local_x = float(x) + offset_x
				var local_z = float(y) + offset_z

				# Check each neighbor - create wall if neighbor is NOT unexplored
				# North neighbor (y-1)
				if y == 0 or visibility_data[(y-1) * map_width + x] != 0:
					_add_north_wall(vertices, normals, uvs, indices, local_x, local_z, top_y, bottom_y, x, y)

				# South neighbor (y+1)
				if y == map_height - 1 or visibility_data[(y+1) * map_width + x] != 0:
					_add_south_wall(vertices, normals, uvs, indices, local_x, local_z, top_y, bottom_y, x, y)

				# West neighbor (x-1)
				if x == 0 or visibility_data[y * map_width + (x-1)] != 0:
					_add_west_wall(vertices, normals, uvs, indices, local_x, local_z, top_y, bottom_y, x, y)

				# East neighbor (x+1)
				if x == map_width - 1 or visibility_data[y * map_width + (x+1)] != 0:
					_add_east_wall(vertices, normals, uvs, indices, local_x, local_z, top_y, bottom_y, x, y)

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

		print("Curtain mesh updated with ", vertices.size(), " vertices and ", indices.size() / 3, " triangles")
	else:
		curtain_mesh_instance.mesh = null


## Add a wall on the north side of a tile (faces north, toward negative Z)
func _add_north_wall(vertices: PackedVector3Array, normals: PackedVector3Array,
					uvs: PackedVector2Array, indices: PackedInt32Array,
					x: float, z: float, top: float, bottom: float,
					grid_x: int, grid_y: int) -> void:
	var base_idx = vertices.size()

	# Vertices for north wall (looking from north toward wall, should see front face)
	# Counter-clockwise from viewer's perspective
	vertices.append(Vector3(x + 1.0, top, z))      # v0: top-right (from viewer)
	vertices.append(Vector3(x, top, z))            # v1: top-left
	vertices.append(Vector3(x, bottom, z))         # v2: bottom-left
	vertices.append(Vector3(x + 1.0, bottom, z))   # v3: bottom-right

	# Normal points north (toward viewer = negative Z)
	var n = Vector3(0, 0, -1)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	normals.append(n)

	# UVs
	var uv = Vector2(float(grid_x) / float(map_width), float(grid_y) / float(map_height))
	uvs.append(uv)
	uvs.append(uv)
	uvs.append(uv)
	uvs.append(uv)

	# Triangles: (v0,v1,v2) and (v0,v2,v3)
	indices.append(base_idx)
	indices.append(base_idx + 1)
	indices.append(base_idx + 2)
	indices.append(base_idx)
	indices.append(base_idx + 2)
	indices.append(base_idx + 3)


## Add a wall on the south side of a tile (faces south, toward positive Z)
func _add_south_wall(vertices: PackedVector3Array, normals: PackedVector3Array,
					uvs: PackedVector2Array, indices: PackedInt32Array,
					x: float, z: float, top: float, bottom: float,
					grid_x: int, grid_y: int) -> void:
	var base_idx = vertices.size()

	# Vertices for south wall (looking from south toward wall)
	vertices.append(Vector3(x, top, z + 1.0))            # v0: top-right (from viewer)
	vertices.append(Vector3(x + 1.0, top, z + 1.0))      # v1: top-left
	vertices.append(Vector3(x + 1.0, bottom, z + 1.0))   # v2: bottom-left
	vertices.append(Vector3(x, bottom, z + 1.0))         # v3: bottom-right

	# Normal points south (toward viewer = positive Z)
	var n = Vector3(0, 0, 1)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	normals.append(n)

	# UVs
	var uv = Vector2(float(grid_x) / float(map_width), float(grid_y) / float(map_height))
	uvs.append(uv)
	uvs.append(uv)
	uvs.append(uv)
	uvs.append(uv)

	# Triangles
	indices.append(base_idx)
	indices.append(base_idx + 1)
	indices.append(base_idx + 2)
	indices.append(base_idx)
	indices.append(base_idx + 2)
	indices.append(base_idx + 3)


## Add a wall on the west side of a tile (faces west, toward negative X)
func _add_west_wall(vertices: PackedVector3Array, normals: PackedVector3Array,
					uvs: PackedVector2Array, indices: PackedInt32Array,
					x: float, z: float, top: float, bottom: float,
					grid_x: int, grid_y: int) -> void:
	var base_idx = vertices.size()

	# Vertices for west wall (looking from west toward wall)
	vertices.append(Vector3(x, top, z))            # v0: top-right (from viewer)
	vertices.append(Vector3(x, top, z + 1.0))      # v1: top-left
	vertices.append(Vector3(x, bottom, z + 1.0))   # v2: bottom-left
	vertices.append(Vector3(x, bottom, z))         # v3: bottom-right

	# Normal points west (toward viewer = negative X)
	var n = Vector3(-1, 0, 0)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	normals.append(n)

	# UVs
	var uv = Vector2(float(grid_x) / float(map_width), float(grid_y) / float(map_height))
	uvs.append(uv)
	uvs.append(uv)
	uvs.append(uv)
	uvs.append(uv)

	# Triangles
	indices.append(base_idx)
	indices.append(base_idx + 1)
	indices.append(base_idx + 2)
	indices.append(base_idx)
	indices.append(base_idx + 2)
	indices.append(base_idx + 3)


## Add a wall on the east side of a tile (faces east, toward positive X)
func _add_east_wall(vertices: PackedVector3Array, normals: PackedVector3Array,
					uvs: PackedVector2Array, indices: PackedInt32Array,
					x: float, z: float, top: float, bottom: float,
					grid_x: int, grid_y: int) -> void:
	var base_idx = vertices.size()

	# Vertices for east wall (looking from east toward wall)
	vertices.append(Vector3(x + 1.0, top, z + 1.0))      # v0: top-right (from viewer)
	vertices.append(Vector3(x + 1.0, top, z))            # v1: top-left
	vertices.append(Vector3(x + 1.0, bottom, z))         # v2: bottom-left
	vertices.append(Vector3(x + 1.0, bottom, z + 1.0))   # v3: bottom-right

	# Normal points east (toward viewer = positive X)
	var n = Vector3(1, 0, 0)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	normals.append(n)

	# UVs
	var uv = Vector2(float(grid_x) / float(map_width), float(grid_y) / float(map_height))
	uvs.append(uv)
	uvs.append(uv)
	uvs.append(uv)
	uvs.append(uv)

	# Triangles
	indices.append(base_idx)
	indices.append(base_idx + 1)
	indices.append(base_idx + 2)
	indices.append(base_idx)
	indices.append(base_idx + 2)
	indices.append(base_idx + 3)


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
