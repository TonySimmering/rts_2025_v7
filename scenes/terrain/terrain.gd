extends Node3D

# Terrain settings
@export_group("Terrain Size")
@export var terrain_width: int = 128
@export var terrain_depth: int = 128
@export var terrain_scale: float = 1.0

@export_group("Height Settings")
@export var max_height: float = 3.0
@export var min_height: float = -1.0

@export_group("Noise Settings")
@export var noise_frequency: float = 0.02
@export var noise_octaves: int = 3
@export var noise_lacunarity: float = 2.0
@export var noise_gain: float = 0.4

@export_group("Resource Spawning")
@export var spawn_resources: bool = true
@export var num_gold_nodes: int = 8
@export var num_wood_nodes: int = 12
@export var num_stone_nodes: int = 12

@export_group("Generation")
@export var auto_generate: bool = false

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var terrain_mesh_instance: MeshInstance3D = $NavigationRegion3D/TerrainMesh
@onready var terrain_collision: StaticBody3D = $NavigationRegion3D/TerrainCollision
@onready var collision_shape: CollisionShape3D = $NavigationRegion3D/TerrainCollision/CollisionShape3D

const RESOURCE_NODE_SCENE = preload("res://scripts/resources/resource_node.tscn")

var noise: FastNoiseLite
var heightmap: Array = []
var terrain_seed: int = 0

func _ready():
	auto_generate = false
	print("Terrain _ready() - auto_generate forcibly set to false")

func generate_terrain(seed_value: int):
	terrain_seed = seed_value
	print("Generating terrain with seed: ", terrain_seed)
	setup_noise(terrain_seed)
	generate_heightmap()
	create_mesh()
	create_collision()
	await bake_navigation()
	
	# Spawn resources after navigation is ready
	if spawn_resources and multiplayer.is_server():
		spawn_resource_nodes()
	
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
	
	terrain_collision.collision_layer = 1
	terrain_collision.collision_mask = 1
	
	print("  Collision created with ", faces.size() / 3, " triangles")

func bake_navigation():
	print("  Baking navigation mesh...")
	
	if navigation_region.navigation_mesh == null:
		navigation_region.navigation_mesh = NavigationMesh.new()
	
	var nav_mesh = navigation_region.navigation_mesh
	
	nav_mesh.cell_size = 1.0
	nav_mesh.cell_height = 0.2
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = 0.3
	nav_mesh.agent_max_climb = 3.0
	nav_mesh.agent_max_slope = 60.0
	nav_mesh.region_min_size = 0.5
	nav_mesh.detail_sample_distance = 6.0
	nav_mesh.detail_sample_max_error = 1.0
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var source_geometry = NavigationMeshSourceGeometryData3D.new()
	var mesh_faces = terrain_mesh_instance.mesh.get_faces()
	var mesh_transform = terrain_mesh_instance.global_transform
	source_geometry.add_faces(mesh_faces, mesh_transform)
	
	print("  Added ", mesh_faces.size() / 3, " triangles to source geometry")
	
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geometry)
	
	var poly_count = nav_mesh.get_polygon_count()
	print("  NavMesh baked! Polygons: ", poly_count)
	
	if poly_count < 500:
		push_warning("  ⚠ Low NavMesh coverage! Only ", poly_count, " polygons")
	
	navigation_region.enabled = false
	await get_tree().process_frame
	navigation_region.enabled = true
	
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var world_nav_map = get_world_3d().navigation_map
	print("  World navigation map RID: ", world_nav_map)
	print("  NavigationRegion map RID: ", navigation_region.get_navigation_map())

func spawn_resource_nodes():
	"""Spawn resource nodes across the terrain (server only)"""
	if not multiplayer.is_server():
		print("⚠ Not server, skipping resource spawn")
		return
	
	print("\n=== SPAWNING RESOURCES ===")
	print("Is Server: ", multiplayer.is_server())
	print("Num gold: ", num_gold_nodes)
	print("Num wood: ", num_wood_nodes)
	print("Num stone: ", num_stone_nodes)
	
	# Spawn gold
	for i in range(num_gold_nodes):
		spawn_resource(0, i)  # Type 0 = Gold
	
	# Spawn wood
	for i in range(num_wood_nodes):
		spawn_resource(1, i)  # Type 1 = Wood
	
	# Spawn stone
	for i in range(num_stone_nodes):
		spawn_resource(2, i)  # Type 2 = Stone
	
	print("✓ Resource spawning complete!")
	print("Total resources in scene: ", get_tree().get_nodes_in_group("resource_nodes").size())
	print("=========================\n")

func spawn_resource(resource_type: int, index: int):
	"""Spawn a single resource node"""
	var max_attempts = 50
	var nav_map = get_world_3d().navigation_map
	
	print("\n[SPAWN ATTEMPT] Type: ", resource_type, " Index: ", index)
	
	for attempt in range(max_attempts):
		# Random position on terrain
		var random_x = randf_range(10, terrain_width - 10)
		var random_z = randf_range(10, terrain_depth - 10)
		var test_pos = Vector3(random_x, 0, random_z)
		
		# Get valid NavMesh position
		var valid_pos = NavigationServer3D.map_get_closest_point(nav_map, test_pos)
		
		var distance_to_navmesh = valid_pos.distance_to(test_pos)
		
		# Much more lenient check - accept if within 15 units
		if distance_to_navmesh > 15.0:
			if attempt % 10 == 0:
				print("  Attempt ", attempt, ": Too far from NavMesh (", distance_to_navmesh, "m)")
			continue
		
		# Check minimum distance from other resources (reduced to 5.0)
		var too_close = false
		for existing in get_tree().get_nodes_in_group("resource_nodes"):
			if existing.global_position.distance_to(valid_pos) < 5.0:
				too_close = true
				break
		
		if too_close:
			if attempt % 10 == 0:
				print("  Attempt ", attempt, ": Too close to existing resource")
			continue
		
		# Success! Spawn the resource
		print("  ✓ SUCCESS on attempt ", attempt + 1)
		print("    Test pos: ", test_pos)
		print("    Valid pos: ", valid_pos)
		print("    Distance to NavMesh: ", distance_to_navmesh, "m")
		spawn_resource_rpc.rpc(resource_type, valid_pos, index)
		return
	
	print("  ✗ FAILED after ", max_attempts, " attempts")
	print("    NavMesh might be too sparse or disconnected")
	
	# Fallback: spawn without NavMesh validation
	print("  → Using fallback spawn (no NavMesh check)")
	var fallback_pos = Vector3(
		randf_range(20, terrain_width - 20),
		0,
		randf_range(20, terrain_depth - 20)
	)
	spawn_resource_rpc.rpc(resource_type, fallback_pos, index)

@rpc("authority", "call_local", "reliable")
func spawn_resource_rpc(resource_type: int, position: Vector3, index: int):
	"""Spawn resource on all clients"""
	var type_names = ["Gold", "Wood", "Stone"]
	print("\n[SPAWN_RESOURCE_RPC] Called on peer ", multiplayer.get_unique_id())
	print("  Type: ", type_names[resource_type])
	print("  Position: ", position)
	print("  Index: ", index)
	
	var resource_node = RESOURCE_NODE_SCENE.instantiate()
	print("  ✓ Resource node instantiated: ", resource_node)
	
	resource_node.resource_type = resource_type
	print("  ✓ Resource type set")
	
	resource_node.global_position = position
	resource_node.name = "Resource_%d_%d" % [resource_type, index]
	print("  ✓ Position and name set: ", resource_node.name)
	
	# Add to navigation region parent so it's in the same coordinate space
	navigation_region.add_child(resource_node)
	print("  ✓ Added to scene tree")
	print("  Final position: ", resource_node.global_position)
	print("  Is in group 'resource_nodes': ", resource_node.is_in_group("resource_nodes"))
	print("")

func get_height_at_position(world_pos: Vector3) -> float:
	var local_x = int(world_pos.x / terrain_scale)
	var local_z = int(world_pos.z / terrain_scale)
	
	local_x = clamp(local_x, 0, terrain_width - 1)
	local_z = clamp(local_z, 0, terrain_depth - 1)
	
	if local_z < heightmap.size() and local_x < heightmap[local_z].size():
		return heightmap[local_z][local_x]
	return 0.0
