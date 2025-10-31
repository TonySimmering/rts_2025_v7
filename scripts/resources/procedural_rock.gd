extends MeshInstance3D
class_name ProceduralRock

## Procedural rock mesh generator using noise-based deformation
## Creates unique rock shapes for gold and stone resource nodes

enum RockType {
	GOLD,
	STONE
}

@export var rock_type: RockType = RockType.STONE
@export var rock_seed: int = 0
@export var base_size: float = 1.5

# Noise parameters
var noise: FastNoiseLite
var noise_strength: float = 0.3
var noise_frequency: float = 2.0

# LOD settings
var lod_distances: Array[float] = [15.0, 30.0, 50.0]  # Distance thresholds for LOD levels
var current_lod: int = 0
var lod_meshes: Array[ArrayMesh] = []
var camera: Camera3D = null

# Material properties
var rock_material: StandardMaterial3D

func _ready():
	# Find camera for LOD calculation
	call_deferred("_find_camera")

func _find_camera():
	"""Find the main camera in the scene"""
	var viewport = get_viewport()
	if viewport:
		camera = viewport.get_camera_3d()

func _process(_delta):
	"""Update LOD based on distance to camera"""
	if camera and lod_meshes.size() > 0:
		var distance = global_position.distance_to(camera.global_position)
		var new_lod = _calculate_lod(distance)

		if new_lod != current_lod:
			current_lod = new_lod
			mesh = lod_meshes[current_lod] if current_lod < lod_meshes.size() else lod_meshes[0]

func _calculate_lod(distance: float) -> int:
	"""Calculate LOD level based on distance"""
	if distance > lod_distances[2]:
		return 2  # Lowest detail
	elif distance > lod_distances[1]:
		return 1  # Medium detail
	elif distance > lod_distances[0]:
		return 1  # Medium detail
	else:
		return 0  # Highest detail

func generate_rock(type: RockType, seed_value: int, size: float = 1.5):
	"""Generate a procedural rock mesh with the given parameters"""
	rock_type = type
	rock_seed = seed_value
	base_size = size

	# Setup noise
	_setup_noise()

	# Setup material
	_setup_material()

	# Generate all LOD levels
	_generate_lod_meshes()

	# Set initial mesh to highest detail
	if lod_meshes.size() > 0:
		mesh = lod_meshes[0]
		current_lod = 0

func _setup_noise():
	"""Initialize noise generator with parameters based on rock type"""
	noise = FastNoiseLite.new()
	noise.seed = rock_seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN

	if rock_type == RockType.GOLD:
		# Gold: smoother, more nugget-like
		noise.frequency = 1.5
		noise.fractal_octaves = 3
		noise_strength = 0.25
		noise_frequency = 1.5
	else:  # STONE
		# Stone: rougher, more irregular
		noise.frequency = 2.5
		noise.fractal_octaves = 4
		noise_strength = 0.35
		noise_frequency = 2.5

func _setup_material():
	"""Create PBR material based on rock type"""
	rock_material = StandardMaterial3D.new()

	if rock_type == RockType.GOLD:
		# Gold material: metallic with emission
		rock_material.albedo_color = Color(1.0, 0.84, 0.0)  # Gold color
		rock_material.metallic = 0.9
		rock_material.roughness = 0.3
		rock_material.emission_enabled = true
		rock_material.emission = Color(0.4, 0.33, 0.0)  # Subtle gold glow
		rock_material.emission_energy_multiplier = 0.3
	else:  # STONE
		# Stone material: rough and non-metallic
		rock_material.albedo_color = Color(0.5, 0.5, 0.5)  # Gray
		rock_material.metallic = 0.1
		rock_material.roughness = 0.8

	# Enable vertex colors for variation
	rock_material.vertex_color_use_as_albedo = true
	rock_material.vertex_color_is_srgb = true

	# Apply material
	set_surface_override_material(0, rock_material)

func _generate_lod_meshes():
	"""Generate all LOD levels for the rock"""
	lod_meshes.clear()

	# LOD 0: High detail (32 subdivisions)
	lod_meshes.append(_generate_rock_mesh(32))

	# LOD 1: Medium detail (16 subdivisions)
	lod_meshes.append(_generate_rock_mesh(16))

	# LOD 2: Low detail (8 subdivisions)
	lod_meshes.append(_generate_rock_mesh(8))

func _generate_rock_mesh(subdivisions: int) -> ArrayMesh:
	"""Generate a single rock mesh with specified subdivision level"""
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Create icosphere base
	var vertices: PackedVector3Array = []
	var indices: PackedInt32Array = []
	_create_icosphere(subdivisions, vertices, indices)

	# Apply noise deformation and vertex colors
	for i in range(vertices.size()):
		var vertex = vertices[i]

		# Get noise value for this vertex
		var noise_value = noise.get_noise_3d(
			vertex.x * noise_frequency,
			vertex.y * noise_frequency,
			vertex.z * noise_frequency
		)

		# Deform vertex outward/inward based on noise
		var deformation = 1.0 + noise_value * noise_strength
		vertex = vertex.normalized() * base_size * deformation

		# Calculate vertex color for variation
		var color_variation = (noise_value + 1.0) / 2.0  # Remap to 0-1
		var vertex_color: Color

		if rock_type == RockType.GOLD:
			# Gold: subtle color variation
			vertex_color = Color(
				lerp(0.9, 1.0, color_variation),
				lerp(0.75, 0.84, color_variation),
				0.0,
				1.0
			)
		else:  # STONE
			# Stone: more gray variation
			var gray = lerp(0.4, 0.6, color_variation)
			vertex_color = Color(gray, gray, gray, 1.0)

		# Add vertex with color
		surface_tool.set_color(vertex_color)
		surface_tool.add_vertex(vertex)

	# Add indices
	for i in range(0, indices.size(), 3):
		surface_tool.add_index(indices[i])
		surface_tool.add_index(indices[i + 1])
		surface_tool.add_index(indices[i + 2])

	# Generate normals for proper lighting
	surface_tool.generate_normals()

	# Commit mesh
	var array_mesh = surface_tool.commit()
	return array_mesh

func _create_icosphere(subdivisions: int, vertices: PackedVector3Array, indices: PackedInt32Array):
	"""Create an icosphere mesh (base for rock generation)"""
	# Start with icosahedron
	var t = (1.0 + sqrt(5.0)) / 2.0

	# 12 vertices of icosahedron
	var base_vertices = [
		Vector3(-1, t, 0).normalized(),
		Vector3(1, t, 0).normalized(),
		Vector3(-1, -t, 0).normalized(),
		Vector3(1, -t, 0).normalized(),

		Vector3(0, -1, t).normalized(),
		Vector3(0, 1, t).normalized(),
		Vector3(0, -1, -t).normalized(),
		Vector3(0, 1, -t).normalized(),

		Vector3(t, 0, -1).normalized(),
		Vector3(t, 0, 1).normalized(),
		Vector3(-t, 0, -1).normalized(),
		Vector3(-t, 0, 1).normalized()
	]

	# 20 faces of icosahedron
	var base_indices = [
		0, 11, 5,   0, 5, 1,    0, 1, 7,    0, 7, 10,   0, 10, 11,
		1, 5, 9,    5, 11, 4,   11, 10, 2,  10, 7, 6,   7, 1, 8,
		3, 9, 4,    3, 4, 2,    3, 2, 6,    3, 6, 8,    3, 8, 9,
		4, 9, 5,    2, 4, 11,   6, 2, 10,   8, 6, 7,    9, 8, 1
	]

	# Copy base vertices
	for v in base_vertices:
		vertices.append(v)

	# Copy base indices
	for i in base_indices:
		indices.append(i)

	# Subdivide faces
	for _level in range(subdivisions / 8):  # Adjust subdivision based on detail level
		var new_indices: PackedInt32Array = []

		for i in range(0, indices.size(), 3):
			var v1 = vertices[indices[i]]
			var v2 = vertices[indices[i + 1]]
			var v3 = vertices[indices[i + 2]]

			# Calculate midpoints
			var a = ((v1 + v2) / 2.0).normalized()
			var b = ((v2 + v3) / 2.0).normalized()
			var c = ((v3 + v1) / 2.0).normalized()

			# Add new vertices
			var idx1 = indices[i]
			var idx2 = indices[i + 1]
			var idx3 = indices[i + 2]

			var idx_a = vertices.size()
			vertices.append(a)
			var idx_b = vertices.size()
			vertices.append(b)
			var idx_c = vertices.size()
			vertices.append(c)

			# Create 4 new triangles
			new_indices.append(idx1)
			new_indices.append(idx_a)
			new_indices.append(idx_c)

			new_indices.append(idx2)
			new_indices.append(idx_b)
			new_indices.append(idx_a)

			new_indices.append(idx3)
			new_indices.append(idx_c)
			new_indices.append(idx_b)

			new_indices.append(idx_a)
			new_indices.append(idx_b)
			new_indices.append(idx_c)

		indices = new_indices

func get_collision_shape() -> ConvexPolygonShape3D:
	"""Generate a simplified collision shape for the rock"""
	var shape = ConvexPolygonShape3D.new()

	# Use the low-detail mesh for collision
	if lod_meshes.size() > 0:
		var collision_mesh = lod_meshes[lod_meshes.size() - 1]  # Use lowest LOD
		var faces = collision_mesh.get_faces()
		shape.points = faces

	return shape
