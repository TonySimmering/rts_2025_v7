extends Node3D

# Terrain settings
@export_group("Terrain Size")
@export var terrain_width: int = 128
@export var terrain_depth: int = 128
@export var terrain_scale: float = 1.0

@export_group("Height Settings")
@export var max_height: float = 3.0  # CHANGED from 10.0
@export var min_height: float = -1.0  # CHANGED from -10.0

@export_group("Noise Settings")
@export var noise_frequency: float = 0.02  # CHANGED from 0.05 - larger features
@export var noise_octaves: int = 3  # CHANGED from 4 - smoother
@export var noise_lacunarity: float = 2.0  # Same
@export var noise_gain: float = 0.4  # CHANGED from 0.5 - less detail influence

@export_group("Generation")
@export var auto_generate: bool = false

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var terrain_mesh_instance: MeshInstance3D = $NavigationRegion3D/TerrainMesh
@onready var terrain_collision: StaticBody3D = $NavigationRegion3D/TerrainCollision  # UPDATED PATH
@onready var collision_shape: CollisionShape3D = $NavigationRegion3D/TerrainCollision/CollisionShape3D  # UPDATED PATH

var noise: FastNoiseLite
var heightmap: Array = []
var terrain_seed: int = 0

func _ready():
	# Force auto_generate to false, regardless of what's saved in scene
	auto_generate = false
	print("Terrain _ready() - auto_generate forcibly set to false")

func generate_terrain(seed_value: int):
	terrain_seed = seed_value
	print("Generating terrain with seed: ", terrain_seed)
	setup_noise(terrain_seed)
	generate_heightmap()
	create_mesh()
	create_collision()
	await bake_navigation()  # IMPORTANT: await this
	print("Terrain generation complete!")

func setup_noise(seed_value: int):
	noise = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = noise_frequency
	noise.fractal_octaves = noise_octaves
	noise.fractal_lacunarity = noise_lacunarity
	noise.fractal_gain = noise_gain
	noise.noise_type = FastNoiseLite.TYPE_PERLIN

func generate_heightmap():
	heightmap.clear()
	heightmap.resize(terrain_depth)
	
	for z in terrain_depth:
		heightmap[z] = []
		heightmap[z].resize(terrain_width)
		for x in terrain_width:
			var noise_value = noise.get_noise_2d(x, z)
			var height = remap(noise_value, -1.0, 1.0, min_height, max_height)
			heightmap[z][x] = height

func create_mesh():
	var surface_tool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate vertices and UVs
	for z in terrain_depth:
		for x in terrain_width:
			var height = heightmap[z][x]
			var vertex_pos = Vector3(
				x * terrain_scale,
				height,
				z * terrain_scale
			)
			
			var uv = Vector2(
				float(x) / float(terrain_width - 1),
				float(z) / float(terrain_depth - 1)
			)
			
			surface_tool.set_uv(uv)
			surface_tool.add_vertex(vertex_pos)
	
	# Generate triangles
	for z in terrain_depth - 1:
		for x in terrain_width - 1:
			var i = z * terrain_width + x
			
			surface_tool.add_index(i)
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + terrain_width)
			
			surface_tool.add_index(i + 1)
			surface_tool.add_index(i + terrain_width + 1)
			surface_tool.add_index(i + terrain_width)
	
	surface_tool.generate_normals()
	
	var mesh = surface_tool.commit()
	terrain_mesh_instance.mesh = mesh
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.6, 0.2)
	terrain_mesh_instance.set_surface_override_material(0, material)

func create_collision():
	var shape = ConcavePolygonShape3D.new()
	var faces = terrain_mesh_instance.mesh.get_faces()
	shape.set_faces(faces)
	collision_shape.shape = shape
	
	# Ensure collision is on the right layer
	terrain_collision.collision_layer = 1
	terrain_collision.collision_mask = 1
	
	print("  Collision created with ", faces.size() / 3, " triangles")


func bake_navigation():
	print("  Baking navigation mesh...")
	
	if navigation_region.navigation_mesh == null:
		navigation_region.navigation_mesh = NavigationMesh.new()
	
	var nav_mesh = navigation_region.navigation_mesh
	
	nav_mesh.cell_size = 0.5
	nav_mesh.cell_height = 0.5
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_max_climb = 2.0
	nav_mesh.agent_max_slope = 45.0
	nav_mesh.region_min_size = 2.0
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Create source geometry manually
	var source_geometry = NavigationMeshSourceGeometryData3D.new()
	var mesh_faces = terrain_mesh_instance.mesh.get_faces()
	var mesh_transform = terrain_mesh_instance.global_transform
	source_geometry.add_faces(mesh_faces, mesh_transform)
	
	print("  Added ", mesh_faces.size() / 3, " triangles to source geometry")
	print("  Mesh transform: ", mesh_transform)
	
	# Bake from source geometry
	print("  Baking from source geometry...")
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geometry)
	
	var poly_count = nav_mesh.get_polygon_count()
	print("  NavMesh baked! Polygons: ", poly_count)
	
	# CRITICAL: Force NavigationRegion to update by toggling it
	navigation_region.enabled = false
	await get_tree().process_frame
	navigation_region.enabled = true
	
	# Wait for NavigationServer to register
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Verify
	var world_nav_map = get_world_3d().navigation_map
	print("  World navigation map RID: ", world_nav_map)
	print("  NavigationRegion map RID: ", navigation_region.get_navigation_map())
	
	# Test if NavMesh is accessible
	var test_point = Vector3(64, 0, 64)  # Center of map
	var closest = NavigationServer3D.map_get_closest_point(world_nav_map, test_point)
	print("  Test: Closest point to (64,0,64): ", closest)
	print("  Test: Distance: ", test_point.distance_to(closest))
		
func get_height_at_position(world_pos: Vector3) -> float:
	var local_x = int(world_pos.x / terrain_scale)
	var local_z = int(world_pos.z / terrain_scale)
	
	local_x = clamp(local_x, 0, terrain_width - 1)
	local_z = clamp(local_z, 0, terrain_depth - 1)
	
	if local_z < heightmap.size() and local_x < heightmap[local_z].size():
		return heightmap[local_z][local_x]
	return 0.0
